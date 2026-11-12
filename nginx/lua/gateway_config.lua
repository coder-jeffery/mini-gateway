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

-- api_key | bearer | both (default api_key keeps existing behavior)
function _M.auth_mode()
    local v = env("GATEWAY_AUTH_MODE", "api_key"):lower()
    if v == "bearer" or v == "both" then
        return v
    end
    return "api_key"
end

function _M.oauth2_issuer()
    return env("OAUTH2_ISSUER", "")
end

function _M.oauth2_jwks_uri()
    return env("OAUTH2_JWKS_URI", "")
end

function _M.oauth2_audience()
    return env("OAUTH2_AUDIENCE", "")
end

function _M.oauth2_required_scope()
    return env("OAUTH2_REQUIRED_SCOPE", "")
end

function _M.oauth2_jwt_secret()
    return env("OAUTH2_JWT_SECRET", "")
end

function _M.oauth2_clock_skew_sec()
    return tonumber(env("OAUTH2_CLOCK_SKEW_SEC", "60")) or 60
end

function _M.oauth2_jwks_cache_ttl()
    return tonumber(env("OAUTH2_JWKS_CACHE_TTL", "300")) or 300
end

-- sub | client_id
function _M.oauth2_rate_limit_key()
    local v = env("OAUTH2_RATE_LIMIT_KEY", "sub"):lower()
    if v == "client_id" then
        return "client_id"
    end
    return "sub"
end

function _M.oauth2_default_limit()
    return tonumber(env("OAUTH2_DEFAULT_LIMIT", env("DEFAULT_API_KEY_LIMIT", "1000"))) or 1000
end

function _M.oauth2_default_window()
    return tonumber(env("OAUTH2_DEFAULT_WINDOW", env("DEFAULT_API_KEY_WINDOW", "60"))) or 60
end

function _M.cors_enabled()
    return env("GATEWAY_CORS_ENABLED", "0") == "1"
end

function _M.cors_allow_origins()
    return env("GATEWAY_CORS_ALLOW_ORIGINS", "")
end

function _M.cors_allow_methods()
    return env("GATEWAY_CORS_ALLOW_METHODS", "GET,POST,PUT,PATCH,DELETE,OPTIONS")
end

function _M.cors_allow_headers()
    return env(
        "GATEWAY_CORS_ALLOW_HEADERS",
        "Content-Type,Authorization,X-Api-Key,X-Request-Id"
    )
end

function _M.cors_expose_headers()
    return env(
        "GATEWAY_CORS_EXPOSE_HEADERS",
        "X-Request-Id,X-RateLimit-Limit,X-RateLimit-Remaining,X-RateLimit-Reset,Retry-After"
    )
end

function _M.cors_max_age()
    local value = tonumber(env("GATEWAY_CORS_MAX_AGE", "600")) or 600
    return math.max(0, math.floor(value))
end

function _M.cors_allow_credentials()
    return env("GATEWAY_CORS_ALLOW_CREDENTIALS", "0") == "1"
end

return _M
