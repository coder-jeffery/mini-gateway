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

-- Scrub credentials from nginx error_log lines (M4).
function _M.scrub_line(message)
    if message == nil then
        return ""
    end
    local s = tostring(message)
    s = ngx.re.gsub(s, [[(?i)Bearer\s+[A-Za-z0-9_\-\.]+]], "Bearer ***", "jo")
    s = ngx.re.gsub(s, [[(?i)Authorization:\s*\S+]], "Authorization: ***", "jo")
    s = ngx.re.gsub(s, [[X%-Api%-Key:\s*\S+]], "X-Api-Key: ***", "jo")
    s = ngx.re.gsub(s, [[X%-Business%-Sign:\s*\S+]], "X-Business-Sign: ***", "jo")
    local key = ngx.var.http_x_api_key
    if key and key ~= "" and #key > 4 then
        local esc = ngx.re.gsub(key, [[([\.\+\-\*\?\[\]\^\$\(\)%%])]], "\\$1", "jo")
        if esc then
            s = ngx.re.gsub(s, esc, _M.mask_credential(key), "jo")
        end
    end
    return s
end

return _M