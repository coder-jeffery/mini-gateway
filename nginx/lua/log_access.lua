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
    -- Append log entry to Redis list
    local ok, err = red:rpush("gateway:access_log", log_data)
    redis_util.close(red)
    if not ok then
        ngx.log(ngx.ERR, "rpush access log err: ", err)
    end
end

-- Build JSON log payload
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

-- Async timer; 0 = run as soon as possible
local ok, err = ngx.timer.at(0, log_timer, log_str)
if not ok then
    ngx.log(ngx.ERR, "create log timer failed: ", err)
end

-- docker exec -it gw-redis redis-cli LRANGE gateway:access_log 0 -1