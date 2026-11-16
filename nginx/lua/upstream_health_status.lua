local health = require "upstream_health"
local cjson = require "cjson"
local config = require "gateway_config"

local ngx = ngx

ngx.header["Content-Type"] = "application/json"
ngx.status = 200
ngx.say(cjson.encode({
    ok = true,
    scheme = config.upstream_scheme(),
    proxy_path = config.upstream_proxy_path(),
    health_path = config.upstream_health_path(),
    peers = health.snapshot(),
}))