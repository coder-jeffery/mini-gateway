local cjson = require "cjson"
local config = require "gateway_config"

local dict_name = "gateway_store"
local log_dict_name = "gateway_logs"

local _M = {}

local function dict()
    return ngx.shared[dict_name]
end

local function log_dict()
    return ngx.shared[log_dict_name]
end

function _M.new()
    local d = dict()
    if not d then
        return nil, "shared dict gateway_store missing"
    end
    return { _kind = "memory" }, nil
end

function _M.close(_store)
    return true
end

function _M.backend_name()
    return "memory"
end

local function k(key)
    return "k:" .. key
end

local function hkey(hash_key)
    return "h:" .. hash_key
end

local function skey(set_name, member)
    return "s:" .. set_name .. ":" .. member
end

function _M.exists(_store, key)
    local d = dict()
    return d:get(k(key)) and 1 or 0, nil
end

function _M.get(_store, key)
    local d = dict()
    return d:get(k(key)), nil
end

function _M.set(_store, key, value)
    local d = dict()
    d:set(k(key), value)
    return true, nil
end

function _M.del(_store, key)
    local d = dict()
    d:delete(k(key))
    d:delete(hkey(key))
    return true, nil
end

function _M.hmget(_store, hash_key, f1, f2)
    local d = dict()
    local raw = d:get(hkey(hash_key))
    if not raw then
        return { ngx.null, ngx.null }, nil
    end
    local ok, t = pcall(cjson.decode, raw)
    if not ok or type(t) ~= "table" then
        return { ngx.null, ngx.null }, nil
    end
    local v1 = t[f1]
    local v2 = t[f2]
    return {
        v1 == nil and ngx.null or tostring(v1),
        v2 == nil and ngx.null or tostring(v2),
    }, nil
end

function _M.hset(_store, hash_key, f1, v1, f2, v2)
    local d = dict()
    local raw = d:get(hkey(hash_key))
    local t = {}
    if raw then
        local ok, decoded = pcall(cjson.decode, raw)
        if ok and type(decoded) == "table" then
            t = decoded
        end
    end
    t[f1] = v1
    if f2 and v2 then
        t[f2] = v2
    end
    d:set(hkey(hash_key), cjson.encode(t))
    return true, nil
end

function _M.sismember(_store, set_name, member)
    local d = dict()
    return d:get(skey(set_name, member)) and 1 or 0, nil
end

function _M.sadd(_store, set_name, member)
    local d = dict()
    d:set(skey(set_name, member), "1")
    return true, nil
end

function _M.srem(_store, set_name, member)
    local d = dict()
    d:delete(skey(set_name, member))
    return true, nil
end

function _M.smembers(_store, set_name)
    local d = dict()
    local prefix = "s:" .. set_name .. ":"
    local keys = d:get_keys(0)
    local out = {}
    for _, full in ipairs(keys) do
        if full:sub(1, #prefix) == prefix then
            out[#out + 1] = full:sub(#prefix + 1)
        end
    end
    return out, nil
end

function _M.sliding_window(_store, limit_key, window_sec, now, unique_id)
    local d = dict()
    local zkey = "z:" .. limit_key
    local raw = d:get(zkey)
    local events = {}
    if raw then
        local ok, decoded = pcall(cjson.decode, raw)
        if ok and type(decoded) == "table" then
            events = decoded
        end
    end
    local window_start = now - window_sec
    local trimmed = {}
    for _, ev in ipairs(events) do
        if ev.t and ev.t > window_start then
            trimmed[#trimmed + 1] = ev
        end
    end
    local cnt = #trimmed
    trimmed[#trimmed + 1] = { t = now, id = unique_id }
    d:set(zkey, cjson.encode(trimmed), window_sec + 10)
    return cnt, nil
end

function _M.access_log_append(_store, line)
    local ld = log_dict()
    if not ld then
        return false, "shared dict gateway_logs missing"
    end
    local idx = (ld:get("_idx") or 0) + 1
    ld:set("_idx", idx)
    ld:set("log:" .. idx, line, 86400)
    return true, nil
end

function _M.bootstrap(_store, opts)
    for ip in string.gmatch(opts.admin_whitelist_ips, "[^,%s]+") do
        _M.sadd(_store, "admin:whitelist:ip", ip)
    end
    _M.set(_store, "apikey:" .. opts.api_key, "1")
    _M.hset(_store, "apikey:meta:" .. opts.api_key, "limit", opts.api_key_limit, "window", opts.api_key_window)
    local token_info = cjson.encode({ creator = "bootstrap", expire_at = 0 })
    _M.set(_store, "admin:token:" .. opts.admin_token, token_info)
    return true, nil
end

return _M
