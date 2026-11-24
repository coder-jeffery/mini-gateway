-- P3-3: admin RBAC (v0 Bearer token role + v1 HMAC principal role).
local config = require "gateway_config"
local ngx = ngx

local _M = {}

local ROLE_PERMISSIONS = {
    full_admin = {
        upsert_apikey = true,
        del_apikey = true,
        whitelist_add = true,
        whitelist_del = true,
        admin_whitelist_add = true,
        admin_whitelist_del = true,
        route_quota_set = true,
        route_quota_del = true,
        uri_block_add = true,
        uri_block_del = true,
        ua_block_add = true,
        ua_block_del = true,
        gray_rule_set = true,
        gray_rule_del = true,
        rewrite_rule_set = true,
        rewrite_rule_del = true,
        config_snapshot_save = true,
        config_snapshot_restore = true,
        admin_role_set = true,
        token_issue = true,
        token_revoke = true,
    },
    operator = {
        upsert_apikey = true,
        whitelist_add = true,
        whitelist_del = true,
        route_quota_set = true,
        uri_block_add = true,
        ua_block_add = true,
        gray_rule_set = true,
        rewrite_rule_set = true,
        config_snapshot_save = true,
    },
    read_only = {},
}

local function normalize_role(role)
    if role == "operator" or role == "read_only" or role == "full_admin" then
        return role
    end
    return "full_admin"
end

function _M.v1_role(backend, handle)
    local raw, err = backend.get(handle, "admin:rbac:v1_role")
    if err then
        return config.admin_v1_default_role(), err
    end
    if raw and raw ~= ngx.null and raw ~= "" then
        return normalize_role(tostring(raw)), nil
    end
    return normalize_role(config.admin_v1_default_role()), nil
end

function _M.bearer_role(token_data)
    if type(token_data) ~= "table" then
        return "full_admin"
    end
    return normalize_role(token_data.role or "full_admin")
end

function _M.allows(role, action)
    role = normalize_role(role)
    local perms = ROLE_PERMISSIONS[role]
    if not perms then
        return false
    end
    if action == "hmac_test" or action == "apikey_list" or action == "get_apikey"
        or action == "whitelist_list" or action == "admin_whitelist_list"
        or action == "audit_list" or action == "token_list" then
        return true
    end
    return perms[action] == true
end

function _M.denied_msg(action)
    return "forbidden: role cannot perform action " .. tostring(action)
end

return _M