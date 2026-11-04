-- API key authentication
-- Per-key dynamic quota in Redis (limit/window)
-- IP whitelist
-- ZSet sliding-window rate limit + pipeline
-- Standard X-RateLimit-* + Retry-After
-- Redis failure circuit breaker (pass/reject)

local redis_util = require "redis_util"
local ngx = ngx

-- Toggle circuit breaker policy here
-- local CIRCUIT_BREAK_POLICY = "reject"  -- reject all when Redis is down (503)
local CIRCUIT_BREAK_POLICY = "pass"     -- bypass auth and rate limit when Redis is down
local DEFAULT_RATE_LIMIT = 10
local DEFAULT_RATE_WINDOW = 60

local function deny(status, msg)
    ngx.status = status
    ngx.header["Content-Type"] = "application/json"
    ngx.say('{"code":'..status..',"msg":"'..msg..'"}')
    return ngx.exit(status)
end

local function handle_circuit_break()
    print("circuit break >>>>>>>>>>>>>>>>>>>>>>>>>>>>")
    ngx.header["X-Redis-Circuit-Break"] = "true"
    if CIRCUIT_BREAK_POLICY == "reject" then
        return deny(503, "circuit break: redis unavailable")
    else
        -- pass: skip auth and rate limiting
        ngx.header["X-RateLimit-Limit"] = DEFAULT_RATE_LIMIT
        ngx.header["X-RateLimit-Remaining"] = -1
        ngx.header["X-RateLimit-Reset"] = math.ceil(ngx.now() + DEFAULT_RATE_WINDOW)
        return
    end
end

local api_key = ngx.var.http_x_api_key
if not api_key or api_key == "" then
    return deny(401, "missing X-Api-Key header")
end

local ip = ngx.var.remote_addr

local red, err = redis_util.new()
if not red then
    ngx.log(ngx.ERR, "redis connect fail: ", err)
    return handle_circuit_break()
end

local key_exist, err = red:exists("apikey:" .. api_key)
if err then
    redis_util.close(red)
    ngx.log(ngx.ERR, "redis exists err: ", err)
    return handle_circuit_break()
end
if key_exist ~= 1 then
    redis_util.close(red)
    return deny(401, "invalid api key")
end

local meta_key = "apikey:meta:" .. api_key
local meta, err = red:hmget(meta_key, "limit", "window")
if err then
    redis_util.close(red)
    ngx.log(ngx.ERR, "hmget meta err: ", err)
    return handle_circuit_break()
end
local rate_limit  = tonumber(meta[1]) or DEFAULT_RATE_LIMIT
local rate_window = tonumber(meta[2]) or DEFAULT_RATE_WINDOW

local in_whitelist, err = red:sismember("whitelist:ip", ip)
if err then
    redis_util.close(red)
    ngx.log(ngx.ERR, "sismember err: ", err)
    return handle_circuit_break()
end

if in_whitelist == 1 then
    redis_util.close(red)
    ngx.header["X-RateLimit-Whitelist"] = "true"
    ngx.header["X-RateLimit-Limit"] = rate_limit
    ngx.header["X-RateLimit-Remaining"] = -1
    ngx.header["X-RateLimit-Reset"] = math.ceil(ngx.now() + rate_window)
    return
end

-- Sliding-window rate limit (pipeline)
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
    return handle_circuit_break()
end

local cnt = res[2]
local remaining = rate_limit - cnt
local reset_ts = math.ceil(now + rate_window)

ngx.header["X-RateLimit-Limit"] = rate_limit
ngx.header["X-RateLimit-Remaining"] = math.max(0, remaining)
ngx.header["X-RateLimit-Reset"] = reset_ts

if cnt >= rate_limit then
    print("rate limited >>>>>>>>>>>>>>>>>>>>>>>>>>>> key: ", limit_key)
    redis_util.close(red)
    ngx.header["Retry-After"] = reset_ts - math.ceil(ngx.now())
    return deny(429, "too many requests, rate limited")
end

redis_util.close(red)
return
