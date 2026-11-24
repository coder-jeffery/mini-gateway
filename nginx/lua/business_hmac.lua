-- P4-2: optional business request HMAC (distinct from admin v1).
local config = require "gateway_config"
local hmac = require "resty.hmac"
local ngx = ngx

local _M = {}
local SIGN_WINDOW = 60

local function required_for_key(backend, handle, api_key)
    local mode = config.business_hmac_mode()
    if mode == "required" then
        return true
    end
    local flag, err = backend.hmget(handle, "apikey:meta:" .. api_key, "hmac_required")
    if err then
        return nil, err
    end
    if flag and flag[1] == "1" then
        return true
    end
    if mode == "required" then
        return true
    end
    if mode == "off" then
        return false
    end
    -- optional: enforce when client sends signature headers
    local ts = ngx.var.http_x_business_ts
    local sign = ngx.var.http_x_business_sign
    return (ts ~= nil and ts ~= "") or (sign ~= nil and sign ~= "")
end

function _M.verify(api_key, backend, handle)
    local need = required_for_key(backend, handle, api_key)
    if need == nil then
        return false, "storage error"
    end
    if not need then
        return true, nil
    end

    local ts = tonumber(ngx.var.http_x_business_ts)
    local sign = ngx.var.http_x_business_sign
    if not ts or not sign or sign == "" then
        return false, "missing business hmac headers"
    end
    if math.abs(ngx.now() - ts) > SIGN_WINDOW then
        return false, "business signature expired"
    end

    local secret = config.business_hmac_secret()
    if not secret or secret == "" then
        return false, "business hmac not configured"
    end

    local raw = table.concat({
        tostring(ts),
        ngx.req.get_method(),
        ngx.var.uri or "/",
        api_key,
    }, ":")
    local h = hmac:new(secret, hmac.ALGOS.SHA256)
    if not h or not h:update(raw) then
        return false, "hmac init failed"
    end
    local calc = h:final(nil, true)
    if not calc or calc ~= sign then
        return false, "invalid business signature"
    end
    return true, nil
end

return _M