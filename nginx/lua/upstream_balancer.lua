-- balancer_by_lua: pick a healthy peer; supports one failover retry via set_more_tries.

local pool = require "upstream_pool"
local health = require "upstream_health"
local config = require "gateway_config"
local balancer = require "ngx.balancer"
local cjson = require "cjson"
local ngx = ngx

ngx.ctx.upstream_tried = ngx.ctx.upstream_tried or {}

local exclude = ngx.ctx.upstream_tried
local peers = pool.healthy_peers(exclude)

if #peers == 0 then
  -- allow one attempt on down peers if everything is marked down (last resort)
    local all = pool.all_peers()
    if #exclude == 0 and #all > 0 then
        peers = {}
        for _, p in ipairs(all) do
            peers[#peers + 1] = {
                host = p.host,
                port = p.port,
                weight = p.weight or 1,
                key = health.peer_key(p.host, p.port),
            }
        end
        ngx.header["X-Upstream-Degraded"] = "all-down"
    end
end

if #peers == 0 then
    ngx.log(ngx.ERR, "balancer: no upstream peers configured")
    ngx.status = 503
    ngx.header["Content-Type"] = "application/json"
    ngx.say(cjson.encode({ code = 503, msg = "no upstream peers available" }))
    return ngx.exit(503)
end

local peer = pool.pick_peer(peers)
if not peer then
    return ngx.exit(502)
end

exclude[#exclude + 1] = peer.key
ngx.ctx.upstream_peer_key = peer.key
ngx.ctx.upstream_peer_host = peer.host
ngx.ctx.upstream_peer_port = peer.port

local max_tries = config.upstream_max_tries()
local remaining = max_tries - #exclude
if remaining < 0 then
    remaining = 0
end
balancer.set_more_tries(remaining)

local timeout = config.upstream_timeouts()
balancer.set_timeouts(timeout.connect, timeout.send, timeout.read)

local ok, err = balancer.set_current_peer(peer.host, peer.port)
if not ok then
    ngx.log(ngx.ERR, "balancer set_current_peer failed: ", err)
    return ngx.exit(502)
end

ngx.var.upstream_balancer_peer = peer.key