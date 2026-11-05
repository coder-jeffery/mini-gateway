local cjson = require "cjson"
local config = require "gateway_config"

local _M = {}
local db_cache = nil
local lsqlite3 = nil

local function open_db()
    if db_cache then
        return db_cache, nil
    end
    local ok, mod = pcall(require, "lsqlite3")
    if not ok then
        return nil, "lsqlite3 not installed (build openresty/Dockerfile for sqlite mode)"
    end
    lsqlite3 = mod
    local path = config.sqlite_path()
    local db, msg = lsqlite3.open(path)
    if not db then
        return nil, "sqlite open failed: " .. tostring(msg)
    end
    db:exec([[
        PRAGMA journal_mode=WAL;
        CREATE TABLE IF NOT EXISTS kv (k TEXT PRIMARY KEY, v TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS hash (
            hk TEXT NOT NULL, field TEXT NOT NULL, v TEXT NOT NULL,
            PRIMARY KEY (hk, field)
        );
        CREATE TABLE IF NOT EXISTS set_members (
            set_name TEXT NOT NULL, member TEXT NOT NULL,
            PRIMARY KEY (set_name, member)
        );
        CREATE TABLE IF NOT EXISTS zset (
            zkey TEXT NOT NULL, member TEXT NOT NULL, score REAL NOT NULL,
            PRIMARY KEY (zkey, member)
        );
        CREATE TABLE IF NOT EXISTS access_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT, v TEXT NOT NULL
        );
    ]])
    db_cache = db
    return db, nil
end

function _M.new()
    local db, err = open_db()
    if not db then
        return nil, err
    end
    return { _kind = "sqlite", _db = db }, nil
end

function _M.close(_store)
    return true
end

function _M.backend_name()
    return "sqlite"
end

local function db(store)
    return store._db
end

function _M.exists(store, key)
    local stmt = db(store):prepare("SELECT 1 FROM kv WHERE k = ? LIMIT 1")
    stmt:bind_values(key)
    local row = stmt:step()
    stmt:finalize()
    return row == lsqlite3.ROW and 1 or 0, nil
end

function _M.get(store, key)
    local stmt = db(store):prepare("SELECT v FROM kv WHERE k = ? LIMIT 1")
    stmt:bind_values(key)
    local row = stmt:step()
    local val = nil
    if row == lsqlite3.ROW then
        val = stmt:get_value(0)
    end
    stmt:finalize()
    return val, nil
end

function _M.set(store, key, value)
    local stmt = db(store):prepare("INSERT OR REPLACE INTO kv(k, v) VALUES(?, ?)")
    stmt:bind_values(key, value)
    stmt:step()
    stmt:finalize()
    return true, nil
end

function _M.del(store, key)
    local stmt = db(store):prepare("DELETE FROM kv WHERE k = ?")
    stmt:bind_values(key)
    stmt:step()
    stmt:finalize()
    stmt = db(store):prepare("DELETE FROM hash WHERE hk = ?")
    stmt:bind_values(key)
    stmt:step()
    stmt:finalize()
    return true, nil
end

function _M.hmget(store, hash_key, f1, f2)
    local function one(field)
        local stmt = db(store):prepare("SELECT v FROM hash WHERE hk = ? AND field = ? LIMIT 1")
        stmt:bind_values(hash_key, field)
        local row = stmt:step()
        local val = ngx.null
        if row == lsqlite3.ROW then
            val = stmt:get_value(0)
        end
        stmt:finalize()
        return val
    end
    return { one(f1), one(f2) }, nil
end

function _M.hset(store, hash_key, f1, v1, f2, v2)
    local function upsert(field, val)
        local stmt = db(store):prepare("INSERT OR REPLACE INTO hash(hk, field, v) VALUES(?, ?, ?)")
        stmt:bind_values(hash_key, field, tostring(val))
        stmt:step()
        stmt:finalize()
    end
    upsert(f1, v1)
    if f2 and v2 then
        upsert(f2, v2)
    end
    return true, nil
end

function _M.sismember(store, set_name, member)
    local stmt = db(store):prepare("SELECT 1 FROM set_members WHERE set_name = ? AND member = ? LIMIT 1")
    stmt:bind_values(set_name, member)
    local row = stmt:step()
    stmt:finalize()
    return row == lsqlite3.ROW and 1 or 0, nil
end

function _M.sadd(store, set_name, member)
    local stmt = db(store):prepare("INSERT OR IGNORE INTO set_members(set_name, member) VALUES(?, ?)")
    stmt:bind_values(set_name, member)
    stmt:step()
    stmt:finalize()
    return true, nil
end

function _M.srem(store, set_name, member)
    local stmt = db(store):prepare("DELETE FROM set_members WHERE set_name = ? AND member = ?")
    stmt:bind_values(set_name, member)
    stmt:step()
    stmt:finalize()
    return true, nil
end

function _M.smembers(store, set_name)
    local stmt = db(store):prepare("SELECT member FROM set_members WHERE set_name = ?")
    stmt:bind_values(set_name)
    local out = {}
    while stmt:step() == lsqlite3.ROW do
        out[#out + 1] = stmt:get_value(0)
    end
    stmt:finalize()
    return out, nil
end

function _M.sliding_window(store, limit_key, window_sec, now, unique_id)
    local d = db(store)
    local del = d:prepare("DELETE FROM zset WHERE zkey = ? AND score < ?")
    del:bind_values(limit_key, now - window_sec)
    del:step()
    del:finalize()

    local cnt = 0
    local stmt = d:prepare("SELECT COUNT(*) FROM zset WHERE zkey = ?")
    stmt:bind_values(limit_key)
    if stmt:step() == lsqlite3.ROW then
        cnt = stmt:get_value(0)
    end
    stmt:finalize()

    local ins = d:prepare("INSERT OR REPLACE INTO zset(zkey, member, score) VALUES(?, ?, ?)")
    ins:bind_values(limit_key, unique_id, now)
    ins:step()
    ins:finalize()
    return cnt, nil
end

function _M.access_log_append(store, line)
    local stmt = db(store):prepare("INSERT INTO access_log(v) VALUES(?)")
    stmt:bind_values(line)
    stmt:step()
    stmt:finalize()
    return true, nil
end

function _M.list_kv_prefix(store, prefix)
    local stmt = db(store):prepare(
        "SELECT k FROM kv WHERE k LIKE ? AND k NOT LIKE 'apikey:meta:%'"
    )
    stmt:bind_values(prefix .. "%")
    local out = {}
    while stmt:step() == lsqlite3.ROW do
        local k = stmt:get_value(0)
        local id = k:sub(#prefix + 1)
        if id ~= "" and id ~= "index" then
            out[#out + 1] = id
        end
    end
    stmt:finalize()
    return out, nil
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
