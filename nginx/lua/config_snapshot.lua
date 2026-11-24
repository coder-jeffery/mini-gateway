-- P3-4: configuration snapshot save/restore (apikeys + whitelists).
local cjson = require "cjson"
local apikey_admin = require "apikey_admin"
local ngx = ngx

local _M = {}

local SNAPSHOT_KEY = "config:snapshot:latest"

function _M.save(backend, handle)
    local keys, err = apikey_admin.list_backend(backend, handle, 1, 10000)
    if not keys then
        return nil, err
    end
    local biz, err_b = backend.smembers(handle, "whitelist:ip")
    if err_b then
        return nil, err_b
    end
    local admin, err_a = backend.smembers(handle, "admin:whitelist:ip")
    if err_a then
        return nil, err_a
    end
    local payload = {
        ts = ngx.now(),
        apikeys = keys.items or {},
        whitelist = biz or {},
        admin_whitelist = admin or {},
    }
    local raw = cjson.encode(payload)
    local ok, set_err = backend.set(handle, SNAPSHOT_KEY, raw)
    if not ok then
        return nil, set_err
    end
    return { snapshot_key = SNAPSHOT_KEY, ts = payload.ts, apikey_count = #(payload.apikeys) }, nil
end

function _M.restore(backend, handle)
    local raw, err = backend.get(handle, SNAPSHOT_KEY)
    if err or not raw or raw == ngx.null then
        return nil, "no snapshot"
    end
    local ok, payload = pcall(cjson.decode, raw)
    if not ok or type(payload) ~= "table" then
        return nil, "snapshot corrupt"
    end
    for _, item in ipairs(payload.apikeys or {}) do
        if item.api_key then
            backend.set(handle, "apikey:" .. item.api_key, "1")
            backend.hset(handle, "apikey:meta:" .. item.api_key, "limit", item.limit or 100, "window", item.window or 60)
            apikey_admin.index_add_backend(backend, handle, item.api_key)
        end
    end
    for _, ip in ipairs(payload.whitelist or {}) do
        backend.sadd(handle, "whitelist:ip", ip)
    end
    for _, ip in ipairs(payload.admin_whitelist or {}) do
        backend.sadd(handle, "admin:whitelist:ip", ip)
    end
    return { restored = true, ts = payload.ts }, nil
end

return _M