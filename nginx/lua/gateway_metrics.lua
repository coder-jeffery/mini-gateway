-- Prometheus-oriented counters in lua_shared_dict (worker-safe incr).
local ngx = ngx

local _M = {}

local dict_name = "gateway_metrics"

local function dict()
    return ngx.shared[dict_name]
end

function _M.incr(key, delta)
    local d = dict()
    if not d then
        return false
    end
    delta = delta or 1
    local newval, err = d:incr(key, delta, 0)
    if not newval and err == "not found" then
        d:set(key, delta)
        return true
    end
    return newval ~= nil
end

function _M.set_gauge(key, value)
    local d = dict()
    if not d then
        return false
    end
    d:set(key, value)
    return true
end

function _M.get(key)
    local d = dict()
    if not d then
        return 0
    end
    return d:get(key) or 0
end

function _M.incr_http_status(status)
    local code = tonumber(status) or 0
    if code >= 200 and code < 300 then
        _M.incr("http_status_2xx_total")
    elseif code == 401 then
        _M.incr("http_status_401_total")
    elseif code == 429 then
        _M.incr("http_status_429_total")
        _M.incr("rate_limit_hits_total")
    elseif code == 503 then
        _M.incr("http_status_503_total")
    elseif code >= 500 then
        _M.incr("http_status_5xx_total")
    end
    _M.incr("http_requests_total")
end

function _M.prometheus_lines()
    local defs = {
        { prom = "gateway_http_requests_total", store = "http_requests_total", typ = "counter",
          help = "Total HTTP requests through the data plane." },
        { prom = "gateway_http_status_2xx_total", store = "http_status_2xx_total", typ = "counter",
          help = "HTTP 2xx responses." },
        { prom = "gateway_http_status_401_total", store = "http_status_401_total", typ = "counter",
          help = "HTTP 401 responses." },
        { prom = "gateway_http_status_429_total", store = "http_status_429_total", typ = "counter",
          help = "HTTP 429 responses." },
        { prom = "gateway_http_status_503_total", store = "http_status_503_total", typ = "counter",
          help = "HTTP 503 responses." },
        { prom = "gateway_http_status_5xx_total", store = "http_status_5xx_total", typ = "counter",
          help = "HTTP 5xx responses (excluding counted 503)." },
        { prom = "gateway_rate_limit_hits_total", store = "rate_limit_hits_total", typ = "counter",
          help = "Rate limit denials (429)." },
        { prom = "gateway_storage_errors_total", store = "storage_errors_total", typ = "counter",
          help = "Storage operation failures on the data plane." },
        { prom = "gateway_storage_cb_trips_total", store = "circuit_breaker_trips_total", typ = "counter",
          help = "Times the storage circuit breaker opened." },
        { prom = "gateway_storage_cb_degraded_total", store = "circuit_breaker_degraded_total", typ = "counter",
          help = "Requests served under storage circuit open (degraded mode)." },
        { prom = "gateway_whitelist_bypass_total", store = "whitelist_bypass_total", typ = "counter",
          help = "Requests from business IP whitelist (rate limit skipped)." },
        { prom = "gateway_circuit_breaker_open", store = "circuit_breaker_open_gauge", typ = "gauge",
          help = "1 if storage circuit is open, else 0." },
        { prom = "gateway_storage_cb_state", store = "circuit_breaker_state_gauge", typ = "gauge",
          help = "Circuit state: 0=closed, 1=open, 2=half_open." },
        { prom = "gateway_storage_cb_window_failures", store = "cb_window_failures", typ = "gauge",
          help = "Storage failures in current breaker window." },
        { prom = "gateway_storage_cb_window_successes", store = "cb_window_successes", typ = "gauge",
          help = "Storage successes in current breaker window." },
    }
    local lines = {}
    for _, def in ipairs(defs) do
        if def.help then
            lines[#lines + 1] = string.format("# HELP %s %s", def.prom, def.help)
        end
        lines[#lines + 1] = string.format("# TYPE %s %s", def.prom, def.typ)
        lines[#lines + 1] = string.format("%s %d", def.prom, _M.get(def.store))
    end
    return table.concat(lines, "\n") .. "\n"
end

return _M