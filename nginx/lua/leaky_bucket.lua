-- P4-1: simple leaky bucket gate (shared dict water level).
local config = require "gateway_config"
local metrics = require "gateway_metrics"
local ngx = ngx

local _M = {}
local dict_name = "gateway_leaky"

local function dict()
    return ngx.shared[dict_name]
end

function _M.allow(bucket_key)
    local rate = config.leaky_bucket_rate()
    local capacity = config.leaky_bucket_capacity()
    if rate <= 0 or capacity <= 0 then
        return true
    end
    local d = dict()
    if not d then
        return true
    end
    local now = ngx.now()
    local state_key = "lb:" .. bucket_key
    local raw = d:get(state_key)
    local water, last = 0, now
    if raw then
        local w, t = raw:match("^(%d+%.?%d*):(%d+%.?%d*)$")
        water = tonumber(w) or 0
        last = tonumber(t) or now
    end
    local leaked = (now - last) * rate
    water = math.max(0, water - leaked)
    water = water + 1
    if water > capacity then
        metrics.incr("leaky_bucket_rejects_total")
        return false
    end
    d:set(state_key, string.format("%.4f:%.4f", water, now), config.leaky_bucket_ttl_sec())
    return true
end

return _M