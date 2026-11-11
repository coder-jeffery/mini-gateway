local cjson = require "cjson"
local config = require "gateway_config"

local _M = {}

local function current_policy()
    local service = ngx.ctx.gateway_service
    if service then
        return {
            cors_enabled = service.cors_enabled == true,
            cors_allow_origins = service.cors_allow_origins or "",
            cors_allow_methods = service.cors_allow_methods or "",
            cors_allow_headers = service.cors_allow_headers or "",
            cors_expose_headers = service.cors_expose_headers or "",
            cors_max_age = tonumber(service.cors_max_age) or 0,
            cors_allow_credentials = service.cors_allow_credentials == true,
        }
    end
    return {
        cors_enabled = config.cors_enabled(),
        cors_allow_origins = config.cors_allow_origins(),
        cors_allow_methods = config.cors_allow_methods(),
        cors_allow_headers = config.cors_allow_headers(),
        cors_expose_headers = config.cors_expose_headers(),
        cors_max_age = config.cors_max_age(),
        cors_allow_credentials = config.cors_allow_credentials(),
    }
end

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
    local policy = current_policy()
    if not policy.cors_enabled or not origin or origin == "" then
        return nil
    end
    local origins = csv_set(policy.cors_allow_origins)
    if origins[origin] then
        return origin
    end
    if origins["*"] and not policy.cors_allow_credentials then
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
    local policy = current_policy()
    if policy.cors_allow_credentials then
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
    local policy = current_policy()
    return policy.cors_enabled
        and ngx.req.get_method() == "OPTIONS"
        and ngx.var.http_origin
        and ngx.var.http_access_control_request_method
end

function _M.handle_preflight()
    local origin = ngx.var.http_origin
    if not apply_origin(origin) then
        return deny_preflight("CORS origin not allowed")
    end

    local policy = current_policy()
    local requested_method = ngx.var.http_access_control_request_method:upper()
    local methods = csv_set(policy.cors_allow_methods, string.upper)
    if not methods[requested_method] then
        ngx.header["Access-Control-Allow-Origin"] = nil
        ngx.header["Access-Control-Allow-Credentials"] = nil
        return deny_preflight("CORS method not allowed")
    end

    local requested_headers = ngx.var.http_access_control_request_headers
    if requested_headers and requested_headers ~= "" then
        local allowed_headers = csv_set(policy.cors_allow_headers, string.lower)
        for header in string.gmatch(requested_headers, "[^,]+") do
            if not allowed_headers[trim(header):lower()] then
                ngx.header["Access-Control-Allow-Origin"] = nil
                ngx.header["Access-Control-Allow-Credentials"] = nil
                return deny_preflight("CORS header not allowed")
            end
        end
    end

    ngx.header["Access-Control-Allow-Methods"] = policy.cors_allow_methods
    ngx.header["Access-Control-Allow-Headers"] = policy.cors_allow_headers
    ngx.header["Access-Control-Max-Age"] = tostring(policy.cors_max_age)
    append_vary("Access-Control-Request-Method")
    append_vary("Access-Control-Request-Headers")
    return ngx.exit(204)
end

function _M.apply_response_headers()
    local origin = ngx.var.http_origin
    if not apply_origin(origin) then
        return
    end
    local policy = current_policy()
    local expose_headers = policy.cors_expose_headers
    if expose_headers ~= "" then
        ngx.header["Access-Control-Expose-Headers"] = expose_headers
    end
end

return _M
