local ngx = ngx
local bit = bit

local function fallback_id()
    return string.format(
        "req-%x-%x-%x",
        math.floor(ngx.now() * 1000000),
        ngx.worker.pid(),
        math.random(0, 0xffffff)
    )
end

-- OpenResty 无 resty.uuid；用 lua-resty-core 自带的 random + string 生成 UUID v4
local function uuid_v4()
    local ok_random, random = pcall(require, "resty.random")
    local ok_str, str = pcall(require, "resty.string")
    if not ok_random or not ok_str then
        return fallback_id()
    end

    local bytes, err = random.bytes(16, true)
    if not bytes then
        ngx.log(ngx.WARN, "request_id random bytes failed: ", err)
        return fallback_id()
    end

    local ba = { string.byte(bytes, 1, 16) }
    ba[7] = bit.bor(bit.band(ba[7], 0x0f), 0x40)
    ba[9] = bit.bor(bit.band(ba[9], 0x3f), 0x80)
    bytes = string.char(table.unpack(ba))

    local hex = str.to_hex(bytes)
    return string.format(
        "%s-%s-%s-%s-%s",
        hex:sub(1, 8),
        hex:sub(9, 12),
        hex:sub(13, 16),
        hex:sub(17, 20),
        hex:sub(21, 32)
    )
end

local req_id = uuid_v4()
ngx.ctx.request_id = req_id
ngx.var.ctx_request_id = req_id
ngx.header["X-Request-Id"] = req_id
