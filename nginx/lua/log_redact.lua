-- Redact credentials for access/audit logs (must stay in sync with test/test_log_redact.py).
local _M = {}

function _M.mask_credential(value)
    if value == nil or value == "" then
        return ""
    end
    local s = tostring(value)
    local n = #s
    if n <= 4 then
        return "***"
    end
    if n <= 8 then
        return s:sub(1, 2) .. "***"
    end
    return s:sub(1, 4) .. "***" .. s:sub(-4)
end

return _M