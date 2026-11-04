local redis_util = require "redis_util"
local ngx = ngx

-- 配置：单IP 60s最多10次
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


-- 方式一 ========== 滑动窗口限流（ZSet） ==========
-- local now = ngx.now() -- 浮点数，单位秒
-- local window_start = now - RATE_WINDOW
-- local limit_key = "ratelimit:sw:ip:" .. ip

-- -- 清理窗口之前的旧记录
-- red:zremrangebyscore(limit_key, 0, window_start)

-- -- 统计当前窗口内请求数量
-- local cnt, err = red:zcard(limit_key)
-- if err then
--     redis_util.close(red)
--     ngx.log(ngx.ERR, "zcard err: ", err)
--     return deny(500, "redis error")
-- end

-- if cnt >= RATE_LIMIT then
--     redis_util.close(red)
--     return deny(429, "too many requests, rate limited")
-- end

-- 方式二 ========== Pipeline 滑动窗口限流 ==========
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


if cnt >= RATE_LIMIT then
    redis_util.close(red)
    print("limit key >>>>>> ", limit_key)
    return deny(429, "too many requests, rate limited")
end

-- 插入本次请求记录；member要唯一，防止zset去重吞请求
local unique_id = now .. ":" .. ngx.var.pid .. ":" .. math.random()
red:zadd(limit_key, now, unique_id)
-- zset整体过期，防止长期堆积冷key（自动清理兜底）
red:expire(limit_key, RATE_WINDOW + 10)

redis_util.close(red)
-- 全部校验通过，放行
return
