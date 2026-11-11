-- API key / OAuth2 Bearer auth, quotas, whitelist, sliding-window rate limit

local store_mod = require "store"
local config = require "gateway_config"
local oauth = require "oauth_validate"
local cors = require "cors"
local cjson = require "cjson"
local ngx = ngx

local CIRCUIT_BREAK_POLICY = "pass"
local DEFAULT_RATE_LIMIT = 10
local DEFAULT_RATE_WINDOW = 60

if cors.is_preflight() then
    return cors.handle_preflight()
end

local function deny(status, msg)
    ngx.status = status
    ngx.header["Content-Type"] = "application/json"
    ngx.say(cjson.encode({ code = status, msg = msg }))
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

-- Returns rate_limit_key, rate_limit, rate_window, auth_label or nil + deny
local function resolve_identity()
    local mode = config.auth_mode()
    local bearer = oauth.extract_bearer()
    local api_key = ngx.var.http_x_api_key

    if bearer and bearer ~= "" then
        if mode == "api_key" then
            return deny(401, "bearer token not accepted in api_key auth mode")
        end
        local claims, err, status = oauth.validate(bearer)
        if not claims then
            return deny(status or 401, err or "invalid token")
        end
        local identity = oauth.rate_limit_identity(claims)
        ngx.ctx.auth_type = "oauth2"
        ngx.ctx.auth_subject = identity
        ngx.header["X-Gateway-Auth"] = "oauth2"
        ngx.header["X-Gateway-Auth-Subject"] = identity
        return {
            rate_key = "ratelimit:sw:oauth:" .. identity,
            limit = config.oauth2_default_limit(),
            window = config.oauth2_default_window(),
            use_apikey_store = false,
        }
    end

    if mode == "bearer" then
        return deny(401, "missing Authorization Bearer token")
    end

    if not api_key or api_key == "" then
        if mode == "both" then
            return deny(401, "missing Authorization Bearer token or X-Api-Key header")
        end
        return deny(401, "missing X-Api-Key header")
    end

    ngx.ctx.auth_type = "api_key"
    ngx.ctx.auth_subject = api_key
    ngx.header["X-Gateway-Auth"] = "api_key"

    return {
        rate_key = "ratelimit:sw:key:" .. api_key,
        limit = nil,
        window = nil,
        use_apikey_store = true,
        api_key = api_key,
    }
end

local identity = resolve_identity()
if not identity then
    return
end

local ip = ngx.var.remote_addr
local backend = store_mod.backend()
local handle, err = backend.new()
if not handle then
    ngx.log(ngx.ERR, "storage open fail: ", err)
    return handle_storage_outage()
end

ngx.header["X-Gateway-Storage"] = store_mod.name()

local rate_limit = identity.limit
local rate_window = identity.window

if identity.use_apikey_store then
    local api_key = identity.api_key
    local key_exist, err_exists = backend.exists(handle, "apikey:" .. api_key)
    if err_exists then
        backend.close(handle)
        ngx.log(ngx.ERR, "storage exists err: ", err_exists)
        return handle_storage_outage()
    end
    if key_exist ~= 1 then
        backend.close(handle)
        return deny(401, "invalid api key")
    end

    local meta, err_meta = backend.hmget(handle, "apikey:meta:" .. api_key, "limit", "window")
    if err_meta then
        backend.close(handle)
        ngx.log(ngx.ERR, "storage hmget err: ", err_meta)
        return handle_storage_outage()
    end
    rate_limit = tonumber(meta[1]) or DEFAULT_RATE_LIMIT
    rate_window = tonumber(meta[2]) or DEFAULT_RATE_WINDOW
end

local in_whitelist, err_wl = backend.sismember(handle, "whitelist:ip", ip)
if err_wl then
    backend.close(handle)
    ngx.log(ngx.ERR, "storage sismember err: ", err_wl)
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
local limit_key = identity.rate_key
local unique_id = now .. ":" .. ngx.var.pid .. ":" .. math.random()

local cnt, err_rl = backend.sliding_window(handle, limit_key, rate_window, now, unique_id)
if err_rl then
    backend.close(handle)
    ngx.log(ngx.ERR, "storage rate limit err: ", err_rl)
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
