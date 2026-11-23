-- Irreversible log identifiers. Never return a prefix or copy of the secret.

local sha256 = require "resty.sha256"
local str = require "resty.string"

local _M = {}

function _M.fingerprint(secret)
    if type(secret) ~= "string" or secret == "" then
        return ""
    end
    local digest = sha256:new()
    if not digest then
        return ""
    end
    digest:update(secret)
    local hex = str.to_hex(digest:final())
    return "fp_" .. hex:sub(1, 16)
end

function _M.subject(auth_type, subject, api_key)
    if auth_type == "api_key" then
        local secret = api_key
        if secret == nil or secret == "" then
            secret = subject or ""
        end
        return _M.fingerprint(secret)
    end
    if type(subject) ~= "string" or subject == "" then
        return ""
    end
    if subject:find("Bearer ", 1, true) or subject:match("^[%w%-_]+%.[%w%-_]+%.[%w%-_]+$") then
        return _M.fingerprint(subject)
    end
    return subject
end

return _M
