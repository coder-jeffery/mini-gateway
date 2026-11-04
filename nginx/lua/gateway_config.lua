local _M = {}

local function env(name, default)
    local v = os.getenv(name)
    if v == nil or v == "" then
        return default
    end
    return v
end

function _M.storage_backend()
    local v = env("GATEWAY_STORAGE", "memory"):lower()
    if v == "redis" or v == "sqlite" or v == "memory" then
        return v
    end
    return "memory"
end

function _M.sqlite_path()
    return env("GATEWAY_SQLITE_PATH", "/var/lib/gateway/gateway.db")
end

function _M.redis_host()
    return env("GATEWAY_REDIS_HOST", "redis")
end

function _M.redis_port()
    return tonumber(env("GATEWAY_REDIS_PORT", "6379")) or 6379
end

function _M.bootstrap_defaults()
    return {
        api_key = env("DEFAULT_API_KEY", "mini-key"),
        api_key_limit = tonumber(env("DEFAULT_API_KEY_LIMIT", "1000")) or 1000,
        api_key_window = tonumber(env("DEFAULT_API_KEY_WINDOW", "60")) or 60,
        admin_token = env("DEFAULT_ADMIN_TOKEN", "mini-token"),
        admin_whitelist_ips = env("ADMIN_WHITELIST_IPS", "127.0.0.1,172.17.0.1,192.168.65.1"),
    }
end

return _M
