local redact = require "log_redact"
local ngx = ngx

local _M = {}

local function scrub_args(...)
    local n = select("#", ...)
    local out = {}
    for i = 1, n do
        out[i] = redact.scrub_line(select(i, ...))
    end
    return table.concat(out)
end

function _M.err(...)
    ngx.log(ngx.ERR, scrub_args(...))
end

function _M.warn(...)
    ngx.log(ngx.WARN, scrub_args(...))
end

function _M.notice(...)
    ngx.log(ngx.NOTICE, scrub_args(...))
end

return _M