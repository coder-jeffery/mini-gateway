-- Parse upstream peers and weighted round-robin among healthy nodes.

local config = require "gateway_config"
local health = require "upstream_health"
local ngx = ngx

local _M = {}

local rr_dict = ngx.shared.gateway_upstream_health

local function rr_key()
    return "upe:rr:counter"
end

local function configured_peers()
    local override = ngx.ctx.gateway_service_peers
    if type(override) == "table" and #override > 0 then
        return override
    end
    return config.upstream_peers()
end

function _M.all_peers()
    return configured_peers()
end

function _M.healthy_peers(exclude_keys)
    exclude_keys = exclude_keys or {}
    local seen = {}
    for _, k in ipairs(exclude_keys) do
        seen[k] = true
    end
    local out = {}
    for _, p in ipairs(configured_peers()) do
        local key = health.peer_key(p.host, p.port)
        if not seen[key] and health.is_available(p.host, p.port) then
            out[#out + 1] = {
                host = p.host,
                port = p.port,
                weight = p.weight or 1,
                key = key,
            }
        end
    end
    return out
end

function _M.pick_peer(peers)
    if #peers == 0 then
        return nil
    end
    if #peers == 1 then
        return peers[1]
    end
    local total_weight = 0
    for _, p in ipairs(peers) do
        total_weight = total_weight + (p.weight or 1)
    end
    local n = 0
    if rr_dict then
        n = rr_dict:incr(rr_key(), 1, 0) or 0
    else
        n = math.floor(ngx.now() * 1000)
    end
    local slot = n % total_weight
    local acc = 0
    for _, p in ipairs(peers) do
        acc = acc + (p.weight or 1)
        if slot < acc then
            return p
        end
    end
    return peers[1]
end

function _M.parse_upstream_addr(addr)
    if not addr or addr == "" then
        return nil, nil
    end
    -- upstream_addr: "1.2.3.4:80" or "host:port" (first peer if multiple tries)
    local first = addr:match("^([^,]+)")
    if not first then
        first = addr
    end
    local host, port = first:match("^%[([^%]]+)%]:(%d+)$")
    if host then
        return host, tonumber(port)
    end
    host, port = first:match("^([^:]+):(%d+)$")
    if host then
        return host, tonumber(port)
    end
    return nil, nil
end

return _M