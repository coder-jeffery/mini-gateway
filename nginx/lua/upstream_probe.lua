-- Active upstream health checks (ngx.timer); not run inside balancer_by_lua.

local config = require "gateway_config"
local health = require "upstream_health"
local ngx = ngx

local _M = {}

local function probe_lock_key(peer_key)
    return "upe:lock:" .. peer_key
end

local function try_lock(peer_key, ttl)
    local dict = ngx.shared.gateway_upstream_health
    if not dict then
        return true
    end
    local ok = dict:add(probe_lock_key(peer_key), 1, ttl)
    return ok
end

local function http_probe(peer)
    local host = peer.host
    local port = peer.port
    local scheme = config.upstream_scheme()
    local path = config.upstream_health_path()
    local timeout = config.upstream_health_timeout_ms()
    local connect_host = config.upstream_health_host() or host

    local sock = ngx.socket.tcp()
    sock:settimeout(timeout)

    local ok, err = sock:connect(host, port)
    if not ok then
        return false, "connect: " .. (err or "failed")
    end

    if scheme == "https" then
        local sess, ssl_err = sock:sslhandshake(nil, connect_host, false)
        if not sess then
            sock:close()
            return false, "ssl: " .. (ssl_err or "failed")
        end
    end

    local req = string.format(
        "GET %s HTTP/1.1\r\nHost: %s\r\nUser-Agent: mini-gateway-probe\r\nConnection: close\r\n\r\n",
        path,
        connect_host
    )
    local sent, send_err = sock:send(req)
    if not sent then
        sock:close()
        return false, "send: " .. (send_err or "failed")
    end

    local line, recv_err = sock:receive("*l")
    sock:close()
    if not line then
        return false, "recv: " .. (recv_err or "failed")
    end

    local status = tonumber(line:match("^HTTP/%d%.%d%s+(%d+)"))
    if not status then
        return false, "bad status line"
    end
    local min_c, max_c = config.upstream_health_status_range()
    if status < min_c or status > max_c then
        return false, "status " .. tostring(status)
    end
    return true
end

local function probe_all(premature)
    if premature then
        return
    end

    local peers = config.upstream_peers()
    local interval = config.upstream_health_interval()
    local lock_ttl = math.max(1, math.floor(interval * 0.8))

    for _, peer in ipairs(peers) do
        local key = health.peer_key(peer.host, peer.port)
        if try_lock(key, lock_ttl) then
            local ok, reason = http_probe(peer)
            if ok then
                health.record_probe_success(peer.host, peer.port)
            else
                health.record_probe_failure(peer.host, peer.port, reason)
            end
        end
    end

    local delay = interval + (ngx.worker.id() % 3)
    local ok, err = ngx.timer.at(delay, probe_all)
    if not ok then
        ngx.log(ngx.ERR, "upstream probe reschedule failed: ", err)
    end
end

function _M.start()
    local interval = config.upstream_health_interval()
    local stagger = ngx.worker.id() * 0.5
    local ok, err = ngx.timer.at(stagger, probe_all)
    if not ok then
        return false, err
    end
    ngx.log(ngx.NOTICE, "upstream health probe scheduled every ", interval, "s (worker ", ngx.worker.id(), ")")
    return true
end

return _M