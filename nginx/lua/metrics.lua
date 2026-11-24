local metrics = require "gateway_metrics"
local storage_cb = require "storage_circuit"
local ngx = ngx

storage_cb.sync_metrics()

ngx.header["Content-Type"] = "text/plain; version=0.0.4; charset=utf-8"
ngx.say(metrics.prometheus_lines())
return ngx.exit(ngx.HTTP_OK)