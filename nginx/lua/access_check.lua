-- API key auth, quotas, whitelist, sliding-window rate limit, circuit breaker (redis only)

local store_mod = require "store"
local ngx = ngx

local CIRCUIT_BREAK_POLICY = "pass"
local DEFAULT_RATE_LIMIT = 10
local DEFAULT_RATE_WINDOW = 60

local function deny(status, msg)
    ngx.status = status
    ngx.header["Content-Type"] = "application/json"
    ngx.say('{"code":'..status..',"msg":"'..msg..'"}')
    return ngx.exit(status)
end

local function handle_storage_outage()
    ngx.header["X-Gateway-Storage-Degraded"] = "true"
    ngx.header["X-Gateway-Storage"] = store_mod.name()
    if store_mod.name() ~= "redis" then
        return deny(503, "storage unavailable")
    end
    ngx.header["X-Redis-Circuit-Break"] = "true"
    if CIRCUIT_BREAK_POLICY == "reject" then
        return deny(503, "circuit break: redis unavailable")
    end
    ngx.header["X-RateLimit-Limit"] = DEFAULT_RATE_LIMIT
    ngx.header["X-RateLimit-Remaining"] = -1
    ngx.header["X-RateLimit-Reset"] = math.ceil(ngx.now() + DEFAULT_RATE_WINDOW)
    return
end

local api_key = ngx.var.http_x_api_key
if not api_key or api_key == "" then
    return deny(401, "missing X-Api-Key header")
end

local ip = ngx.var.remote_addr
local backend = store_mod.backend()
local handle, err = backend.new()
if not handle then
    ngx.log(ngx.ERR, "storage open fail: ", err)
    return handle_storage_outage()
end

ngx.header["X-Gateway-Storage"] = store_mod.name()

local key_exist, err = backend.exists(handle, "apikey:" .. api_key)
if err then
    backend.close(handle)
    ngx.log(ngx.ERR, "storage exists err: ", err)
    return handle_storage_outage()
end
if key_exist ~= 1 then
    backend.close(handle)
    return deny(401, "invalid api key")
end

local meta, err = backend.hmget(handle, "apikey:meta:" .. api_key, "limit", "window")
if err then
    backend.close(handle)
    ngx.log(ngx.ERR, "storage hmget err: ", err)
    return handle_storage_outage()
end
local rate_limit  = tonumber(meta[1]) or DEFAULT_RATE_LIMIT
local rate_window = tonumber(meta[2]) or DEFAULT_RATE_WINDOW

local in_whitelist, err = backend.sismember(handle, "whitelist:ip", ip)
if err then
    backend.close(handle)
    ngx.log(ngx.ERR, "storage sismember err: ", err)
    return handle_storage_outage()
end

if in_whitelist == 1 then
    backend.close(handle)
    ngx.header["X-RateLimit-Whitelist"] = "true"
    ngx.header["X-RateLimit-Limit"] = rate_limit
    ngx.header["X-RateLimit-Remaining"] = -1
    ngx.header["X-RateLimit-Reset"] = math.ceil(ngx.now() + rate_window)
    return
end

local now = ngx.now()
local limit_key = "ratelimit:sw:key:" .. api_key
local unique_id = now .. ":" .. ngx.var.pid .. ":" .. math.random()

local cnt, err = backend.sliding_window(handle, limit_key, rate_window, now, unique_id)
if err then
    backend.close(handle)
    ngx.log(ngx.ERR, "storage rate limit err: ", err)
    return handle_storage_outage()
end

local remaining = rate_limit - cnt
local reset_ts = math.ceil(now + rate_window)

ngx.header["X-RateLimit-Limit"] = rate_limit
ngx.header["X-RateLimit-Remaining"] = math.max(0, remaining)
ngx.header["X-RateLimit-Reset"] = reset_ts

if cnt >= rate_limit then
    backend.close(handle)
    ngx.header["Retry-After"] = reset_ts - math.ceil(ngx.now())
    return deny(429, "too many requests, rate limited")
end

backend.close(handle)
return
