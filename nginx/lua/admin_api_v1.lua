local store_mod = require "store"
local config = require "gateway_config"
local cjson = require "cjson"
local ngx = ngx
local hmac = require "resty.hmac"
local apikey_admin = require "apikey_admin"

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
    backend.close(handle)
    return resp(200, { ok = true, msg = "apikey saved" })

elseif action == "del_apikey" then
    local api_key = req.api_key
    if not api_key then
        backend.close(handle)
        return resp(400, { ok = false, msg = "need api_key" })
    end
    backend.del(handle, "apikey:" .. api_key)
    backend.del(handle, "apikey:meta:" .. api_key)
    apikey_admin.index_del_backend(backend, handle, api_key)
    backend.close(handle)
    return resp(200, { ok = true, msg = "apikey deleted" })

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
    backend.close(handle)
    return resp(200, { ok = true, msg = "ip added to business whitelist" })

elseif action == "whitelist_del" then
    local ip = req.ip
    if not ip then
        backend.close(handle)
        return resp(400, { ok = false, msg = "need ip" })
    end
    backend.srem(handle, "whitelist:ip", ip)
    backend.close(handle)
    return resp(200, { ok = true, msg = "ip removed from business whitelist" })

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
    backend.close(handle)
    return resp(200, { ok = true, msg = "ip added to admin whitelist" })

elseif action == "admin_whitelist_del" then
    local ip = req.ip
    if not ip then
        backend.close(handle)
        return resp(400, { ok = false, msg = "need ip" })
    end
    backend.srem(handle, "admin:whitelist:ip", ip)
    backend.close(handle)
    return resp(200, { ok = true, msg = "ip removed from admin whitelist" })

elseif action == "admin_whitelist_list" then
    local ips, list_err = backend.smembers(handle, "admin:whitelist:ip")
    backend.close(handle)
    if list_err then
        return resp(500, { ok = false, msg = "storage error" })
    end
    return resp(200, { ok = true, admin_whitelist = ips })

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