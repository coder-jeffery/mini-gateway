-- Async admin mutation audit (separate from access logs).
local store_mod = require "store"
local redact = require "log_redact"
local cjson = require "cjson"
local ngx = ngx

local _M = {}

local MUTATING = {
    upsert_apikey = true,
    del_apikey = true,
    whitelist_add = true,
    whitelist_del = true,
    admin_whitelist_add = true,
    admin_whitelist_del = true,
    token_issue = true,
    token_revoke = true,
    route_quota_set = true,
    route_quota_del = true,
    uri_block_add = true,
    uri_block_del = true,
    ua_block_add = true,
    ua_block_del = true,
    gray_rule_set = true,
    gray_rule_del = true,
    config_snapshot_save = true,
    config_snapshot_restore = true,
}

local SENSITIVE = {
    api_key = true,
    token = true,
    sign = true,
    nonce = true,
}

local function sanitize_req(req)
    local out = {}
    for k, v in pairs(req) do
        if k == "action" or k == "ts" or k == "sign" then
            -- omit signature noise from detail
        elseif SENSITIVE[k] then
            out[k] = redact.mask_credential(tostring(v))
        else
            out[k] = v
        end
    end
    return out
end

local function audit_timer(premature, line)
    if premature then
        return
    end
    local backend = store_mod.backend()
    if not backend.admin_audit_append then
        return
    end
    local handle, err = backend.new()
    if not handle then
        ngx.log(ngx.ERR, "admin audit storage connect failed: ", err)
        return
    end
    local ok, append_err = backend.admin_audit_append(handle, line)
    backend.close(handle)
    if not ok then
        ngx.log(ngx.ERR, "admin audit append err: ", append_err)
    end
end

function _M.is_mutating(action)
    return action ~= nil and MUTATING[action] == true
end

function _M.emit(actor, client_ip, action, req)
    if not _M.is_mutating(action) then
        return
    end
    local backend = store_mod.backend()
    if not backend.admin_audit_append then
        return
    end
    local obj = {
        ts = ngx.now(),
        request_id = ngx.ctx.request_id or "",
        ip = client_ip,
        action = action,
        actor = actor,
        storage = store_mod.name(),
        detail = sanitize_req(req or {}),
    }
    local line, err = cjson.encode(obj)
    if not line then
        ngx.log(ngx.ERR, "admin audit encode failed: ", err)
        return
    end
    local ok, timer_err = ngx.timer.at(0, audit_timer, line)
    if not ok then
        ngx.log(ngx.ERR, "admin audit timer failed: ", timer_err)
    end
end

return _M