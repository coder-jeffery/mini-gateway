local cjson = require "cjson"

local _M = {}

local INDEX_KEY = "service:index"
local KEY_PREFIX = "service:"

local function resp_table(ok, extra)
    local t = { ok = ok }
    for k, v in pairs(extra or {}) do
        t[k] = v
    end
    return t
end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function parse_bool(v)
    if v == true or v == 1 or v == "1" then
        return true
    end
    if v == false or v == 0 or v == "0" then
        return false
    end
    return nil
end

local function normalize_path_prefix(path)
    if type(path) ~= "string" then
        return nil, "path_prefix must be a string"
    end
    path = trim(path)
    if path == "" or path:sub(1, 1) ~= "/" then
        return nil, "path_prefix must start with /"
    end
    if path ~= "/" then
        path = path:gsub("/+$", "")
    end
    return path, nil
end

local function validate_upstream(url)
    if type(url) ~= "string" or url == "" then
        return nil, "upstream_url required"
    end
    url = trim(url)
    if not url:match("^https?://") then
        return nil, "upstream_url must start with http:// or https://"
    end
    if url:match("%?") then
        return nil, "upstream_url must not contain query parameters"
    end
    return url, nil
end

local function validate_cors_origins(origins, credentials)
    if credentials and origins then
        for item in string.gmatch(origins, "[^,]+") do
            if trim(item) == "*" then
                return nil, "cors_allow_origins cannot contain * when credentials enabled"
            end
        end
    end
    return true, nil
end

local function new_id()
    return ngx.md5(ngx.now() .. ":" .. ngx.worker.pid() .. ":" .. math.random(1, 1e9))
end

local function load_raw(backend, handle, id)
    local raw, err = backend.get(handle, KEY_PREFIX .. id)
    if err then
        return nil, err
    end
    if raw == nil or raw == ngx.null or raw == "" then
        return nil, "not found"
    end
    local ok, decoded = pcall(cjson.decode, raw)
    if not ok or type(decoded) ~= "table" then
        return nil, "corrupt service record"
    end
    return decoded, nil
end

local function serialize_public(record)
    return {
        id = record.id,
        name = record.name,
        path_prefix = record.path_prefix,
        upstream_url = record.upstream_url,
        cors_enabled = record.cors_enabled == true,
        cors_allow_origins = record.cors_allow_origins or "",
        cors_allow_methods = record.cors_allow_methods or "",
        cors_allow_headers = record.cors_allow_headers or "",
        cors_expose_headers = record.cors_expose_headers or "",
        cors_max_age = tonumber(record.cors_max_age) or 0,
        cors_allow_credentials = record.cors_allow_credentials == true,
    }
end

function _M.public_router_record(record)
    return {
        id = record.id,
        name = record.name,
        path_prefix = record.path_prefix,
        upstream_url = record.upstream_url,
        cors_enabled = record.cors_enabled == true,
        cors_allow_origins = record.cors_allow_origins or "",
        cors_allow_methods = record.cors_allow_methods or "",
        cors_allow_headers = record.cors_allow_headers or "",
        cors_expose_headers = record.cors_expose_headers or "",
        cors_max_age = tonumber(record.cors_max_age) or 0,
        cors_allow_credentials = record.cors_allow_credentials == true,
    }
end

local function list_ids(backend, handle)
    local ids, err = backend.smembers(handle, INDEX_KEY)
    if err then
        return nil, err
    end
    if not ids then
        ids = {}
    end
    table.sort(ids, function(a, b)
        return tostring(a) < tostring(b)
    end)
    return ids, nil
end

local function check_unique(backend, handle, name, path_prefix, exclude_id)
    local ids, err = list_ids(backend, handle)
    if not ids then
        return nil, err
    end
    for _, id in ipairs(ids) do
        if exclude_id == nil or id ~= exclude_id then
            local rec, err_load = load_raw(backend, handle, id)
            if rec then
                if rec.name == name then
                    return false, "name conflict"
                end
                if rec.path_prefix == path_prefix then
                    return false, "path_prefix conflict"
                end
            elseif err_load ~= "not found" and err_load ~= "corrupt service record" then
                return nil, err_load
            end
        end
    end
    return true, nil
end

local function fields_from_req(req, require_all)
    local name = req.name
    local path_prefix, perr = normalize_path_prefix(req.path_prefix)
    if not path_prefix then
        return nil, perr
    end
    local upstream_url, uerr = validate_upstream(req.upstream_url)
    if not upstream_url then
        return nil, uerr
    end

    local cors_enabled = parse_bool(req.cors_enabled)
    if cors_enabled == nil then
        if require_all then
            return nil, "cors_enabled must be 0 or 1"
        end
        cors_enabled = false
    end

    local cors_allow_credentials = parse_bool(req.cors_allow_credentials)
    if cors_allow_credentials == nil then
        cors_allow_credentials = false
    end

    local cors_allow_origins = tostring(req.cors_allow_origins or "")
    local ok_o, oerr = validate_cors_origins(cors_allow_origins, cors_allow_credentials)
    if not ok_o then
        return nil, oerr
    end

    local cors_max_age = tonumber(req.cors_max_age)
    if cors_max_age == nil then
        cors_max_age = 0
    end
    if cors_max_age < 0 then
        cors_max_age = 0
    end
    cors_max_age = math.floor(cors_max_age)

    if require_all then
        if type(name) ~= "string" or trim(name) == "" then
            return nil, "name required"
        end
        name = trim(name)
    elseif name ~= nil then
        name = trim(tostring(name))
        if name == "" then
            return nil, "name required"
        end
    end

    return {
        name = name,
        path_prefix = path_prefix,
        upstream_url = upstream_url,
        cors_enabled = cors_enabled,
        cors_allow_origins = cors_allow_origins,
        cors_allow_methods = tostring(req.cors_allow_methods or "GET,POST,OPTIONS"),
        cors_allow_headers = tostring(req.cors_allow_headers or ""),
        cors_expose_headers = tostring(req.cors_expose_headers or ""),
        cors_max_age = cors_max_age,
        cors_allow_credentials = cors_allow_credentials,
    }, nil
end

function _M.clear_cache()
    local cache = ngx.shared.service_cache
    if cache then
        cache:flush_all()
    end
end

function _M.create_backend(backend, handle, req)
    local fields, ferr = fields_from_req(req, true)
    if not fields then
        return 400, resp_table(false, { msg = ferr })
    end

    local unique, uerr = check_unique(backend, handle, fields.name, fields.path_prefix, nil)
    if unique == nil then
        return 500, resp_table(false, { msg = "storage error: " .. tostring(uerr) })
    end
    if unique == false then
        return 409, resp_table(false, { msg = uerr })
    end

    local id = new_id()
    local record = {
        id = id,
        name = fields.name,
        path_prefix = fields.path_prefix,
        upstream_url = fields.upstream_url,
        cors_enabled = fields.cors_enabled,
        cors_allow_origins = fields.cors_allow_origins,
        cors_allow_methods = fields.cors_allow_methods,
        cors_allow_headers = fields.cors_allow_headers,
        cors_expose_headers = fields.cors_expose_headers,
        cors_max_age = fields.cors_max_age,
        cors_allow_credentials = fields.cors_allow_credentials,
    }

    local _, err_set = backend.set(handle, KEY_PREFIX .. id, cjson.encode(record))
    if err_set then
        return 500, resp_table(false, { msg = "storage error: " .. tostring(err_set) })
    end
    local _, err_sadd = backend.sadd(handle, INDEX_KEY, id)
    if err_sadd then
        backend.del(handle, KEY_PREFIX .. id)
        return 500, resp_table(false, { msg = "storage error: " .. tostring(err_sadd) })
    end

    return 201, resp_table(true, { service = serialize_public(record), msg = "service created" })
end

function _M.update_backend(backend, handle, req)
    local id = req.id
    if type(id) ~= "string" or trim(id) == "" then
        return 400, resp_table(false, { msg = "need id" })
    end
    id = trim(id)

    local existing, err_load = load_raw(backend, handle, id)
    if err_load == "not found" then
        return 404, resp_table(false, { msg = "service not found" })
    end
    if not existing then
        return 500, resp_table(false, { msg = "storage error: " .. tostring(err_load) })
    end

    local fields, ferr = fields_from_req(req, true)
    if not fields then
        return 400, resp_table(false, { msg = ferr })
    end

    local unique, uerr = check_unique(backend, handle, fields.name, fields.path_prefix, id)
    if unique == nil then
        return 500, resp_table(false, { msg = "storage error: " .. tostring(uerr) })
    end
    if unique == false then
        return 409, resp_table(false, { msg = uerr })
    end

    local record = {
        id = id,
        name = fields.name,
        path_prefix = fields.path_prefix,
        upstream_url = fields.upstream_url,
        cors_enabled = fields.cors_enabled,
        cors_allow_origins = fields.cors_allow_origins,
        cors_allow_methods = fields.cors_allow_methods,
        cors_allow_headers = fields.cors_allow_headers,
        cors_expose_headers = fields.cors_expose_headers,
        cors_max_age = fields.cors_max_age,
        cors_allow_credentials = fields.cors_allow_credentials,
    }

    local _, err_set = backend.set(handle, KEY_PREFIX .. id, cjson.encode(record))
    if err_set then
        return 500, resp_table(false, { msg = "storage error: " .. tostring(err_set) })
    end

    return 200, resp_table(true, { service = serialize_public(record), msg = "service updated" })
end

function _M.delete_backend(backend, handle, id)
    if type(id) ~= "string" or trim(id) == "" then
        return 400, resp_table(false, { msg = "need id" })
    end
    id = trim(id)

    local existing, err_load = load_raw(backend, handle, id)
    if err_load == "not found" then
        return 404, resp_table(false, { msg = "service not found" })
    end
    if not existing then
        return 500, resp_table(false, { msg = "storage error: " .. tostring(err_load) })
    end

    backend.del(handle, KEY_PREFIX .. id)
    backend.srem(handle, INDEX_KEY, id)
    return 200, resp_table(true, { msg = "service deleted" })
end

function _M.get_backend(backend, handle, id)
    if type(id) ~= "string" or trim(id) == "" then
        return 400, resp_table(false, { msg = "need id" })
    end
    id = trim(id)

    local record, err_load = load_raw(backend, handle, id)
    if err_load == "not found" then
        return 404, resp_table(false, { msg = "service not found" })
    end
    if not record then
        return 500, resp_table(false, { msg = "storage error: " .. tostring(err_load) })
    end
    return 200, resp_table(true, { service = serialize_public(record) })
end

function _M.list_backend(backend, handle)
    local ids, err = list_ids(backend, handle)
    if not ids then
        return 500, resp_table(false, { msg = "storage error: " .. tostring(err) })
    end

    local services = {}
    for _, sid in ipairs(ids) do
        local record, err_load = load_raw(backend, handle, sid)
        if record then
            services[#services + 1] = serialize_public(record)
        elseif err_load and err_load ~= "not found" then
            ngx.log(ngx.ERR, "skip corrupt service ", sid, ": ", err_load)
        end
    end

    table.sort(services, function(a, b)
        if a.path_prefix == b.path_prefix then
            return a.name < b.name
        end
        return a.path_prefix < b.path_prefix
    end)

    return 200, resp_table(true, { services = services })
end

return _M
