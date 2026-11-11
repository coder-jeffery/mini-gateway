local store_mod = require "store"

local _M = {}

function _M.check_storage()
    local name = store_mod.name()
    local backend = store_mod.backend()
    local handle, err = backend.new()
    if not handle then
        return false, err or "storage unavailable"
    end

    if name == "redis" then
        local red = handle._red
        local pong, perror = red:ping()
        backend.close(handle)
        if not pong or pong == ngx.null then
            return false, perror or "redis ping failed"
        end
        return true, nil
    end

    -- memory / sqlite: lightweight read
    local _, probe_err = backend.exists(handle, "gateway:health:probe")
    backend.close(handle)
    if probe_err then
        return false, tostring(probe_err)
    end
    return true, nil
end

return _M
