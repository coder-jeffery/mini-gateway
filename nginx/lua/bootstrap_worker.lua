local store = require "store"
local probe = require "upstream_probe"
local storage_circuit = require "storage_circuit"

storage_circuit.init_worker()

if ngx.worker.id() == 0 then
    local ok, err = store.bootstrap_if_needed()
    if not ok then
        ngx.log(ngx.ERR, "gateway bootstrap failed: ", err)
    end
end

local pok, perr = probe.start()
if not pok then
    ngx.log(ngx.ERR, "upstream probe start failed: ", perr)
end
