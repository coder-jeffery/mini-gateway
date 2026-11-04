
local redis = require "resty.redis"
local config = require "gateway_config"
local _M = {}

function _M.new()
    local r = redis:new()
    r:set_timeouts(500, 500, 500)
    local ok, err = r:connect(config.redis_host(), config.redis_port())
    if not ok then
        return nil, "redis connect fail: " .. err
    end
    return r
end

-- Return connection to the pool
function _M.close(red)
    -- keepalive 60s, up to 100 idle connections
    local ok, err = red:set_keepalive(60000, 100)
    if not ok then
        red:close()
    end
end

return _M
