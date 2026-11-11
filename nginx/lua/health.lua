local respond = require "health_respond"

respond.ensure_get_or_head()
respond.json(200, { ok = true, status = "healthy" })
