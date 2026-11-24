-- API key / OAuth2 Bearer auth, quotas, whitelist, sliding-window rate limit

local store_mod = require "store"
local config = require "gateway_config"
local oauth = require "oauth_validate"
local storage_circuit = require "storage_circuit"
local config_cache = require "config_cache"
local policy = require "data_plane_policy"
local metrics = require "gateway_metrics"
local business_hmac = require "business_hmac"
local rate_warmup = require "rate_warmup"
local leaky_bucket = require "leaky_bucket"
local cjson = require "cjson"
local ngx = ngx

local DEFAULT_RATE_LIMIT = config.storage_cb_degraded_default_limit()
local DEFAULT_RATE_WINDOW = config.storage_cb_degraded_default_window()

local function deny(status, msg)
    ngx.status = status
    ngx.header["Content-Type"] = "application/json"
    ngx.say(cjson.encode({ code = status, msg = msg }))
    return ngx.exit(status)
end

local function storage_fail()
    storage_circuit.record_failure()
    return handle_storage_outage()
end

local function handle_storage_outage()
    ngx.header["X-Gateway-Storage-Degraded"] = "true"
    ngx.header["X-Gateway-Storage"] = store_mod.name()
    ngx.header["X-Storage-Circuit-State"] = storage_circuit.current_state()
    ngx.header["X-Redis-Circuit-Break"] = "true"
    if config.storage_cb_policy() == "reject" then
        return deny(503, "circuit break: storage unavailable")
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

if not storage_circuit.allow_storage() then
    return handle_storage_outage()
end

local ip = ngx.var.remote_addr
local backend = store_mod.backend()
local handle, err = backend.new()
if not handle then
    ngx.log(ngx.ERR, "storage open fail: ", err)
    return storage_fail()
end

ngx.header["X-Gateway-Storage"] = store_mod.name()

local block_status, block_msg = policy.check_security(backend, handle)
if block_status then
    storage_circuit.record_success()
    backend.close(handle)
    return deny(block_status, block_msg)
end

local rate_limit = identity.limit
local rate_window = identity.window

if identity.use_apikey_store then
    local api_key = identity.api_key
    local key_exist, err_exists = config_cache.apikey_exists(api_key, backend, handle)
    if err_exists then
        backend.close(handle)
        ngx.log(ngx.ERR, "storage exists err: ", err_exists)
        return storage_fail()
    end
    if key_exist ~= 1 then
        storage_circuit.record_success()
        backend.close(handle)
        return deny(401, "invalid api key")
    end

    local bh_ok, bh_msg = business_hmac.verify(api_key, backend, handle)
    if not bh_ok then
        storage_circuit.record_success()
        backend.close(handle)
        metrics.incr("business_hmac_failures_total")
        return deny(401, bh_msg or "business hmac failed")
    end

    local meta, err_meta = config_cache.apikey_meta(api_key, backend, handle)
    if err_meta then
        backend.close(handle)
        ngx.log(ngx.ERR, "storage hmget err: ", err_meta)
        return storage_fail()
    end
    local meta_tbl = config_cache.meta_table_from_hmget(meta)
    rate_limit = tonumber(meta_tbl.limit) or DEFAULT_RATE_LIMIT
    rate_window = tonumber(meta_tbl.window) or DEFAULT_RATE_WINDOW
    rate_limit = rate_warmup.effective_limit(rate_limit, meta_tbl)
    ngx.header["X-RateLimit-Warmup-Limit"] = rate_limit
end

identity.rate_key = policy.build_rate_key(identity.rate_key, identity.api_key, ip)

local identity_key = identity.api_key or ngx.ctx.auth_subject or "anon"
local rq, rq_err = policy.route_quota(backend, handle, ngx.var.uri or "/", tostring(identity_key))
if rq_err then
    backend.close(handle)
    ngx.log(ngx.ERR, "route quota err: ", rq_err)
    return storage_fail()
elseif rq then
    rate_limit = rq.limit
    rate_window = rq.window
    identity.rate_key = rq.rate_key
end

local in_whitelist, err_wl = config_cache.whitelist_member(ip, backend, handle)
if err_wl then
    backend.close(handle)
    ngx.log(ngx.ERR, "storage sismember err: ", err_wl)
    return storage_fail()
end

if in_whitelist == 1 then
    storage_circuit.record_success()
    backend.close(handle)
    ngx.header["X-RateLimit-Whitelist"] = "true"
    ngx.header["X-RateLimit-Limit"] = rate_limit
    ngx.header["X-RateLimit-Remaining"] = -1
    ngx.header["X-RateLimit-Reset"] = math.ceil(ngx.now() + rate_window)
    return
end

local function sliding_check(handle, limit_key, rate_limit, rate_window)
    local now = ngx.now()
    local unique_id = now .. ":" .. ngx.var.pid .. ":" .. math.random()
    local cnt, err_rl = backend.sliding_window(handle, limit_key, rate_window, now, unique_id)
    if err_rl then
        return nil, err_rl
    end
    local reset_ts = math.ceil(now + rate_window)
    if cnt >= rate_limit then
        return false, reset_ts, cnt
    end
    return true, reset_ts, cnt
end

local gcap, _ = policy.global_cap()
if gcap then
    local ok, reset_ts = sliding_check(backend, gcap.rate_key, gcap.limit, gcap.window)
    if ok == nil then
        backend.close(handle)
        ngx.log(ngx.ERR, "global rate limit err")
        return storage_fail()
    end
    if not ok then
        storage_circuit.record_success()
        backend.close(handle)
        metrics.incr("global_rate_limit_hits_total")
        ngx.header["Retry-After"] = reset_ts - math.ceil(ngx.now())
        return deny(429, "too many requests, global rate limited")
    end
end

if not leaky_bucket.allow(identity.rate_key) then
    storage_circuit.record_success()
    backend.close(handle)
    ngx.header["Retry-After"] = "1"
    return deny(429, "leaky bucket full")
end

local now = ngx.now()
local limit_key = identity.rate_key
local unique_id = now .. ":" .. ngx.var.pid .. ":" .. math.random()

local cnt, err_rl = backend.sliding_window(handle, limit_key, rate_window, now, unique_id)
if err_rl then
    backend.close(handle)
    ngx.log(ngx.ERR, "storage rate limit err: ", err_rl)
    return storage_fail()
end

local remaining = rate_limit - cnt
local reset_ts = math.ceil(now + rate_window)

ngx.header["X-RateLimit-Limit"] = rate_limit
ngx.header["X-RateLimit-Remaining"] = math.max(0, remaining)
ngx.header["X-RateLimit-Reset"] = reset_ts

if cnt >= rate_limit then
    storage_circuit.record_success()
    backend.close(handle)
    ngx.header["Retry-After"] = reset_ts - math.ceil(ngx.now())
    return deny(429, "too many requests, rate limited")
end

storage_circuit.record_success()
backend.close(handle)
return
