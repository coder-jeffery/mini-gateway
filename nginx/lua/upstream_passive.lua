-- Passive upstream health updates from proxy result (call from log_by_lua).

local pool = require "upstream_pool"
local health = require "upstream_health"
local ngx = ngx

local _M = {}

function _M.observe()
    local status = ngx.var.upstream_status
    local addr = ngx.var.upstream_addr
    local connect_time = ngx.var.upstream_connect_time

    local host = ngx.ctx.upstream_peer_host
    local port = ngx.ctx.upstream_peer_port

    if (not host or not port) and addr and addr ~= "" then
        host, port = pool.parse_upstream_addr(addr)
    end

    if not host or not port then
        return
    end

    local upstream_code = tonumber(status)
    local connect_failed = (connect_time == nil or connect_time == "" or connect_time == "-")
        and (upstream_code == nil or upstream_code == 0)

    if connect_failed or (upstream_code and upstream_code >= 500) then
        health.record_passive_failure(host, port)
        return
    end

    if upstream_code and upstream_code > 0 and upstream_code < 500 then
        health.record_passive_success(host, port)
    end
end

return _M