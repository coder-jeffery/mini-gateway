-- P3-2: request header / URI rewrite rules from store.
local store_mod = require "store"
local cjson = require "cjson"
local ngx = ngx

local _M = {}

local function rule_matches(rule, uri, api_key)
    local prefix = rule.match_prefix or ""
    if prefix == "" then
        return false
    end
    if uri:sub(1, #prefix) ~= prefix then
        return false
    end
    if rule.match_api_key and rule.match_api_key ~= "" and api_key ~= rule.match_api_key then
        return false
    end
    return true
end

function _M.apply()
    local backend = store_mod.backend()
    local handle, err = backend.new()
    if not handle then
        return
    end
    local names, list_err = backend.smembers(handle, "policy:rewrite:index")
    if list_err or not names then
        backend.close(handle)
        return
    end
    table.sort(names)
    local uri = ngx.var.uri or "/"
    local api_key = ngx.var.http_x_api_key or ""

    for _, name in ipairs(names) do
        local raw = backend.get(handle, "policy:rewrite:" .. name)
        if raw and raw ~= ngx.null then
            local ok, rule = pcall(cjson.decode, raw)
            if ok and type(rule) == "table" and rule_matches(rule, uri, api_key) then
                ngx.header["X-Gateway-Rewrite-Applied"] = name
                if rule.uri_prefix and rule.uri_prefix ~= "" then
                    local prefix = rule.match_prefix
                    local tail = uri:sub(#prefix + 1)
                    if tail == "" then
                        tail = ""
                    end
                    ngx.req.set_uri(rule.uri_prefix .. tail)
                    ngx.header["X-Gateway-Rewrite-Uri"] = "1"
                end
                if type(rule.headers) == "table" then
                    for hk, hv in pairs(rule.headers) do
                        if type(hk) == "string" and type(hv) == "string" then
                            ngx.req.set_header(hk, hv)
                        end
                    end
                end
                break
            end
        end
    end
    backend.close(handle)
end

return _M