local cjson = require "cjson"
local config = require "gateway_config"

local _M = {}

local function trim(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function csv_set(value, normalize)
    local out = {}
    for item in string.gmatch(value or "", "[^,]+") do
        item = trim(item)
        if item ~= "" then
            out[normalize and normalize(item) or item] = true
        end
    end
    return out
end

local function append_vary(value)
    local current = ngx.header["Vary"]
    if not current or current == "" then
        ngx.header["Vary"] = value
        return
    end
    if type(current) == "table" then
        for _, item in ipairs(current) do
            if item == value then
                return
            end
        end
        current[#current + 1] = value
        ngx.header["Vary"] = current
        return
    end
    for item in string.gmatch(current, "[^,]+") do
        if trim(item):lower() == value:lower() then
            return
        end
    end
    ngx.header["Vary"] = current .. ", " .. value
end

local function allowed_origin(origin)
    if not config.cors_enabled() or not origin or origin == "" then
        return nil
    end
    local origins = csv_set(config.cors_allow_origins())
    if origins[origin] then
        return origin
    end
    if origins["*"] and not config.cors_allow_credentials() then
        return "*"
    end
    return nil
end

local function apply_origin(origin)
    local value = allowed_origin(origin)
    if not value then
        return false
    end
    ngx.header["Access-Control-Allow-Origin"] = value
    if value ~= "*" then
        append_vary("Origin")
    end
    if config.cors_allow_credentials() then
        ngx.header["Access-Control-Allow-Credentials"] = "true"
    end
    return true
end

local function deny_preflight(message)
    ngx.status = 403
    ngx.header["Content-Type"] = "application/json"
    ngx.header["Cache-Control"] = "no-store"
    ngx.say(cjson.encode({ ok = false, msg = message }))
    return ngx.exit(403)
end

function _M.is_preflight()
    return config.cors_enabled()
        and ngx.req.get_method() == "OPTIONS"
        and ngx.var.http_origin
        and ngx.var.http_access_control_request_method
end

function _M.handle_preflight()
    local origin = ngx.var.http_origin
    if not apply_origin(origin) then
        return deny_preflight("CORS origin not allowed")
    end

    local requested_method = ngx.var.http_access_control_request_method:upper()
    local methods = csv_set(config.cors_allow_methods(), string.upper)
    if not methods[requested_method] then
        ngx.header["Access-Control-Allow-Origin"] = nil
        ngx.header["Access-Control-Allow-Credentials"] = nil
        return deny_preflight("CORS method not allowed")
    end

    local requested_headers = ngx.var.http_access_control_request_headers
    if requested_headers and requested_headers ~= "" then
        local allowed_headers = csv_set(config.cors_allow_headers(), string.lower)
        for header in string.gmatch(requested_headers, "[^,]+") do
            if not allowed_headers[trim(header):lower()] then
                ngx.header["Access-Control-Allow-Origin"] = nil
                ngx.header["Access-Control-Allow-Credentials"] = nil
                return deny_preflight("CORS header not allowed")
            end
        end
    end

    ngx.header["Access-Control-Allow-Methods"] = config.cors_allow_methods()
    ngx.header["Access-Control-Allow-Headers"] = config.cors_allow_headers()
    ngx.header["Access-Control-Max-Age"] = tostring(config.cors_max_age())
    append_vary("Access-Control-Request-Method")
    append_vary("Access-Control-Request-Headers")
    return ngx.exit(204)
end

function _M.apply_response_headers()
    local origin = ngx.var.http_origin
    if not apply_origin(origin) then
        return
    end
    local expose_headers = config.cors_expose_headers()
    if expose_headers ~= "" then
        ngx.header["Access-Control-Expose-Headers"] = expose_headers
    end
end

return _M
