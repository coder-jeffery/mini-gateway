
local redis = require "resty.redis"
local _M = {}

function _M.new()
    local r = redis:new()
    r:set_timeouts(500, 500, 500)
    local ok, err = r:connect("redis", 6379)
    if not ok then
        return nil, "redis connect fail: " .. err
    end
    return r
end

-- 归还连接到连接池
function _M.close(red)
    -- 保持连接池，keepalive 60s，最多100个空闲连接
    local ok, err = red:set_keepalive(60000, 100)
    if not ok then
        red:close()
    end
end

return _M
