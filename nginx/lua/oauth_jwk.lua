-- RSA JWK (n, e) → PEM public key for RS256 verify

local _M = {}

local function b64url_to_bin(s)
    if not s or s == "" then
        return nil, "empty base64url"
    end
    s = s:gsub("-", "+"):gsub("_", "/")
    local pad = #s % 4
    if pad > 0 then
        s = s .. string.rep("=", 4 - pad)
    end
    return ngx.decode_base64(s)
end

local function der_len(n)
    if n < 128 then
        return string.char(n)
    end
    local bytes = {}
    while n > 0 do
        table.insert(bytes, 1, string.char(n % 256))
        n = math.floor(n / 256)
    end
    local raw = table.concat(bytes)
    return string.char(0x80 + #raw) .. raw
end

local function der_integer(bin)
    if bin:byte(1) >= 0x80 then
        bin = string.char(0x00) .. bin
    end
    return string.char(0x02) .. der_len(#bin) .. bin
end

function _M.rsa_public_pem(n_b64url, e_b64url)
    local n_bin, err = b64url_to_bin(n_b64url)
    if not n_bin then
        return nil, err
    end
    local e_bin, err2 = b64url_to_bin(e_b64url)
    if not e_bin then
        return nil, err2
    end

    local seq = der_integer(n_bin) .. der_integer(e_bin)
    seq = string.char(0x30) .. der_len(#seq) .. seq

    local bitstr = string.char(0x00) .. seq
    bitstr = string.char(0x03) .. der_len(#bitstr) .. bitstr

    local oid = string.char(0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01)
    local null = string.char(0x05, 0x00)
    local alg_id = string.char(0x30) .. der_len(#oid + #null) .. oid .. null

    local spki = string.char(0x30) .. der_len(#alg_id + #bitstr) .. alg_id .. bitstr
    local b64 = ngx.encode_base64(spki)
    b64 = b64:gsub("\n", "")

    local pem = "-----BEGIN PUBLIC KEY-----\n"
    for i = 1, #b64, 64 do
        pem = pem .. b64:sub(i, i + 63) .. "\n"
    end
    pem = pem .. "-----END PUBLIC KEY-----\n"
    return pem
end

return _M
