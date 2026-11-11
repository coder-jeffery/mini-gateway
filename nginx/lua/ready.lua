local respond = require "health_respond"
local probe = require "health_probe"
local store_mod = require "store"

respond.ensure_get_or_head()

local storage = store_mod.name()
local ok, err = probe.check_storage()
if ok then
    respond.json(200, { ok = true, status = "ready", storage = storage })
end

respond.json(503, {
    ok = false,
    status = "not_ready",
    storage = storage,
    msg = err or "storage unavailable",
})
