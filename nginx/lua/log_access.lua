local store_mod = require "store"
local cjson = require "cjson"
local ngx = ngx

local function log_timer(premature, log_data)
    if premature then
        return
    end
    local backend = store_mod.backend()
    local handle, err = backend.new()
    if not handle then
        ngx.log(ngx.ERR, "log storage connect failed: ", err)
        return
    end
    local ok, err = backend.access_log_append(handle, log_data)
    backend.close(handle)
    if not ok then
        ngx.log(ngx.ERR, "access log append err: ", err)
    end
end

local now = ngx.now()
local log_obj = {
    request_id = ngx.ctx.request_id,
    ts = now,
    ip = ngx.var.remote_addr,
    api_key = ngx.var.http_x_api_key or "",
    auth_type = ngx.ctx.auth_type or "",
    auth_subject = ngx.ctx.auth_subject or "",
    uri = ngx.var.uri,
    status = ngx.status,
    storage = store_mod.name(),
    is_whitelist = ngx.header["X-RateLimit-Whitelist"] == "true",
    circuit_break = ngx.header["X-Redis-Circuit-Break"] == "true",
    limit_limit = ngx.header["X-RateLimit-Limit"],
    limit_remaining = ngx.header["X-RateLimit-Remaining"],
}
local log_str, err = cjson.encode(log_obj)
if not log_str then
    ngx.log(ngx.ERR, "encode log failed: ", err)
    return
end

local ok, err = ngx.timer.at(0, log_timer, log_str)
if not ok then
    ngx.log(ngx.ERR, "create log timer failed: ", err)
end
