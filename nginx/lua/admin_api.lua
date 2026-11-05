local store_mod = require "store"
local cjson = require "cjson"
local ngx = ngx
local apikey_admin = require "apikey_admin"

local function resp(code, data)
    ngx.status = code
    ngx.header["Content-Type"] = "application/json"
    ngx.header["X-Gateway-Storage"] = store_mod.name()
    ngx.say(cjson.encode(data))
    return ngx.exit(code)
end

local auth_header = ngx.var.http_authorization
local token = nil
if auth_header then
    local m = ngx.re.match(auth_header, "^Bearer\\s+(.+)$", "jo")
    if m then
        token = m[1]
    end
end

ngx.req.read_body()
local body = ngx.req.get_body_data()
local req = {}
if body and #body > 0 then
    local decode_req, err = cjson.decode(body)
    if not decode_req then
        return resp(400, {ok=false, msg="invalid json"})
    end
    req = decode_req
end

local client_ip = ngx.var.remote_addr
local backend = store_mod.backend()
local handle, err = backend.new()
if not handle then
    ngx.log(ngx.ERR, "storage connect err: ", err)
    return resp(500, {ok=false, msg="storage error"})
end

local in_admin_whitelist, err = backend.sismember(handle, "admin:whitelist:ip", client_ip)
if err then
    backend.close(handle)
    return resp(500, {ok=false, msg="storage error"})
end
if in_admin_whitelist ~= 1 then
    backend.close(handle)
    return resp(403, {ok=false, msg="forbidden: ip not in admin whitelist"})
end

if not token then
    backend.close(handle)
    return resp(401, {ok=false, msg="missing Bearer token in Authorization header"})
end

local token_key = "admin:token:" .. token
local token_data_str, err = backend.get(handle, token_key)
if err or token_data_str == nil or token_data_str == ngx.null or token_data_str == "" then
    backend.close(handle)
    return resp(401, {ok=false, msg="invalid or revoked token"})
end
local token_data, err = cjson.decode(token_data_str)
if not token_data then
    backend.close(handle)
    return resp(401, {ok=false, msg="token data malformed"})
end

local now = ngx.now()
if token_data.expire_at ~= 0 and now > token_data.expire_at then
    backend.del(handle, token_key)
    backend.close(handle)
    return resp(401, {ok=false, msg="token expired"})
end

local action = req.action
if not action then
    backend.close(handle)
    return resp(400, {ok=false, msg="missing action"})
end

if action == "upsert_apikey" then
    local api_key = req.api_key
    local limit = tonumber(req.limit)
    local window = tonumber(req.window)
    if not api_key or not limit or not window then
        backend.close(handle)
        return resp(400, {ok=false, msg="need api_key, limit, window"})
    end
    backend.set(handle, "apikey:" .. api_key, "1")
    backend.hset(handle, "apikey:meta:" .. api_key, "limit", limit, "window", window)
    apikey_admin.index_add_backend(backend, handle, api_key)
    backend.close(handle)
    return resp(200, {ok=true, msg="apikey saved"})

elseif action == "del_apikey" then
    local api_key = req.api_key
    if not api_key then
        backend.close(handle)
        return resp(400, {ok=false, msg="need api_key"})
    end
    backend.del(handle, "apikey:" .. api_key)
    backend.del(handle, "apikey:meta:" .. api_key)
    apikey_admin.index_del_backend(backend, handle, api_key)
    backend.close(handle)
    return resp(200, {ok=true, msg="apikey deleted"})

elseif action == "apikey_list" then
    local result, err = apikey_admin.list_backend(backend, handle, req.page, req.page_size)
    backend.close(handle)
    if not result then
        return resp(500, {ok=false, msg="storage error: " .. tostring(err)})
    end
    return resp(200, {ok=true, apikeys=result.items, total=result.total, page=result.page, page_size=result.page_size, total_pages=result.total_pages})

elseif action == "get_apikey" then
    local api_key = req.api_key
    local item, err = apikey_admin.get_backend(backend, handle, api_key)
    backend.close(handle)
    if err == "need api_key" then
        return resp(400, {ok=false, msg=err})
    end
    if err == "not found" then
        return resp(404, {ok=false, msg="apikey not found"})
    end
    if not item then
        return resp(500, {ok=false, msg="storage error: " .. tostring(err)})
    end
    return resp(200, {ok=true, apikey=item})

elseif action == "whitelist_add" then
    local ip = req.ip
    if not ip then
        backend.close(handle)
        return resp(400, {ok=false, msg="need ip"})
    end
    backend.sadd(handle, "whitelist:ip", ip)
    backend.close(handle)
    return resp(200, {ok=true, msg="ip added to business whitelist"})

elseif action == "whitelist_del" then
    local ip = req.ip
    if not ip then
        backend.close(handle)
        return resp(400, {ok=false, msg="need ip"})
    end
    backend.srem(handle, "whitelist:ip", ip)
    backend.close(handle)
    return resp(200, {ok=true, msg="ip removed from business whitelist"})

elseif action == "whitelist_list" then
    local ips, err = backend.smembers(handle, "whitelist:ip")
    backend.close(handle)
    if err then
        return resp(500, {ok=false, msg="storage error"})
    end
    return resp(200, {ok=true, whitelist=ips})

elseif action == "admin_whitelist_add" then
    local ip = req.ip
    if not ip then
        backend.close(handle)
        return resp(400, {ok=false, msg="need ip"})
    end
    backend.sadd(handle, "admin:whitelist:ip", ip)
    backend.close(handle)
    return resp(200, {ok=true, msg="ip added to admin whitelist"})

elseif action == "admin_whitelist_del" then
    local ip = req.ip
    if not ip then
        backend.close(handle)
        return resp(400, {ok=false, msg="need ip"})
    end
    backend.srem(handle, "admin:whitelist:ip", ip)
    backend.close(handle)
    return resp(200, {ok=true, msg="ip removed from admin whitelist"})

elseif action == "admin_whitelist_list" then
    local ips, err = backend.smembers(handle, "admin:whitelist:ip")
    backend.close(handle)
    if err then
        return resp(500, {ok=false, msg="storage error"})
    end
    return resp(200, {ok=true, admin_whitelist=ips})

elseif action == "token_issue" then
    local new_token = ngx.md5(ngx.now() .. ":" .. ngx.worker.pid() .. ":" .. math.random())
    local creator = req.creator or "unknown"
    local ttl_sec = tonumber(req.ttl) or 0
    local expire_at = 0
    if ttl_sec > 0 then
        expire_at = ngx.now() + ttl_sec
    end
    local token_info = {
        creator = creator,
        expire_at = expire_at
    }
    backend.set(handle, "admin:token:" .. new_token, cjson.encode(token_info))
    backend.close(handle)
    return resp(200, {ok=true, token=new_token, info=token_info})

elseif action == "token_revoke" then
    local rev_token = req.token
    if not rev_token then
        backend.close(handle)
        return resp(400, {ok=false, msg="need token"})
    end
    backend.del(handle, "admin:token:" .. rev_token)
    backend.close(handle)
    return resp(200, {ok=true, msg="token revoked"})

elseif action == "token_list" then
    backend.close(handle)
    return resp(400, {ok=false, msg="token_list not implemented"})

else
    backend.close(handle)
    return resp(400, {ok=false, msg="unknown action"})
end
