
local redis_util = require "redis_util"
local ngx = ngx

-- 兜底默认配额：meta读取失败、字段缺失时使用
local DEFAULT_RATE_LIMIT = 10
local DEFAULT_RATE_WINDOW = 60

local function deny(status, msg)
    ngx.status = status
    ngx.header["Content-Type"] = "application/json"
    ngx.say('{"code":'..status..',"msg":"'..msg..'"}')
    return ngx.exit(status)
end

-- 1. 读取 ApiKey
local api_key = ngx.var.http_x_api_key
if not api_key or api_key == "" then
    return deny(401, "missing X-Api-Key header")
end

-- 2. 获取客户端真实IP
local ip = ngx.var.remote_addr

local red, err = redis_util.new()
if not red then
    ngx.log(ngx.ERR, "redis connect fail: ", err)
    return deny(500, "redis service unavailable")
end

-- 校验 apikey 是否合法（存在）
local key_exist, err = red:exists("apikey:" .. api_key)
if err then
    redis_util.close(red)
    ngx.log(ngx.ERR, "redis exists err: ", err)
    return deny(500, "redis error")
end
if key_exist ~= 1 then
    redis_util.close(red)
    return deny(401, "invalid api key")
end

-- ========== 读取该 apikey 动态配额 meta ==========
local meta_key = "apikey:meta:" .. api_key
local meta, err = red:hmget(meta_key, "limit", "window")
if err then
    redis_util.close(red)
    ngx.log(ngx.ERR, "hmget meta err: ", err)
    return deny(500, "redis error")
end
-- hmget 返回数组：meta[1]=limit, meta[2]=window
local rate_limit  = tonumber(meta[1]) or DEFAULT_RATE_LIMIT
local rate_window = tonumber(meta[2]) or DEFAULT_RATE_WINDOW

-- ========== IP白名单判断，白名单直接跳过限流 ==========
local in_whitelist, err = red:sismember("whitelist:ip", ip)
if err then
    redis_util.close(red)
    ngx.log(ngx.ERR, "sismember err: ", err)
    return deny(500, "redis error")
end
if in_whitelist == 1 then
    redis_util.close(red)
    ngx.header["X-RateLimit-Whitelist"] = "true"
    return
end

-- ========== 滑动窗口限流：维度【按 apikey】 ==========
local now = ngx.now()
local window_start = now - rate_window
local limit_key = "ratelimit:sw:key:" .. api_key
local unique_id = now .. ":" .. ngx.var.pid .. ":" .. math.random()

red:init_pipeline()
red:zremrangebyscore(limit_key, 0, window_start)
red:zcard(limit_key)
red:zadd(limit_key, now, unique_id)
red:expire(limit_key, rate_window + 10)
local res, err = red:commit_pipeline()
if not res then
    redis_util.close(red)
    ngx.log(ngx.ERR, "pipeline err: ", err)
    return deny(500, "redis pipeline error")
end

local cnt = res[2]
local remaining = rate_limit - cnt
local reset_ts = math.ceil(now + rate_window)

ngx.header["X-RateLimit-Limit"] = rate_limit
ngx.header["X-RateLimit-Remaining"] = math.max(0, remaining)
ngx.header["X-RateLimit-Reset"] = reset_ts

if cnt >= rate_limit then
    redis_util.close(red)
    return deny(429, "too many requests, rate limited")
end

redis_util.close(red)
return
