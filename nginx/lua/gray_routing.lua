-- P3-1: percent-based gray tagging (data plane header only).
local store_mod = require "store"
local cjson = require "cjson"
local ngx = ngx

local _M = {}

local function hash_percent(seed)
    local h = 0
    for i = 1, #seed do
        h = (h * 31 + string.byte(seed, i)) % 100
    end
    return h
end

function _M.apply()
    local api_key = ngx.var.http_x_api_key or ""
    local ip = ngx.var.remote_addr or ""
    local backend = store_mod.backend()
    local handle, err = backend.new()
    if not handle then
        return
    end
    local rules, list_err = backend.smembers(handle, "policy:gray_rule:index")
    if list_err or not rules then
        backend.close(handle)
        return
    end
    for _, name in ipairs(rules) do
        local raw, get_err = backend.get(handle, "policy:gray_rule:" .. name)
        if not get_err and raw and raw ~= ngx.null then
            local ok, rule = pcall(cjson.decode, raw)
            if ok and type(rule) == "table" then
                local percent = tonumber(rule.percent) or 0
                local tag = rule.tag or "gray"
                local match = false
                if rule.match_api_key and rule.match_api_key ~= "" and api_key == rule.match_api_key then
                    match = true
                elseif rule.match_ip and rule.match_ip ~= "" and ip == rule.match_ip then
                    match = true
                elseif (not rule.match_api_key or rule.match_api_key == "")
                    and (not rule.match_ip or rule.match_ip == "") then
                    match = true
                end
                if match and hash_percent(api_key .. ":" .. ip) < percent then
                    ngx.header["X-Gray-Tag"] = tag
                    break
                end
            end
        end
    end
    backend.close(handle)
end

return _M