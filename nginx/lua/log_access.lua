local redis_util = require "redis_util"
local ngx = ngx

local function log_timer(premature, log_data)
    if premature then
        return
    end
    local red, err = redis_util.new()
    if not red then
        ngx.log(ngx.ERR, "log redis connect failed: ", err)
        return
    end
    -- RPUSH 追加日志到 list
    local ok, err = red:rpush("gateway:access_log", log_data)
    redis_util.close(red)
    if not ok then
        ngx.log(ngx.ERR, "rpush access log err: ", err)
    end
end

-- 组装日志JSON字符串
local now = ngx.now()
local log_obj = {
    request_id = ngx.ctx.request_id,
    ts = now,
    ip = ngx.var.remote_addr,
    api_key = ngx.var.http_x_api_key or "",
    uri = ngx.var.uri,
    status = ngx.status,
    is_whitelist = ngx.header["X-RateLimit-Whitelist"] == "true",
    circuit_break = ngx.header["X-Redis-Circuit-Break"] == "true",
    limit_limit = ngx.header["X-RateLimit-Limit"],
    limit_remaining = ngx.header["X-RateLimit-Remaining"],
}
local cjson = require "cjson"
local log_str, err = cjson.encode(log_obj)
if not log_str then
    ngx.log(ngx.ERR, "encode log failed: ", err)
    return
end

-- 投递异步timer，0=尽快调度
local ok, err = ngx.timer.at(0, log_timer, log_str)
if not ok then
    ngx.log(ngx.ERR, "create log timer failed: ", err)
end

-- docker exec -it gw-redis redis-cli