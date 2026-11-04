
local redis_util = require "redis_util"
local ngx = ngx

-- Config
local RATE_LIMIT = 10    -- max 10 requests per IP per window
local RATE_WINDOW = 60   -- window size (seconds)

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
    ngx.log(ngx.ERR, err)
    return deny(500, "redis error")
end

-- apikey:{key} must exist
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

-- Fixed-window counter: ratelimit:ip:{ip}
local limit_key = "ratelimit:ip:" .. ip
local count, err = red:incr(limit_key)
if err then
    redis_util.close(red)
    return deny(500, "redis error")
end
-- Set TTL on first increment
if count == 1 then
    red:expire(limit_key, RATE_WINDOW)
end

if count > RATE_LIMIT then
    redis_util.close(red)
    return deny(429, "too many requests")
end

redis_util.close(red)
-- All checks passed
return
