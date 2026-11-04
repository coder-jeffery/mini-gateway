local config = require "gateway_config"

local backends = {
    memory = require "store.backends.memory",
    redis = require "store.backends.redis",
    sqlite = require "store.backends.sqlite",
}

local _M = {}

function _M.name()
    return config.storage_backend()
end

function _M.backend()
    return backends[config.storage_backend()]
end

function _M.open()
    return _M.backend().new()
end

function _M.close(handle)
    return _M.backend().close(handle)
end

function _M.bootstrap_if_needed()
    local name = config.storage_backend()
    if name == "redis" then
        return true, nil
    end
    local lock = ngx.shared.gateway_store
    if not lock then
        return false, "shared dict gateway_store missing"
    end
    if not lock:add("_bootstrapped", 1, 0) then
        return true, nil
    end
    local b = backends[name]
    local handle, err = b.new()
    if not handle then
        return false, err
    end
    local ok, err2 = b.bootstrap(handle, config.bootstrap_defaults())
    b.close(handle)
    if not ok then
        return false, err2
    end
    return true, nil
end

return _M
