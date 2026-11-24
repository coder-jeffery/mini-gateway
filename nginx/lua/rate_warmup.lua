-- P4-3: ramp API key quota from warmup_start_limit to configured limit.
local config = require "gateway_config"
local ngx = ngx

local _M = {}

function _M.effective_limit(nominal, meta_fields)
    nominal = tonumber(nominal) or 0
    if not config.rate_warmup_enabled() then
        return nominal
    end
    if type(meta_fields) ~= "table" then
        return nominal
    end
    local start_limit = tonumber(meta_fields.warmup_start_limit)
    local ramp_sec = tonumber(meta_fields.warmup_ramp_sec)
    local created = tonumber(meta_fields.created_at)
    if not start_limit or not ramp_sec or ramp_sec <= 0 or not created then
        return nominal
    end
    if start_limit >= nominal then
        return nominal
    end
    local elapsed = math.max(0, ngx.now() - created)
    local progress = math.min(1, elapsed / ramp_sec)
    local eff = math.floor(start_limit + (nominal - start_limit) * progress)
    if eff < 1 then
        eff = 1
    end
    if eff > nominal then
        eff = nominal
    end
    return eff
end

return _M