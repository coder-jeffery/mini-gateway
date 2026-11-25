local redis_util = require "redis_util"
local cjson = require "cjson"

local _M = {}

function _M.new()
    local red, err = redis_util.new()
    if not red then
        return nil, err
    end
    return { _kind = "redis", _red = red }, nil
end

function _M.close(store)
    if store and store._red then
        redis_util.close(store._red)
    end
    return true
end

function _M.backend_name()
    return "redis"
end

function _M.exists(store, key)
    return store._red:exists(key)
end

function _M.get(store, key)
    return store._red:get(key)
end

function _M.set(store, key, value)
    return store._red:set(key, value)
end

function _M.setex(store, key, value, ttl_sec)
    return store._red:setex(key, ttl_sec, value)
end

function _M.del(store, key)
    return store._red:del(key)
end

function _M.hmget(store, hash_key, f1, f2)
    return store._red:hmget(hash_key, f1, f2)
end

function _M.hset(store, hash_key, f1, v1, f2, v2)
    return store._red:hset(hash_key, f1, v1, f2, v2)
end

function _M.sismember(store, set_name, member)
    return store._red:sismember(set_name, member)
end

function _M.sadd(store, set_name, member)
    return store._red:sadd(set_name, member)
end

function _M.srem(store, set_name, member)
    return store._red:srem(set_name, member)
end

function _M.smembers(store, set_name)
    return store._red:smembers(set_name)
end

function _M.sliding_window(store, limit_key, window_sec, now, unique_id)
    local red = store._red
    local window_start = now - window_sec
    red:init_pipeline()
    red:zremrangebyscore(limit_key, 0, window_start)
    red:zcard(limit_key)
    red:zadd(limit_key, now, unique_id)
    red:expire(limit_key, window_sec + 10)
    local res, err = red:commit_pipeline()
    if not res then
        return nil, err
    end
    return res[2], nil
end

function _M.access_log_append(store, line)
    return store._red:rpush("gateway:access_log", line)
end

function _M.admin_audit_append(store, line)
    return store._red:rpush("gateway:admin_audit", line)
end

function _M.admin_audit_list(store, limit)
    local red = store._red
    limit = tonumber(limit) or 50
    if limit < 1 then
        limit = 1
    end
    if limit > 200 then
        limit = 200
    end
    local len, err = red:llen("gateway:admin_audit")
    if not len then
        return nil, err
    end
    if len == 0 then
        return {}, nil
    end
    local start = len - limit
    if start < 0 then
        start = 0
    end
    return red:lrange("gateway:admin_audit", start, len - 1)
end

function _M.list_kv_prefix(store, prefix)
    local red = store._red
    local ids = {}
    local seen = {}
    local cursor = "0"
    repeat
        local res, err = red:scan(cursor, "MATCH", prefix .. "*", "COUNT", 200)
        if not res then
            return nil, err
        end
        cursor = res[1]
        for _, key in ipairs(res[2]) do
            local id = key:sub(#prefix + 1)
            if id ~= "" and not seen[id] then
                seen[id] = true
                ids[#ids + 1] = id
            end
        end
    until cursor == "0"
    table.sort(ids)
    return ids, nil
end

function _M.bootstrap(store, opts)
    for ip in string.gmatch(opts.admin_whitelist_ips, "[^,%s]+") do
        _M.sadd(store, "admin:whitelist:ip", ip)
    end
    _M.set(store, "apikey:" .. opts.api_key, "1")
    _M.hset(store, "apikey:meta:" .. opts.api_key, "limit", opts.api_key_limit, "window", opts.api_key_window)
    _M.sadd(store, "apikey:index", opts.api_key)
    local token_info = cjson.encode({ creator = "bootstrap", expire_at = 0 })
    _M.set(store, "admin:token:" .. opts.admin_token, token_info)
    return true, nil
end

return _M
