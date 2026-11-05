local _M = {}

local INDEX_KEY = "apikey:index"
local KEY_PREFIX = "apikey:"
local META_PREFIX = "apikey:meta:"

function _M.clamp_page(page, page_size)
    page = tonumber(page) or 1
    page_size = tonumber(page_size) or 20
    if page < 1 then
        page = 1
    end
    if page_size < 1 then
        page_size = 20
    end
    if page_size > 100 then
        page_size = 100
    end
    return page, page_size
end

local function sort_strings(list)
    table.sort(list, function(a, b)
        return tostring(a) < tostring(b)
    end)
end

local function slice_page(list, page, page_size)
    local total = #list
    local start_idx = (page - 1) * page_size + 1
    local end_idx = math.min(start_idx + page_size - 1, total)
    local items = {}
    if start_idx <= total then
        for i = start_idx, end_idx do
            items[#items + 1] = list[i]
        end
    end
    return items, total
end

function _M.index_add_redis(red, api_key)
    red:sadd(INDEX_KEY, api_key)
end

function _M.index_del_redis(red, api_key)
    red:srem(INDEX_KEY, api_key)
end

function _M.scan_ids_redis(red)
    local ids = {}
    local seen = {}
    local cursor = "0"
    repeat
        local res, err = red:scan(cursor, "MATCH", KEY_PREFIX .. "*", "COUNT", 200)
        if not res then
            return nil, err
        end
        cursor = res[1]
        for _, key in ipairs(res[2]) do
            if key:sub(1, #META_PREFIX) ~= META_PREFIX then
                local id = key:sub(#KEY_PREFIX + 1)
                if id ~= "" and id ~= "index" and not seen[id] then
                    seen[id] = true
                    ids[#ids + 1] = id
                end
            end
        end
    until cursor == "0"
    sort_strings(ids)
    return ids, nil
end

function _M.list_ids_redis(red)
    local ids, err = red:smembers(INDEX_KEY)
    if err then
        return nil, err
    end
    if not ids or #ids == 0 then
        ids, err = _M.scan_ids_redis(red)
        if not ids then
            return nil, err
        end
        for _, id in ipairs(ids) do
            red:sadd(INDEX_KEY, id)
        end
        return ids, nil
    end
    sort_strings(ids)
    return ids, nil
end

function _M.meta_redis(red, api_key)
    local limit, err = red:hget("apikey:meta:" .. api_key, "limit")
    if err then
        return nil, err
    end
    local window, err2 = red:hget("apikey:meta:" .. api_key, "window")
    if err2 then
        return nil, err2
    end
    return {
        api_key = api_key,
        limit = tonumber(limit) or 0,
        window = tonumber(window) or 0,
    }, nil
end

function _M.list_redis(red, page, page_size)
    page, page_size = _M.clamp_page(page, page_size)
    local ids, err = _M.list_ids_redis(red)
    if not ids then
        return nil, err
    end
    local page_ids, total = slice_page(ids, page, page_size)
    local items = {}
    for _, id in ipairs(page_ids) do
        local exists, err_e = red:exists(KEY_PREFIX .. id)
        if err_e then
            return nil, err_e
        end
        if exists == 1 then
            local meta, err_m = _M.meta_redis(red, id)
            if err_m then
                return nil, err_m
            end
            items[#items + 1] = meta
        else
            red:srem(INDEX_KEY, id)
        end
    end
    return {
        items = items,
        total = total,
        page = page,
        page_size = page_size,
        total_pages = total > 0 and math.ceil(total / page_size) or 0,
    }, nil
end

function _M.get_redis(red, api_key)
    if not api_key or api_key == "" then
        return nil, "need api_key"
    end
    local exists, err = red:exists(KEY_PREFIX .. api_key)
    if err then
        return nil, err
    end
    if exists ~= 1 then
        return nil, "not found"
    end
    return _M.meta_redis(red, api_key)
end

-- Store backend (admin_api.lua)
function _M.index_add_backend(backend, handle, api_key)
    backend.sadd(handle, INDEX_KEY, api_key)
end

function _M.index_del_backend(backend, handle, api_key)
    backend.srem(handle, INDEX_KEY, api_key)
end

function _M.list_ids_backend(backend, handle)
    local ids, err = backend.smembers(handle, INDEX_KEY)
    if err then
        return nil, err
    end
    if not ids or #ids == 0 then
        if backend.list_kv_prefix then
            ids, err = backend.list_kv_prefix(handle, KEY_PREFIX)
            if not ids then
                return nil, err
            end
            for _, id in ipairs(ids) do
                backend.sadd(handle, INDEX_KEY, id)
            end
            sort_strings(ids)
            return ids, nil
        end
    end
    sort_strings(ids or {})
    return ids or {}, nil
end

function _M.meta_backend(backend, handle, api_key)
    local limit_w, err = backend.hmget(handle, META_PREFIX .. api_key, "limit", "window")
    if err then
        return nil, err
    end
    return {
        api_key = api_key,
        limit = tonumber(limit_w[1]) or 0,
        window = tonumber(limit_w[2]) or 0,
    }, nil
end

function _M.list_backend(backend, handle, page, page_size)
    page, page_size = _M.clamp_page(page, page_size)
    local ids, err = _M.list_ids_backend(backend, handle)
    if not ids then
        return nil, err
    end
    local page_ids, total = slice_page(ids, page, page_size)
    local items = {}
    for _, id in ipairs(page_ids) do
        local exists, err_e = backend.exists(handle, KEY_PREFIX .. id)
        if err_e then
            return nil, err_e
        end
        if exists == 1 then
            local meta, err_m = _M.meta_backend(backend, handle, id)
            if err_m then
                return nil, err_m
            end
            items[#items + 1] = meta
        else
            backend.srem(handle, INDEX_KEY, id)
        end
    end
    return {
        items = items,
        total = total,
        page = page,
        page_size = page_size,
        total_pages = total > 0 and math.ceil(total / page_size) or 0,
    }, nil
end

function _M.get_backend(backend, handle, api_key)
    if not api_key or api_key == "" then
        return nil, "need api_key"
    end
    local exists, err = backend.exists(handle, KEY_PREFIX .. api_key)
    if err then
        return nil, err
    end
    if exists ~= 1 then
        return nil, "not found"
    end
    return _M.meta_backend(backend, handle, api_key)
end

return _M
