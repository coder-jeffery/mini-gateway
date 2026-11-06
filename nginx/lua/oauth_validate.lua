-- OAuth2 Resource Server: Bearer JWT validation (HS256 dev / RS256 via JWKS)

local cjson = require "cjson"
local hmac = require "resty.hmac"
local config = require "gateway_config"
local jwk_mod = require "oauth_jwk"

local _M = {}

local JWKS_CACHE_KEY = "jwks_json"
local DISCOVERY_CACHE_KEY = "oidc_discovery"

local function b64url_to_bin(s)
    s = s:gsub("-", "+"):gsub("_", "/")
    local pad = #s % 4
    if pad > 0 then
        s = s .. string.rep("=", 4 - pad)
    end
    return ngx.decode_base64(s)
end

local function constant_time_eq(a, b)
    if not a or not b or #a ~= #b then
        return false
    end
    local r = 0
    for i = 1, #a do
        r = bit.bor(r, bit.bxor(a:byte(i), b:byte(i)))
    end
    return r == 0
end

local function split_jwt(token)
    local h, p, s = token:match("^([^.]+)%.([^.]+)%.([^.]+)$")
    if not h then
        return nil, nil, nil, "malformed jwt"
    end
    return h, p, s, nil
end

local function parse_json_b64(part, label)
    local raw = b64url_to_bin(part)
    if not raw then
        return nil, "invalid " .. label
    end
    local ok, obj = pcall(cjson.decode, raw)
    if not ok or type(obj) ~= "table" then
        return nil, "invalid " .. label .. " json"
    end
    return obj, nil
end

local function http_get_json(url, cache_key, cache_ttl)
    local dict = ngx.shared.oauth_jwks_cache
    if dict and cache_key then
        local cached = dict:get(cache_key)
        if cached then
            local ok, obj = pcall(cjson.decode, cached)
            if ok and obj then
                return obj, nil
            end
        end
    end

    local http_ok, http = pcall(require, "resty.http")
    if not http_ok then
        return nil, "resty.http not available"
    end
    local httpc = http.new()
    httpc:set_timeout(5000)
    local res, err = httpc:request_uri(url, {
        method = "GET",
        headers = { ["Accept"] = "application/json" },
        ssl_verify = true,
    })
    if not res then
        return nil, "http request failed: " .. tostring(err)
    end
    if res.status ~= 200 then
        return nil, "http status " .. tostring(res.status)
    end
    local ok, obj = pcall(cjson.decode, res.body)
    if not ok or type(obj) ~= "table" then
        return nil, "invalid json from " .. url
    end
    if dict and cache_key and cache_ttl then
        dict:set(cache_key, res.body, cache_ttl)
    end
    return obj, nil
end

local function resolve_jwks_uri()
    local direct = config.oauth2_jwks_uri()
    if direct and direct ~= "" then
        return direct, nil
    end
    local issuer = config.oauth2_issuer()
    if not issuer or issuer == "" then
        return nil, "OAUTH2_JWKS_URI or OAUTH2_ISSUER required"
    end
    issuer = issuer:gsub("/+$", "")
    local discovery_url = issuer .. "/.well-known/openid-configuration"
    local doc, err = http_get_json(discovery_url, DISCOVERY_CACHE_KEY, config.oauth2_jwks_cache_ttl())
    if not doc then
        return nil, err
    end
    if not doc.jwks_uri or doc.jwks_uri == "" then
        return nil, "missing jwks_uri in discovery"
    end
    return doc.jwks_uri, nil
end

local function load_jwks()
    local uri, err = resolve_jwks_uri()
    if not uri then
        return nil, err
    end
    return http_get_json(uri, JWKS_CACHE_KEY, config.oauth2_jwks_cache_ttl())
end

local function find_jwk(jwks, kid)
    if not jwks or type(jwks.keys) ~= "table" then
        return nil, "invalid jwks"
    end
    if kid and kid ~= "" then
        for _, key in ipairs(jwks.keys) do
            if key.kid == kid and key.kty == "RSA" then
                return key, nil
            end
        end
        return nil, "jwk kid not found"
    end
    for _, key in ipairs(jwks.keys) do
        if key.kty == "RSA" and key.n and key.e then
            return key, nil
        end
    end
    return nil, "no usable rsa jwk"
end

local function verify_hs256(signing_input, signature_part, secret)
    local h = hmac:new(secret, hmac.ALGOS.SHA256)
    if not h then
        return false, "hmac init failed"
    end
    if not h:update(signing_input) then
        return false, "hmac update failed"
    end
    local digest = h:final(nil, false)
    if not digest then
        return false, "hmac final failed"
    end
    local sig_bin = b64url_to_bin(signature_part)
    if not sig_bin then
        return false, "invalid signature encoding"
    end
    if not constant_time_eq(digest, sig_bin) then
        return false, "invalid token signature"
    end
    return true, nil
end

local function verify_rs256(signing_input, signature_part, pem)
    local rsa_ok, rsa = pcall(require, "resty.rsa")
    if not rsa_ok then
        return false, "resty.rsa not available (install lua-resty-rsa)"
    end
    local pub, err = rsa:new({ public_key = pem, algorithm = "SHA256" })
    if not pub then
        return false, "rsa init failed: " .. tostring(err)
    end
    local sig_bin = b64url_to_bin(signature_part)
    if not sig_bin then
        return false, "invalid signature encoding"
    end
    local sig_b64 = ngx.encode_base64(sig_bin)
    local ok, verify_err = pub:verify(signing_input, sig_b64)
    if not ok then
        return false, verify_err or "invalid token signature"
    end
    return true, nil
end

local function claim_audience_ok(aud_claim, expected)
    if not expected or expected == "" then
        return true
    end
    local expected_list = {}
    for part in expected:gmatch("[^,%s]+") do
        expected_list[part] = true
    end
    if type(aud_claim) == "string" then
        return expected_list[aud_claim] == true
    end
    if type(aud_claim) == "table" then
        for _, v in ipairs(aud_claim) do
            if expected_list[v] then
                return true
            end
        end
    end
    return false
end

local function claim_scope_ok(scope_claim, required)
    if not required or required == "" then
        return true
    end
    local scopes = {}
    if type(scope_claim) == "string" then
        for s in scope_claim:gmatch("%S+") do
            scopes[s] = true
        end
    elseif type(scope_claim) == "table" then
        for _, s in ipairs(scope_claim) do
            scopes[s] = true
        end
    end
    for req in required:gmatch("[^,%s]+") do
        if not scopes[req] then
            return false
        end
    end
    return true
end

local function validate_claims(payload)
    local now = ngx.time()
    local skew = config.oauth2_clock_skew_sec()

    local iss = config.oauth2_issuer()
    if iss and iss ~= "" then
        if payload.iss ~= iss then
            return nil, "invalid issuer"
        end
    end

    if not claim_audience_ok(payload.aud, config.oauth2_audience()) then
        return nil, "invalid audience"
    end

    if payload.exp then
        if now - skew > tonumber(payload.exp) then
            return nil, "token expired"
        end
    else
        return nil, "missing exp claim"
    end

    if payload.nbf then
        if now + skew < tonumber(payload.nbf) then
            return nil, "token not yet valid"
        end
    end

    if not claim_scope_ok(payload.scope or payload.scp, config.oauth2_required_scope()) then
        return nil, "insufficient scope"
    end

    return payload, nil
end

function _M.extract_bearer()
    local auth_header = ngx.var.http_authorization
    if not auth_header or auth_header == "" then
        return nil
    end
    local m = ngx.re.match(auth_header, "^Bearer\\s+(.+)$", "jo")
    if not m then
        return nil
    end
    local token = m[1]
    if token == "" then
        return nil
    end
    return token
end

function _M.validate(token)
    if not token or token == "" then
        return nil, "missing bearer token", 401
    end

    local h_b64, p_b64, s_b64, err = split_jwt(token)
    if err then
        return nil, err, 401
    end

    local header, herr = parse_json_b64(h_b64, "header")
    if herr then
        return nil, herr, 401
    end
    local payload, perr = parse_json_b64(p_b64, "payload")
    if perr then
        return nil, perr, 401
    end

    local alg = header.alg
    if not alg then
        return nil, "missing alg", 401
    end

    local signing_input = h_b64 .. "." .. p_b64
    if alg == "HS256" then
        local secret = config.oauth2_jwt_secret()
        if not secret or secret == "" then
            return nil, "HS256 not configured", 503
        end
        local ok, verr = verify_hs256(signing_input, s_b64, secret)
        if not ok then
            return nil, verr or "invalid token signature", 401
        end
    elseif alg == "RS256" then
        local jwks, jerr = load_jwks()
        if not jwks then
            ngx.log(ngx.ERR, "jwks load: ", jerr)
            return nil, "jwks unavailable", 503
        end
        local jwk, ferr = find_jwk(jwks, header.kid)
        if not jwk then
            return nil, ferr or "jwk not found", 401
        end
        local pem, perr2 = jwk_mod.rsa_public_pem(jwk.n, jwk.e)
        if not pem then
            return nil, perr2 or "jwk parse failed", 401
        end
        local ok, verr = verify_rs256(signing_input, s_b64, pem)
        if not ok then
            return nil, verr or "invalid token signature", 401
        end
    else
        return nil, "unsupported alg: " .. tostring(alg), 401
    end

    local claims, cerr = validate_claims(payload)
    if not claims then
        return nil, cerr or "invalid claims", 401
    end

    return claims, nil, nil
end

function _M.rate_limit_identity(claims)
    local mode = config.oauth2_rate_limit_key()
    if mode == "client_id" then
        local cid = claims.client_id or claims.azp or claims.aud
        if type(cid) == "table" then
            cid = cid[1]
        end
        if cid and cid ~= "" then
            return "client:" .. tostring(cid)
        end
    end
    local sub = claims.sub
    if sub and sub ~= "" then
        return "sub:" .. tostring(sub)
    end
    return "sub:unknown"
end

return _M
