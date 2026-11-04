local store = require "store"

if ngx.worker.id() ~= 0 then
    return
end

local ok, err = store.bootstrap_if_needed()
if not ok then
    ngx.log(ngx.ERR, "gateway bootstrap failed: ", err)
end
