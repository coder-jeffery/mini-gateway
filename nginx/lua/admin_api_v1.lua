local store_mod = require "store"
local config = require "gateway_config"
local cjson = require "cjson"
local ngx = ngx
local hmac = require "resty.hmac"
local apikey_admin = require "apikey_admin"
local admin_audit = require "admin_audit"
local config_cache = require "config_cache"
local config_snapshot = require "config_snapshot"
local admin_rbac = require "admin_rbac"

local SIGN_WINDOW = 60 -- signature timestamp tolerance (seconds)

local function is_private_ip(ip)
    local a, b = ip:match("^(%d+)%.(%d+)%.")
    a, b = tonumber(a), tonumber(b)
    if not a then
        return false
    end
    if a == 10 then
        return true
    end
    if a == 172 and b and b >= 16 and b <= 31 then
        return true
    end
    if a == 192 and b == 168 then
        return true
    end
    if ip == "127.0.0.1" or ip == "::1" then
        return true
    end
    return false
end

local function admin_ip_allowed(client_ip)
    if os.getenv("GATEWAY_ADMIN_TRUST_PRIVATE") == "1" and is_private_ip(client_ip) then
        return true
    end
    return false
end

local function resp(code, data)
    ngx.status = code
    ngx.header["Content-Type"] = "application/json"
    ngx.header["X-Gateway-Storage"] = store_mod.name()
    ngx.say(cjson.encode(data))
    return ngx.exit(code)
end

ngx.req.read_body()
local body = ngx.req.get_body_data()
if not body then
    return resp(400, { ok = false, msg = "empty body" })
end
local req, err = cjson.decode(body)
if not req then
    return resp(400, { ok = false, msg = "invalid json" })
end

local client_ip = ngx.var.remote_addr
local backend = store_mod.backend()

local function finish_mutate(handle, code, data, action, req)
    admin_audit.emit("hmac", client_ip, action, req)
    config_cache.invalidate_for_action(action, req)
    backend.close(handle)
    return resp(code, data)
end

local handle, err = backend.new()
if not handle then
    ngx.log(ngx.ERR, "storage connect err: ", err)
    return resp(500, { ok = false, msg = "storage error" })
end

-- Layer 1: admin IP whitelist
local in_admin_whitelist, err = backend.sismember(handle, "admin:whitelist:ip", client_ip)
if err then
    backend.close(handle)
    return resp(500, { ok = false, msg = "storage error" })
end
if in_admin_whitelist ~= 1 and not admin_ip_allowed(client_ip) then
    backend.close(handle)
    return resp(403, { ok = false, msg = "forbidden: ip not in admin whitelist" })
end

-- Layer 2: HMAC signature
local ts = tonumber(req.ts)
local nonce = req.nonce
local sign = req.sign
if not ts or not nonce or not sign then
    backend.close(handle)
    return resp(400, { ok = false, msg = "missing sign params: ts, nonce, sign" })
end
local now = ngx.now()
if math.abs(now - ts) > SIGN_WINDOW then
    backend.close(handle)
    return resp(403, { ok = false, msg = "signature expired" })
end

local nonce_key = "admin:nonce:" .. nonce
local exists, err = backend.exists(handle, nonce_key)
if err then
    backend.close(handle)
    return resp(500, { ok = false, msg = "storage error" })
end
if exists == 1 then
    backend.close(handle)
    return resp(403, { ok = false, msg = "nonce reused, replay attack" })
end

local raw = tostring(ts) .. ":" .. tostring(nonce)
local h = hmac:new(config.admin_hmac_secret(), hmac.ALGOS.SHA256)
if not h then
    backend.close(handle)
    return resp(500, { ok = false, msg = "hmac init failed" })
end
if not h:update(raw) then
    backend.close(handle)
    return resp(500, { ok = false, msg = "hmac update failed" })
end
local calc_sign = h:final(nil, true)
if not calc_sign or calc_sign ~= sign then
    backend.close(handle)
    return resp(403, { ok = false, msg = "invalid signature" })
end

local ok_setex, setex_err = backend.setex(handle, nonce_key, "1", SIGN_WINDOW)
if not ok_setex then
    backend.close(handle)
    ngx.log(ngx.ERR, "nonce setex err: ", setex_err)
    return resp(500, { ok = false, msg = "storage error" })
end

local action = req.action
if not action then
    backend.close(handle)
    return resp(400, { ok = false, msg = "missing action" })
end

local v1_role, role_err = admin_rbac.v1_role(backend, handle)
if role_err then
    backend.close(handle)
    return resp(500, { ok = false, msg = "storage error" })
end
if not admin_rbac.allows(v1_role, action) then
    backend.close(handle)
    return resp(403, { ok = false, msg = admin_rbac.denied_msg(action), role = v1_role })
end

if action == "upsert_apikey" then
    local api_key = req.api_key
    local limit = tonumber(req.limit)
    local window = tonumber(req.window)
    if not api_key or not limit or not window then
        backend.close(handle)
        return resp(400, { ok = false, msg = "need api_key, limit, window" })
    end
    backend.set(handle, "apikey:" .. api_key, "1")
    backend.hset(handle, "apikey:meta:" .. api_key, "limit", limit, "window", window)
    apikey_admin.index_add_backend(backend, handle, api_key)
    return finish_mutate(handle, 200, { ok = true, msg = "apikey saved" }, action, req)

elseif action == "del_apikey" then
    local api_key = req.api_key
    if not api_key then
        backend.close(handle)
        return resp(400, { ok = false, msg = "need api_key" })
    end
    backend.del(handle, "apikey:" .. api_key)
    backend.del(handle, "apikey:meta:" .. api_key)
    apikey_admin.index_del_backend(backend, handle, api_key)
    return finish_mutate(handle, 200, { ok = true, msg = "apikey deleted" }, action, req)

elseif action == "apikey_list" then
    local result, list_err = apikey_admin.list_backend(backend, handle, req.page, req.page_size)
    backend.close(handle)
    if not result then
        return resp(500, { ok = false, msg = "storage error: " .. tostring(list_err) })
    end
    return resp(200, {
        ok = true,
        apikeys = result.items,
        total = result.total,
        page = result.page,
        page_size = result.page_size,
        total_pages = result.total_pages,
    })

elseif action == "get_apikey" then
    local api_key = req.api_key
    local item, get_err = apikey_admin.get_backend(backend, handle, api_key)
    backend.close(handle)
    if get_err == "need api_key" then
        return resp(400, { ok = false, msg = get_err })
    end
    if get_err == "not found" then
        return resp(404, { ok = false, msg = "apikey not found" })
    end
    if not item then
        return resp(500, { ok = false, msg = "storage error: " .. tostring(get_err) })
    end
    return resp(200, { ok = true, apikey = item })

elseif action == "whitelist_add" then
    local ip = req.ip
    if not ip then
        backend.close(handle)
        return resp(400, { ok = false, msg = "need ip" })
    end
    backend.sadd(handle, "whitelist:ip", ip)
    return finish_mutate(handle, 200, { ok = true, msg = "ip added to business whitelist" }, action, req)

elseif action == "whitelist_del" then
    local ip = req.ip
    if not ip then
        backend.close(handle)
        return resp(400, { ok = false, msg = "need ip" })
    end
    backend.srem(handle, "whitelist:ip", ip)
    return finish_mutate(handle, 200, { ok = true, msg = "ip removed from business whitelist" }, action, req)

elseif action == "whitelist_list" then
    local ips, list_err = backend.smembers(handle, "whitelist:ip")
    backend.close(handle)
    if list_err then
        return resp(500, { ok = false, msg = "storage error" })
    end
    return resp(200, { ok = true, whitelist = ips })

elseif action == "admin_whitelist_add" then
    local ip = req.ip
    if not ip then
        backend.close(handle)
        return resp(400, { ok = false, msg = "need ip" })
    end
    backend.sadd(handle, "admin:whitelist:ip", ip)
    return finish_mutate(handle, 200, { ok = true, msg = "ip added to admin whitelist" }, action, req)

elseif action == "admin_whitelist_del" then
    local ip = req.ip
    if not ip then
        backend.close(handle)
        return resp(400, { ok = false, msg = "need ip" })
    end
    backend.srem(handle, "admin:whitelist:ip", ip)
    return finish_mutate(handle, 200, { ok = true, msg = "ip removed from admin whitelist" }, action, req)

elseif action == "admin_whitelist_list" then
    local ips, list_err = backend.smembers(handle, "admin:whitelist:ip")
    backend.close(handle)
    if list_err then
        return resp(500, { ok = false, msg = "storage error" })
    end
    return resp(200, { ok = true, admin_whitelist = ips })

elseif action == "audit_list" then
    if not backend.admin_audit_list then
        backend.close(handle)
        return resp(501, { ok = false, msg = "audit_list unsupported for storage backend" })
    end
    local limit = tonumber(req.limit) or 50
    local lines, list_err = backend.admin_audit_list(handle, limit)
    backend.close(handle)
    if not lines then
        return resp(500, { ok = false, msg = "storage error: " .. tostring(list_err) })
    end
    local events = {}
    for _, line in ipairs(lines) do
        local ok_dec, obj = pcall(cjson.decode, line)
        if ok_dec and type(obj) == "table" then
            events[#events + 1] = obj
        end
    end
    return resp(200, { ok = true, events = events, count = #events })

elseif action == "route_quota_set" then
    local prefix = req.prefix
    local limit = tonumber(req.limit)
    local window = tonumber(req.window)
    if not prefix or not limit or not window then
        backend.close(handle)
        return resp(400, { ok = false, msg = "need prefix, limit, window" })
    end
    backend.sadd(handle, "policy:route_quota:index", prefix)
    backend.set(handle, "policy:route_quota:" .. prefix, cjson.encode({ limit = limit, window = window }))
    return finish_mutate(handle, 200, { ok = true, msg = "route quota saved" }, action, req)

elseif action == "route_quota_del" then
    local prefix = req.prefix
    if not prefix then
        backend.close(handle)
        return resp(400, { ok = false, msg = "need prefix" })
    end
    backend.srem(handle, "policy:route_quota:index", prefix)
    backend.del(handle, "policy:route_quota:" .. prefix)
    return finish_mutate(handle, 200, { ok = true, msg = "route quota deleted" }, action, req)

elseif action == "uri_block_add" then
    local prefix = req.prefix
    if not prefix then
        backend.close(handle)
        return resp(400, { ok = false, msg = "need prefix" })
    end
    backend.sadd(handle, "policy:uri_block", prefix)
    return finish_mutate(handle, 200, { ok = true, msg = "uri block added" }, action, req)

elseif action == "uri_block_del" then
    local prefix = req.prefix
    if not prefix then
        backend.close(handle)
        return resp(400, { ok = false, msg = "need prefix" })
    end
    backend.srem(handle, "policy:uri_block", prefix)
    return finish_mutate(handle, 200, { ok = true, msg = "uri block removed" }, action, req)

elseif action == "ua_block_add" then
    local pattern = req.pattern
    if not pattern then
        backend.close(handle)
        return resp(400, { ok = false, msg = "need pattern" })
    end
    backend.sadd(handle, "policy:ua_block", pattern)
    return finish_mutate(handle, 200, { ok = true, msg = "ua block added" }, action, req)

elseif action == "ua_block_del" then
    local pattern = req.pattern
    if not pattern then
        backend.close(handle)
        return resp(400, { ok = false, msg = "need pattern" })
    end
    backend.srem(handle, "policy:ua_block", pattern)
    return finish_mutate(handle, 200, { ok = true, msg = "ua block removed" }, action, req)

elseif action == "gray_rule_set" then
    local name = req.name
    if not name then
        backend.close(handle)
        return resp(400, { ok = false, msg = "need name" })
    end
    local rule = {
        percent = tonumber(req.percent) or 0,
        tag = req.tag or "gray",
        match_api_key = req.match_api_key,
        match_ip = req.match_ip,
    }
    backend.sadd(handle, "policy:gray_rule:index", name)
    backend.set(handle, "policy:gray_rule:" .. name, cjson.encode(rule))
    return finish_mutate(handle, 200, { ok = true, msg = "gray rule saved" }, action, req)

elseif action == "gray_rule_del" then
    local name = req.name
    if not name then
        backend.close(handle)
        return resp(400, { ok = false, msg = "need name" })
    end
    backend.srem(handle, "policy:gray_rule:index", name)
    backend.del(handle, "policy:gray_rule:" .. name)
    return finish_mutate(handle, 200, { ok = true, msg = "gray rule deleted" }, action, req)

elseif action == "config_snapshot_save" then
    local meta, snap_err = config_snapshot.save(backend, handle)
    if not meta then
        backend.close(handle)
        return resp(500, { ok = false, msg = tostring(snap_err) })
    end
    return finish_mutate(handle, 200, { ok = true, snapshot = meta }, action, req)

elseif action == "config_snapshot_restore" then
    local meta, rest_err = config_snapshot.restore(backend, handle)
    if not meta then
        backend.close(handle)
        return resp(400, { ok = false, msg = tostring(rest_err) })
    end
    return finish_mutate(handle, 200, { ok = true, restored = meta }, action, req)

elseif action == "rewrite_rule_set" then
    local name = req.name
    local match_prefix = req.match_prefix
    if not name or not match_prefix then
        backend.close(handle)
        return resp(400, { ok = false, msg = "need name, match_prefix" })
    end
    local rule = {
        match_prefix = match_prefix,
        uri_prefix = req.uri_prefix,
        match_api_key = req.match_api_key,
        headers = req.headers,
    }
    backend.sadd(handle, "policy:rewrite:index", name)
    backend.set(handle, "policy:rewrite:" .. name, cjson.encode(rule))
    return finish_mutate(handle, 200, { ok = true, msg = "rewrite rule saved" }, action, req)

elseif action == "rewrite_rule_del" then
    local name = req.name
    if not name then
        backend.close(handle)
        return resp(400, { ok = false, msg = "need name" })
    end
    backend.srem(handle, "policy:rewrite:index", name)
    backend.del(handle, "policy:rewrite:" .. name)
    return finish_mutate(handle, 200, { ok = true, msg = "rewrite rule deleted" }, action, req)

elseif action == "admin_role_set" then
    local role = req.role
    if not role then
        backend.close(handle)
        return resp(400, { ok = false, msg = "need role (full_admin|operator|read_only)" })
    end
    backend.set(handle, "admin:rbac:v1_role", role)
    return finish_mutate(handle, 200, { ok = true, msg = "v1 role updated", role = role }, action, req)

elseif action == "admin_role_get" then
    backend.close(handle)
    return resp(200, { ok = true, role = v1_role })

elseif action == "hmac_test" then
    backend.close(handle)
    return resp(200, {
        ok = true,
        msg = "hmac verified",
        client_ip = client_ip,
        ts = ts,
        nonce = nonce,
        storage = store_mod.name(),
    })

else
    backend.close(handle)
    return resp(400, { ok = false, msg = "unknown action" })
end