-- Storage dependency circuit breaker (error-rate window + half-open probes).
local config = require "gateway_config"
local metrics = require "gateway_metrics"
local ngx = ngx

local _M = {}

local dict_name = "gateway_storage_cb"

local STATE = "cb:state"
local OPEN_UNTIL = "cb:open_until"
local WIN_START = "cb:win_start"
local WIN_OK = "cb:win_ok"
local WIN_FAIL = "cb:win_fail"
local HALF_OK = "cb:half_ok"
local HALF_TRIES = "cb:half_tries"

local function dict()
    return ngx.shared[dict_name]
end

local function state_gauge(name)
    if name == "closed" then
        return 0
    elseif name == "open" then
        return 1
    elseif name == "half_open" then
        return 2
    end
    return -1
end

function _M.sync_metrics()
    local d = dict()
    if not d then
        return
    end
    local st = d:get(STATE) or "closed"
    metrics.set_gauge("circuit_breaker_open_gauge", st == "open" and 1 or 0)
    metrics.set_gauge("circuit_breaker_state_gauge", state_gauge(st))
    metrics.set_gauge("cb_window_failures", d:get(WIN_FAIL) or 0)
    metrics.set_gauge("cb_window_successes", d:get(WIN_OK) or 0)
end

local function rotate_window(now, d)
    local win = config.storage_cb_window_sec()
    local start = d:get(WIN_START) or 0
    if now - start >= win then
        d:set(WIN_START, now)
        d:set(WIN_OK, 0)
        d:set(WIN_FAIL, 0)
    end
end

local function open_circuit(now, d)
    d:set(STATE, "open")
    d:set(OPEN_UNTIL, now + config.storage_cb_open_sec())
    d:set(HALF_OK, 0)
    d:set(HALF_TRIES, 0)
    metrics.incr("circuit_breaker_trips_total")
    _M.sync_metrics()
end

local function close_circuit(d)
    d:set(STATE, "closed")
    d:set(OPEN_UNTIL, 0)
    d:set(HALF_OK, 0)
    d:set(HALF_TRIES, 0)
    d:set(WIN_START, ngx.now())
    d:set(WIN_OK, 0)
    d:set(WIN_FAIL, 0)
    _M.sync_metrics()
end

local function maybe_trip(now, d)
    local ok = d:get(WIN_OK) or 0
    local fail = d:get(WIN_FAIL) or 0
    local total = ok + fail
    local min_req = config.storage_cb_min_requests()
    if total < min_req then
        return
    end
    local rate = fail / total
    if rate >= config.storage_cb_error_rate() then
        open_circuit(now, d)
    end
end

function _M.current_state()
    local d = dict()
    if not d then
        return "closed"
    end
    return d:get(STATE) or "closed"
end

function _M.allow_storage()
    local d = dict()
    if not d then
        return true
    end
    local now = ngx.now()
    local st = d:get(STATE) or "closed"
    if st == "closed" then
        return true
    end
    if st == "open" then
        local until_ts = d:get(OPEN_UNTIL) or 0
        if now >= until_ts then
            d:set(STATE, "half_open")
            d:set(HALF_OK, 0)
            d:set(HALF_TRIES, 0)
            _M.sync_metrics()
            return true
        end
        metrics.incr("circuit_breaker_degraded_total")
        return false
    end
    -- half_open
    local max_p = config.storage_cb_half_open_max()
    local tries = d:get(HALF_TRIES) or 0
    if tries >= max_p then
        metrics.incr("circuit_breaker_degraded_total")
        return false
    end
    d:set(HALF_TRIES, tries + 1)
    return true
end

function _M.record_success()
    local d = dict()
    if not d then
        return
    end
    local now = ngx.now()
    local st = d:get(STATE) or "closed"
    if st == "half_open" then
        local ok = (d:incr(HALF_OK, 1, 0) or 1)
        if ok >= config.storage_cb_half_open_success() then
            close_circuit(d)
        end
        _M.sync_metrics()
        return
    end
    if st == "open" then
        return
    end
    rotate_window(now, d)
    d:incr(WIN_OK, 1, 0)
    _M.sync_metrics()
end

function _M.record_failure()
    local d = dict()
    if not d then
        return
    end
    metrics.incr("storage_errors_total")
    local now = ngx.now()
    local st = d:get(STATE) or "closed"
    if st == "half_open" then
        open_circuit(now, d)
        return
    end
    if st == "open" then
        return
    end
    rotate_window(now, d)
    d:incr(WIN_FAIL, 1, 0)
    maybe_trip(now, d)
    _M.sync_metrics()
end

function _M.init_worker()
    _M.sync_metrics()
end

return _M