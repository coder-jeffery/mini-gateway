local cjson = require "cjson"

local _M = {}

function _M.ensure_get_or_head()
    local method = ngx.req.get_method()
    if method == "GET" or method == "HEAD" then
        return true
    end
    ngx.status = 405
    ngx.header["Allow"] = "GET, HEAD"
    ngx.header["Content-Type"] = "application/json"
    ngx.say(cjson.encode({ ok = false, msg = "method not allowed" }))
    return ngx.exit(405)
end

function _M.json(status, data)
    ngx.status = status
    ngx.header["Content-Type"] = "application/json"
    ngx.header["Cache-Control"] = "no-store"
    if ngx.req.get_method() == "HEAD" then
        return ngx.exit(status)
    end
    ngx.say(cjson.encode(data))
    return ngx.exit(status)
end

return _M
