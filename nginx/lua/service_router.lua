local cjson = require "cjson"
local store_mod = require "store"
local service_admin = require "service_admin"

local _M = {}

local CACHE_KEY = "snapshot"
local CACHE_TTL = 5
local INDEX_KEY = "service:index"
local KEY_PREFIX = "service:"

local function cache_dict()
    return ngx.shared.service_cache
end

local function decode_cached(raw)
    local ok, data = pcall(cjson.decode, raw)
    if not ok or type(data) ~= "table" or type(data.services) ~= "table" then
        return nil
    end
    if data.expires and data.expires > ngx.now() then
        return data.services
    end
    return nil
end

local function load_from_store()
    local backend = store_mod.backend()
    local handle, err = backend.new()
    if not handle then
        return nil, err
    end

    local ids, err_ids = backend.smembers(handle, INDEX_KEY)
    if err_ids then
        backend.close(handle)
        return nil, err_ids
    end

    local services = {}
    if ids then
        for _, id in ipairs(ids) do
            local raw, err_get = backend.get(handle, KEY_PREFIX .. id)
            if err_get then
                ngx.log(ngx.ERR, "service load err: ", err_get)
            elseif raw and raw ~= ngx.null and raw ~= "" then
                local ok, decoded = pcall(cjson.decode, raw)
                if ok and type(decoded) == "table" and decoded.path_prefix then
                    services[#services + 1] = service_admin.public_router_record(decoded)
                else
                    ngx.log(ngx.ERR, "skip corrupt service record id=", id)
                end
            end
        end
    end

    backend.close(handle)

    table.sort(services, function(a, b)
        if #a.path_prefix == #b.path_prefix then
            return a.path_prefix > b.path_prefix
        end
        return #a.path_prefix > #b.path_prefix
    end)

    local cache = cache_dict()
    if cache then
        cache:set(
            CACHE_KEY,
            cjson.encode({ expires = ngx.now() + CACHE_TTL, services = services }),
            CACHE_TTL
        )
    end

    return services, nil
end

local function load_services()
    local cache = cache_dict()
    if cache then
        local raw = cache:get(CACHE_KEY)
        if raw then
            local fresh = decode_cached(raw)
            if fresh then
                return fresh, nil
            end
        end
    end

    local services, err = load_from_store()
    if services then
        return services, nil
    end

    if cache then
        local raw = cache:get(CACHE_KEY)
        if raw then
            local ok, data = pcall(cjson.decode, raw)
            if ok and type(data) == "table" and type(data.services) == "table" then
                ngx.log(ngx.WARN, "service store unavailable, using stale cache: ", err)
                return data.services, nil
            end
        end
    end

    return nil, err or "storage unavailable"
end

local function prefix_matches(uri, prefix)
    if prefix == "/" then
        return true
    end
    if uri == prefix then
        return true
    end
    if #uri > #prefix and uri:sub(1, #prefix) == prefix and uri:sub(#prefix + 1, #prefix + 1) == "/" then
        return true
    end
    return false
end

local function upstream_host(upstream_url)
    return upstream_url:match("^https?://([^/:]+)")
end

function _M.resolve(uri, request_uri)
    local services, err = load_services()
    if not services then
        return nil, nil, nil, err
    end
    if #services == 0 then
        return nil, nil, nil, nil
    end

    for _, svc in ipairs(services) do
        if prefix_matches(uri, svc.path_prefix) then
            local base = svc.upstream_url:gsub("/+$", "")
            local target = base .. (request_uri or uri)
            local host = upstream_host(svc.upstream_url)
            return svc, target, host, nil
        end
    end

    return nil, nil, nil, nil
end

return _M
