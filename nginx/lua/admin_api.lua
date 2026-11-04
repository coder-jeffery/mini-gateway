
local redis_util = require "redis_util"
local cjson = require "cjson"
local ngx = ngx

-- ========= 管理员密钥，调用接口必须传这个 =========
local ADMIN_SECRET = "admin-secret-2026"

local function resp(code, data)
    ngx.status = code
    ngx.header["Content-Type"] = "application/json"
    ngx.say(cjson.encode(data))
    return ngx.exit(code)
end

-- 读取 body
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


-- ========= 管理接口独立运维IP白名单校验 =========
local in_admin_whitelist, err = red:sismember("admin:whitelist:ip", client_ip)
if err then
    redis_util.close(red)
    ngx.log(ngx.ERR, "admin whitelist sismember err: ", err)
    return resp(500, {ok=false, msg="redis error"})
end
if in_admin_whitelist ~= 1 then
    redis_util.close(red)
    return resp(403, {ok=false, msg="forbidden: ip not in admin whitelist"})
end


-- 校验管理密钥
if req.admin_secret ~= ADMIN_SECRET then
    return resp(403, {ok=false, msg="admin secret invalid"})
end

local action = req.action
if not action then
    redis_util.close(red)
    return resp(400, {ok=false, msg="missing action"})
end


local red, err = redis_util.new()
if not red then
    ngx.log(ngx.ERR, "redis connect err: ", err)
    return resp(500, {ok=false, msg="redis error"})
end

-- ===================== Action 分支 =====================
if action == "upsert_apikey" then
    -- 新增/更新 apikey
    local api_key = req.api_key
    local limit = tonumber(req.limit)
    local window = tonumber(req.window)
    if not api_key or not limit or not window then
        redis_util.close(red)
        return resp(400, {ok=false, msg="need api_key, limit, window"})
    end
    red:set("apikey:" .. api_key, "1")
    red:hset("apikey:meta:" .. api_key, "limit", limit, "window", window)
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
    redis_util.close(red)
    return resp(200, {ok=true, msg="apikey deleted"})

elseif action == "whitelist_add" then
    local ip = req.ip
    if not ip then
        redis_util.close(red)
        return resp(400, {ok=false, msg="need ip"})
    end
    red:sadd("whitelist:ip", ip)
    redis_util.close(red)
    return resp(200, {ok=true, msg="ip added to whitelist"})

elseif action == "whitelist_del" then
    local ip = req.ip
    if not ip then
        redis_util.close(red)
        return resp(400, {ok=false, msg="need ip"})
    end
    red:srem("whitelist:ip", ip)
    redis_util.close(red)
    return resp(200, {ok=true, msg="ip removed from whitelist"})

elseif action == "whitelist_list" then
    local ips, err = red:smembers("whitelist:ip")
    redis_util.close(red)
    if err then
        return resp(500, {ok=false, msg="redis error"})
    end
    return resp(200, {ok=true, whitelist=ips})

else
    redis_util.close(red)
    return resp(400, {ok=false, msg="unknown action"})
end
