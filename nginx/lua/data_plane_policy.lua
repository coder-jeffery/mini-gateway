-- P2 data-plane policy: blocklists, route quota, rate-limit key dimension, global cap.
local config = require "gateway_config"
local metrics = require "gateway_metrics"
local cjson = require "cjson"
local ngx = ngx

local _M = {}

local function uri_blocked(backend, handle, uri)
    local rules, err = backend.smembers(handle, "policy:uri_block")
    if err or not rules then
        return false, err
    end
    for _, prefix in ipairs(rules) do
        if uri == prefix or uri:sub(1, #prefix) == prefix then
            return true, nil
        end
    end
    return false, nil
end

local function ua_blocked(backend, handle, ua)
    if not ua or ua == "" then
        return false, nil
    end
    local rules, err = backend.smembers(handle, "policy:ua_block")
    if err or not rules then
        return false, err
    end
    for _, needle in ipairs(rules) do
        if ua:find(needle, 1, true) then
            return true, nil
        end
    end
    return false, nil
end

function _M.check_security(backend, handle)
    local uri = ngx.var.uri or "/"
    local ua = ngx.var.http_user_agent or ""
    local blocked, err = uri_blocked(backend, handle, uri)
    if err then
        return nil, err
    end
    if blocked then
        metrics.incr("policy_uri_block_total")
        return 403, "forbidden: uri blocked"
    end
    blocked, err = ua_blocked(backend, handle, ua)
    if err then
        return nil, err
    end
    if blocked then
        metrics.incr("policy_ua_block_total")
        return 403, "forbidden: user-agent blocked"
    end
    return nil, nil
end

function _M.build_rate_key(base_key, api_key, ip)
    local dim = config.rate_limit_dimension()
    if dim == "ip" then
        return "ratelimit:sw:ip:" .. ip
    end
    if dim == "api_key_ip" and api_key then
        return "ratelimit:sw:keyip:" .. api_key .. ":" .. ip
    end
    return base_key
end

local function longest_route_quota(backend, handle, uri)
    local rules, err = backend.smembers(handle, "policy:route_quota:index")
    if err then
        return nil, nil, err, nil
    end
    if not rules or #rules == 0 then
        return nil, nil, nil, nil
    end
    table.sort(rules, function(a, b) return #a > #b end)
    for _, prefix in ipairs(rules) do
        if uri == prefix or uri:sub(1, #prefix) == prefix then
            local raw, get_err = backend.get(handle, "policy:route_quota:" .. prefix)
            if get_err then
                return nil, nil, get_err, nil
            end
            if raw and raw ~= ngx.null then
                local ok, t = pcall(cjson.decode, raw)
                if ok and type(t) == "table" then
                    return tonumber(t.limit), tonumber(t.window), nil, prefix
                end
            end
        end
    end
    return nil, nil, nil, nil
end

function _M.route_quota(backend, handle, uri, identity_key)
    local limit, window, err, prefix = longest_route_quota(backend, handle, uri)
    if err then
        return nil, err
    end
    if not limit or not window or not prefix then
        return nil, nil
    end
    local rate_key = "ratelimit:sw:route:" .. prefix .. ":" .. identity_key
    return {
        rate_key = rate_key,
        limit = limit,
        window = window,
    }, nil
end

function _M.global_cap(backend, handle)
    local limit = config.global_qps_limit()
    local window = config.global_qps_window()
    if limit <= 0 then
        return nil, nil
    end
    return {
        rate_key = "ratelimit:sw:global",
        limit = limit,
        window = window,
    }, nil
end

return _M