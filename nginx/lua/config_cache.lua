-- Local shared_dict cache for hot apikey / whitelist reads (all storage backends when enabled).
local config = require "gateway_config"
local metrics = require "gateway_metrics"
local cjson = require "cjson"
local ngx = ngx

local _M = {}

local dict_name = "gateway_config_cache"

local function dict()
    return ngx.shared[dict_name]
end

function _M.enabled()
    return config.config_cache_enabled()
end

local function bump_epoch(d)
    d:set("cache:epoch", ngx.now(), 0)
end

local function cache_get(key)
    local d = dict()
    if not d then
        return nil
    end
    local raw = d:get(key)
    if not raw then
        metrics.incr("config_cache_misses_total")
        return nil
    end
    metrics.incr("config_cache_hits_total")
    return raw
end

local function cache_set(key, value, ttl)
    local d = dict()
    if not d then
        return
    end
    d:set(key, value, ttl)
end

function _M.invalidate_for_action(action, req)
    if not _M.enabled() then
        return
    end
    local d = dict()
    if not d then
        return
    end
    req = req or {}
    if action == "upsert_apikey" or action == "del_apikey" then
        local key = req.api_key
        if key then
            d:delete("cache:apikey:exists:" .. key)
            d:delete("cache:apikey:meta:" .. key)
        end
    elseif action == "whitelist_add" or action == "whitelist_del" then
        local ip = req.ip
        if ip then
            d:delete("cache:wl:ip:" .. ip)
        end
    end
    bump_epoch(d)
end

function _M.apikey_exists(api_key, backend, handle)
    if not _M.enabled() then
        local exist, err = backend.exists(handle, "apikey:" .. api_key)
        return exist, err
    end
    local ck = "cache:apikey:exists:" .. api_key
    local cached = cache_get(ck)
    if cached then
        return tonumber(cached), nil
    end
    local exist, err = backend.exists(handle, "apikey:" .. api_key)
    if err then
        return nil, err
    end
    cache_set(ck, tostring(exist), config.config_cache_ttl_sec())
    return exist, nil
end

function _M.apikey_meta(api_key, backend, handle)
    if not _M.enabled() then
        return backend.hmget(handle, "apikey:meta:" .. api_key, "limit", "window")
    end
    local ck = "cache:apikey:meta:" .. api_key
    local cached = cache_get(ck)
    if cached then
        local ok, t = pcall(cjson.decode, cached)
        if ok and type(t) == "table" then
            return { t.limit, t.window }, nil
        end
    end
    local meta, err = backend.hmget(handle, "apikey:meta:" .. api_key, "limit", "window")
    if err then
        return nil, err
    end
    cache_set(ck, cjson.encode({ limit = meta[1], window = meta[2] }), config.config_cache_ttl_sec())
    return meta, nil
end

function _M.whitelist_member(ip, backend, handle)
    if not _M.enabled() then
        return backend.sismember(handle, "whitelist:ip", ip)
    end
    local ck = "cache:wl:ip:" .. ip
    local cached = cache_get(ck)
    if cached then
        return tonumber(cached), nil
    end
    local member, err = backend.sismember(handle, "whitelist:ip", ip)
    if err then
        return nil, err
    end
    cache_set(ck, tostring(member), config.config_cache_ttl_sec())
    return member, nil
end

return _M