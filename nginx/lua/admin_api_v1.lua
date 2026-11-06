local redis_util = require "redis_util"
local cjson = require "cjson"
local ngx = ngx
local hmac = require "resty.hmac"
local apikey_admin = require "apikey_admin"

local ADMIN_SECRET = "admin-secret-2026"
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
    ngx.say(cjson.encode(data))
    return ngx.exit(code)
end

ngx.req.read_body()
local body = ngx.req.get_body_data()
if not body then
    return resp(400, {ok=false, msg="empty body"})
end
local req, err = cjson.decode(body)
if not req then
    return resp(400, {ok=false, msg="invalid json"})
end

local client_ip = ngx.var.remote_addr
local red, err = redis_util.new()
if not red then
    ngx.log(ngx.ERR, "redis connect err: ", err)
    return resp(500, {ok=false, msg="redis error"})
end

-- Layer 1: admin IP whitelist
local in_admin_whitelist, err = red:sismember("admin:whitelist:ip", client_ip)
if err then
    redis_util.close(red)
    return resp(500, {ok=false, msg="redis error"})
end
if in_admin_whitelist ~= 1 and not admin_ip_allowed(client_ip) then
    redis_util.close(red)
    return resp(403, {ok=false, msg="forbidden: ip not in admin whitelist"})
end

-- Layer 2: HMAC signature (replaces plain admin_secret comparison)
local ts = tonumber(req.ts)
local nonce = req.nonce
local sign = req.sign
if not ts or not nonce or not sign then
    redis_util.close(red)
    return resp(400, {ok=false, msg="missing sign params: ts, nonce, sign"})
end
local now = ngx.now()
if math.abs(now - ts) > SIGN_WINDOW then
    redis_util.close(red)
    return resp(403, {ok=false, msg="signature expired"})
end

-- Replay protection: reject reused nonce
local nonce_key = "admin:nonce:" .. nonce
local exists, err = red:exists(nonce_key)
if err then
    redis_util.close(red)
    return resp(500, {ok=false, msg="redis error"})
end
if exists == 1 then
    redis_util.close(red)
    return resp(403, {ok=false, msg="nonce reused, replay attack"})
end

-- Server-side sign; match Python hmac.hexdigest() via final(..., true) for hex
local raw = tostring(ts) .. ":" .. tostring(nonce)
local h = hmac:new(ADMIN_SECRET, hmac.ALGOS.SHA256)
if not h then
    redis_util.close(red)
    return resp(500, {ok=false, msg="hmac init failed"})
end
if not h:update(raw) then
    redis_util.close(red)
    return resp(500, {ok=false, msg="hmac update failed"})
end
local calc_sign = h:final(nil, true)
if not calc_sign or calc_sign ~= sign then
    redis_util.close(red)
    return resp(403, {ok=false, msg="invalid signature"})
end
-- Mark nonce used with TTL
red:setex(nonce_key, SIGN_WINDOW, "1")

local action = req.action
if not action then
    redis_util.close(red)
    return resp(400, {ok=false, msg="missing action"})
end

if action == "upsert_apikey" then
    local api_key = req.api_key
    local limit = tonumber(req.limit)
    local window = tonumber(req.window)
    if not api_key or not limit or not window then
        redis_util.close(red)
        return resp(400, {ok=false, msg="need api_key, limit, window"})
    end
    red:set("apikey:" .. api_key, "1")
    red:hset("apikey:meta:" .. api_key, "limit", limit, "window", window)
    apikey_admin.index_add_redis(red, api_key)
    redis_util.close(red)
    return resp(200, {ok=true, msg="apikey saved"})

elseif action == "del_apikey" then
    local api_key = req.api_key
    if not api_key then
        redis_util.close(red)
        return resp(400, {ok=false, msg="need api_key"})
    end
    red:del("apikey:" .. api_key)
    red:del("apikey:meta:" .. api_key)
    apikey_admin.index_del_redis(red, api_key)
    redis_util.close(red)
    return resp(200, {ok=true, msg="apikey deleted"})

elseif action == "apikey_list" then
    local result, err = apikey_admin.list_redis(red, req.page, req.page_size)
    redis_util.close(red)
    if not result then
        return resp(500, {ok=false, msg="redis error: " .. tostring(err)})
    end
    return resp(200, {ok=true, apikeys=result.items, total=result.total, page=result.page, page_size=result.page_size, total_pages=result.total_pages})

elseif action == "get_apikey" then
    local api_key = req.api_key
    local item, err = apikey_admin.get_redis(red, api_key)
    redis_util.close(red)
    if err == "need api_key" then
        return resp(400, {ok=false, msg=err})
    end
    if err == "not found" then
        return resp(404, {ok=false, msg="apikey not found"})
    end
    if not item then
        return resp(500, {ok=false, msg="redis error: " .. tostring(err)})
    end
    return resp(200, {ok=true, apikey=item})

elseif action == "whitelist_add" then
    local ip = req.ip
    if not ip then
        redis_util.close(red)
        return resp(400, {ok=false, msg="need ip"})
    end
    red:sadd("whitelist:ip", ip)
    redis_util.close(red)
    return resp(200, {ok=true, msg="ip added to business whitelist"})

elseif action == "whitelist_del" then
    local ip = req.ip
    if not ip then
        redis_util.close(red)
        return resp(400, {ok=false, msg="need ip"})
    end
    red:srem("whitelist:ip", ip)
    redis_util.close(red)
    return resp(200, {ok=true, msg="ip removed from business whitelist"})

elseif action == "whitelist_list" then
    local ips, err = red:smembers("whitelist:ip")
    redis_util.close(red)
    if err then
        return resp(500, {ok=false, msg="redis error"})
    end
    return resp(200, {ok=true, whitelist=ips})

elseif action == "admin_whitelist_add" then
    local ip = req.ip
    if not ip then
        redis_util.close(red)
        return resp(400, {ok=false, msg="need ip"})
    end
    red:sadd("admin:whitelist:ip", ip)
    redis_util.close(red)
    return resp(200, {ok=true, msg="ip added to admin whitelist"})

elseif action == "admin_whitelist_del" then
    local ip = req.ip
    if not ip then
        redis_util.close(red)
        return resp(400, {ok=false, msg="need ip"})
    end
    red:srem("admin:whitelist:ip", ip)
    redis_util.close(red)
    return resp(200, {ok=true, msg="ip removed from admin whitelist"})

elseif action == "admin_whitelist_list" then
    local ips, err = red:smembers("admin:whitelist:ip")
    redis_util.close(red)
    if err then
        return resp(500, {ok=false, msg="redis error"})
    end
    return resp(200, {ok=true, admin_whitelist=ips})

elseif action == "hmac_test" then
    redis_util.close(red)
    return resp(200, {
        ok = true,
        msg = "hmac verified",
        client_ip = client_ip,
        ts = ts,
        nonce = nonce,
    })

else
    redis_util.close(red)
    return resp(400, {ok=false, msg="unknown action"})
end
