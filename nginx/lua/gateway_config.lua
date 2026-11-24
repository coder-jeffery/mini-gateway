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

function _M.admin_hmac_secret()
    return env("GATEWAY_ADMIN_SECRET", "admin-secret-2026")
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

local function split_csv(raw)
    local out = {}
    for part in string.gmatch(raw, "[^,%s]+") do
        out[#out + 1] = part
    end
    return out
end

function _M.upstream_scheme()
    local v = env("GATEWAY_UPSTREAM_SCHEME", "https"):lower()
    if v == "http" then
        return "http"
    end
    return "https"
end

-- Upstream request-target override.
-- nil when GATEWAY_UPSTREAM_PATH is unset or empty: passthrough.
-- rewrite_by_lua then leaves $gateway_upstream_path empty, so
-- `proxy_pass $scheme://gateway_backend$gateway_upstream_path` has no URI.
-- On that form OpenResty forwards the original request-target (path, query,
-- percent-encoding, repeated parameters) without decoding it again.
-- A non-empty value is the legacy override: it replaces the request-target.
-- Do not default this to /get; that pinned every demo request and is now opt-in.
function _M.upstream_proxy_path()
    local v = os.getenv("GATEWAY_UPSTREAM_PATH")
    if v == nil or v == "" then
        return nil
    end
    if v:sub(1, 1) ~= "/" then
        v = "/" .. v
    end
    return v
end

function _M.upstream_health_path()
    local v = env("GATEWAY_UPSTREAM_HEALTH_PATH", "/status/200")
    if v == "" or v:sub(1, 1) ~= "/" then
        return "/" .. v
    end
    return v
end

function _M.upstream_health_host()
    local v = env("GATEWAY_UPSTREAM_HOST", "")
    if v == "" then
        return nil
    end
    return v
end

function _M.upstream_health_interval()
    return tonumber(env("GATEWAY_UPSTREAM_HEALTH_INTERVAL", "15")) or 15
end

function _M.upstream_health_timeout_ms()
    return tonumber(env("GATEWAY_UPSTREAM_HEALTH_TIMEOUT_MS", "3000")) or 3000
end

function _M.upstream_health_fail_threshold()
    return tonumber(env("GATEWAY_UPSTREAM_HEALTH_FAIL_THRESHOLD", "3")) or 3
end

function _M.upstream_health_pass_threshold()
    return tonumber(env("GATEWAY_UPSTREAM_HEALTH_PASS_THRESHOLD", "2")) or 2
end

function _M.upstream_health_status_range()
    local raw = env("GATEWAY_UPSTREAM_HEALTH_OK_STATUS", "200-399")
    local lo, hi = raw:match("^(%d+)%-(%d+)$")
    if lo and hi then
        return tonumber(lo), tonumber(hi)
    end
    local one = tonumber(raw)
    if one then
        return one, one
    end
    return 200, 399
end

function _M.upstream_max_tries()
    local n = tonumber(env("GATEWAY_UPSTREAM_MAX_TRIES", "2")) or 2
    if n < 1 then
        return 1
    end
    if n > 5 then
        return 5
    end
    return n
end

function _M.upstream_timeouts()
    return {
        connect = tonumber(env("GATEWAY_UPSTREAM_CONNECT_TIMEOUT", "5")) or 5,
        send = tonumber(env("GATEWAY_UPSTREAM_SEND_TIMEOUT", "60")) or 60,
        read = tonumber(env("GATEWAY_UPSTREAM_READ_TIMEOUT", "60")) or 60,
    }
end

-- GATEWAY_UPSTREAM_PEERS: host:port[:weight], comma-separated
-- pass | reject when storage circuit is open or storage unreachable
function _M.storage_cb_policy()
    local v = env("GATEWAY_STORAGE_CB_POLICY", env("GATEWAY_CIRCUIT_BREAK_POLICY", "pass")):lower()
    if v == "reject" then
        return "reject"
    end
    return "pass"
end

function _M.storage_cb_window_sec()
    return tonumber(env("GATEWAY_STORAGE_CB_WINDOW_SEC", "10")) or 10
end

function _M.storage_cb_error_rate()
    local r = tonumber(env("GATEWAY_STORAGE_CB_ERROR_RATE", "0.5")) or 0.5
    if r < 0 then
        return 0
    end
    if r > 1 then
        return 1
    end
    return r
end

function _M.storage_cb_min_requests()
    return tonumber(env("GATEWAY_STORAGE_CB_MIN_REQUESTS", "5")) or 5
end

function _M.storage_cb_open_sec()
    return tonumber(env("GATEWAY_STORAGE_CB_OPEN_SEC", "30")) or 30
end

function _M.storage_cb_half_open_max()
    return tonumber(env("GATEWAY_STORAGE_CB_HALF_OPEN_MAX", "3")) or 3
end

function _M.storage_cb_half_open_success()
    return tonumber(env("GATEWAY_STORAGE_CB_HALF_OPEN_SUCCESS", "2")) or 2
end

function _M.storage_cb_degraded_default_limit()
    return tonumber(env("GATEWAY_STORAGE_CB_DEGRADED_LIMIT", "10")) or 10
end

function _M.storage_cb_degraded_default_window()
    return tonumber(env("GATEWAY_STORAGE_CB_DEGRADED_WINDOW", "60")) or 60
end

function _M.config_cache_enabled()
    return env("GATEWAY_CONFIG_CACHE", "1") == "1"
end

function _M.config_cache_ttl_sec()
    return tonumber(env("GATEWAY_CONFIG_CACHE_TTL_SEC", "30")) or 30
end

-- api_key | ip | api_key_ip
function _M.rate_limit_dimension()
    local v = env("GATEWAY_RL_DIMENSION", "api_key"):lower()
    if v == "ip" or v == "api_key_ip" then
        return v
    end
    return "api_key"
end

function _M.global_qps_limit()
    return tonumber(env("GATEWAY_GLOBAL_QPS_LIMIT", "0")) or 0
end

function _M.global_qps_window()
    return tonumber(env("GATEWAY_GLOBAL_QPS_WINDOW", "1")) or 1
end

function _M.business_hmac_mode()
    local v = env("GATEWAY_BUSINESS_HMAC_MODE", "off"):lower()
    if v == "required" or v == "optional" then
        return v
    end
    return "off"
end

function _M.business_hmac_secret()
    return env("GATEWAY_BUSINESS_HMAC_SECRET", "")
end

function _M.rate_warmup_enabled()
    return env("GATEWAY_RATE_WARMUP", "1") == "1"
end

function _M.leaky_bucket_rate()
    return tonumber(env("GATEWAY_LEAKY_BUCKET_RATE", "0")) or 0
end

function _M.leaky_bucket_capacity()
    return tonumber(env("GATEWAY_LEAKY_BUCKET_CAPACITY", "0")) or 0
end

function _M.leaky_bucket_ttl_sec()
    return tonumber(env("GATEWAY_LEAKY_BUCKET_TTL_SEC", "120")) or 120
end

function _M.admin_v1_default_role()
    local v = env("GATEWAY_ADMIN_V1_ROLE", "full_admin"):lower()
    if v == "operator" or v == "read_only" then
        return v
    end
    return "full_admin"
end

function _M.access_log_sample_rate()
    local r = tonumber(env("GATEWAY_ACCESS_LOG_SAMPLE_RATE", "1")) or 1
    if r < 0 then
        return 0
    end
    if r > 1 then
        return 1
    end
    return r
end

function _M.upstream_peers()
    local raw = env("GATEWAY_UPSTREAM_PEERS", "httpbin.org:443")
    local peers = {}
    for _, item in ipairs(split_csv(raw)) do
        local host, port, weight = item:match("^([^:]+):(%d+):(%d+)$")
        if not host then
            host, port = item:match("^([^:]+):(%d+)$")
            weight = 1
        end
        if host and port then
            peers[#peers + 1] = {
                host = host,
                port = tonumber(port),
                weight = tonumber(weight) or 1,
            }
        end
    end
    if #peers == 0 then
        peers[1] = { host = "httpbin.org", port = 443, weight = 1 }
    end
    return peers
end

return _M
