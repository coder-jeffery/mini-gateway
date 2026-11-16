-- Upstream peer health state in lua_shared_dict (active probe + passive traffic).

local config = require "gateway_config"
local cjson = require "cjson"
local ngx = ngx

local _M = {}

local dict = ngx.shared.gateway_upstream_health

local function peer_key(host, port)
    return tostring(host) .. ":" .. tostring(port)
end

local function state_key(key)
    return "upe:" .. key
end

local function default_record()
    return {
        state = "up",
        consecutive_fail = 0,
        passive_fail = 0,
        recover_streak = 0,
        last_probe_at = 0,
        last_success_at = 0,
        last_fail_at = 0,
    }
end

local function load_record(key)
    local raw = dict and dict:get(state_key(key))
    if not raw then
        return default_record()
    end
    local ok, rec = pcall(cjson.decode, raw)
    if not ok or type(rec) ~= "table" then
        return default_record()
    end
    if rec.state ~= "up" and rec.state ~= "down" then
        rec.state = "up"
    end
    rec.consecutive_fail = tonumber(rec.consecutive_fail) or 0
    rec.passive_fail = tonumber(rec.passive_fail) or 0
    rec.last_probe_at = tonumber(rec.last_probe_at) or 0
    rec.last_success_at = tonumber(rec.last_success_at) or 0
    rec.last_fail_at = tonumber(rec.last_fail_at) or 0
    rec.recover_streak = tonumber(rec.recover_streak) or 0
    return rec
end

local function save_record(key, rec)
    if not dict then
        return false, "no shared dict"
    end
    local raw, err = cjson.encode(rec)
    if not raw then
        return false, err
    end
    local ok, serr = dict:set(state_key(key), raw)
    if not ok then
        return false, serr
    end
    return true
end

function _M.peer_key(host, port)
    return peer_key(host, port)
end

function _M.is_available(host, port)
    local rec = load_record(peer_key(host, port))
    return rec.state == "up"
end

function _M.record_probe_success(host, port)
    local key = peer_key(host, port)
    local rec = load_record(key)
    local now = ngx.now()
    rec.last_probe_at = now
    rec.last_success_at = now
    rec.consecutive_fail = 0
    rec.passive_fail = 0
    local pass_n = config.upstream_health_pass_threshold()
    if rec.state == "down" then
        rec.recover_streak = rec.recover_streak + 1
        if rec.recover_streak >= pass_n then
            rec.state = "up"
            rec.recover_streak = 0
        end
    else
        rec.state = "up"
        rec.recover_streak = 0
    end
    save_record(key, rec)
end

function _M.record_probe_failure(host, port, reason)
    local key = peer_key(host, port)
    local rec = load_record(key)
    local now = ngx.now()
    rec.last_probe_at = now
    rec.last_fail_at = now
    rec.consecutive_fail = rec.consecutive_fail + 1
    rec.recover_streak = 0
    local fail_n = config.upstream_health_fail_threshold()
    if rec.consecutive_fail >= fail_n then
        rec.state = "down"
    end
    ngx.log(ngx.WARN, "upstream probe fail ", key, ": ", reason or "unknown")
    save_record(key, rec)
end

function _M.record_passive_success(host, port)
    local key = peer_key(host, port)
    if not host or not port then
        return
    end
    local rec = load_record(key)
    rec.passive_fail = 0
    if rec.state == "down" then
        -- passive success does not instantly lift down; active probe governs recovery
        save_record(key, rec)
        return
    end
    rec.consecutive_fail = 0
    rec.state = "up"
    save_record(key, rec)
end

function _M.record_passive_failure(host, port)
    local key = peer_key(host, port)
    if not host or not port then
        return
    end
    local rec = load_record(key)
    local now = ngx.now()
    rec.last_fail_at = now
    rec.passive_fail = rec.passive_fail + 1
    rec.consecutive_fail = rec.consecutive_fail + 1
    local fail_n = config.upstream_health_fail_threshold()
    if rec.consecutive_fail >= fail_n then
        rec.state = "down"
        ngx.log(ngx.WARN, "upstream passive mark down: ", key)
    end
    save_record(key, rec)
end

function _M.snapshot()
    local peers = config.upstream_peers()
    local out = {}
    for _, p in ipairs(peers) do
        local key = peer_key(p.host, p.port)
        local rec = load_record(key)
        out[#out + 1] = {
            peer = key,
            host = p.host,
            port = p.port,
            state = rec.state,
            consecutive_fail = rec.consecutive_fail,
            passive_fail = rec.passive_fail,
            last_probe_at = rec.last_probe_at,
            last_success_at = rec.last_success_at,
            last_fail_at = rec.last_fail_at,
            recover_streak = rec.recover_streak,
        }
    end
    return out
end

return _M