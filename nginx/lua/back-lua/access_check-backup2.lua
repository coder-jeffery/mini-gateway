
local redis_util = require "redis_util"
local ngx = ngx

-- Config: 10 requests per IP per 60s
local RATE_LIMIT = 10
local RATE_WINDOW = 60

local function deny(status, msg)
    ngx.status = status
    ngx.header["Content-Type"] = "application/json"
    ngx.say('{"code":'..status..',"msg":"'..msg..'"}')
    return ngx.exit(status)
end

-- 1. Read API key
local api_key = ngx.var.http_x_api_key
if not api_key or api_key == "" then
    return deny(401, "missing X-Api-Key header")
end

-- 2. Client IP
local ip = ngx.var.remote_addr

local red, err = redis_util.new()
if not red then
    ngx.log(ngx.ERR, "redis connect fail: ", err)
    return deny(500, "redis service unavailable")
end

-- Validate API key
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

-- Sliding-window rate limit (ZSet)
local now = ngx.now() -- float seconds
local window_start = now - RATE_WINDOW
local limit_key = "ratelimit:sw:ip:" .. ip

-- Trim entries outside the window
red:zremrangebyscore(limit_key, 0, window_start)

-- Count requests in current window
local cnt, err = red:zcard(limit_key)
if err then
    redis_util.close(red)
    ngx.log(ngx.ERR, "zcard err: ", err)
    return deny(500, "redis error")
end

if cnt >= RATE_LIMIT then
    redis_util.close(red)
    print()
    return deny(429, "too many requests, rate limited")
end

-- Record this request; unique member avoids ZSet dedup
local unique_id = now .. ":" .. ngx.var.pid .. ":" .. math.random()
red:zadd(limit_key, now, unique_id)
-- Key TTL to avoid stale ZSet growth
red:expire(limit_key, RATE_WINDOW + 10)

redis_util.close(red)
-- All checks passed
return
