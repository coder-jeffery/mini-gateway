local redis_util = require "redis_util"
local ngx = ngx

-- 配置
local RATE_LIMIT = 10
local RATE_WINDOW = 60

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

-- 校验 API Key
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

-- ========== IP白名单判断 ==========
local in_whitelist, err = red:sismember("whitelist:ip", ip)
if err then
    redis_util.close(red)
    ngx.log(ngx.ERR, "sismember err: ", err)
    return deny(500, "redis error")
end

-- 白名单命中：跳过限流，直接放行
if in_whitelist == 1 then
    redis_util.close(red)
    ngx.header["X-RateLimit-Whitelist"] = "true"
    return
end

-- ========== 滑动窗口限流（Pipeline） ==========
local now = ngx.now()
local window_start = now - RATE_WINDOW
local limit_key = "ratelimit:sw:ip:" .. ip
local unique_id = now .. ":" .. ngx.var.pid .. ":" .. math.random()

red:init_pipeline()
red:zremrangebyscore(limit_key, 0, window_start)
red:zcard(limit_key)
red:zadd(limit_key, now, unique_id)
red:expire(limit_key, RATE_WINDOW + 10)
local res, err = red:commit_pipeline()
if not res then
    redis_util.close(red)
    ngx.log(ngx.ERR, "pipeline err: ", err)
    return deny(500, "redis pipeline error")
end

local cnt = res[2]
local remaining = RATE_LIMIT - cnt
local reset_ts = math.ceil(now + RATE_WINDOW)

-- 设置标准限流响应头
ngx.header["X-RateLimit-Limit"] = RATE_LIMIT
ngx.header["X-RateLimit-Remaining"] = math.max(0, remaining)
ngx.header["X-RateLimit-Reset"] = reset_ts

if cnt >= RATE_LIMIT then
    redis_util.close(red)
    return deny(429, "too many requests, rate limited")
end

redis_util.close(red)
return
