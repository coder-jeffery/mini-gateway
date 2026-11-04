Why use `log_by_lua` + `ngx.timer.at` for access logs?

1. `access_by_lua` runs before the upstream; `log_by_lua` runs after the response is sent—good for audit and metrics.
2. Sync Redis in `log_by_lua` would add latency; `ngx.timer.at(0)` runs off the request coroutine with no user-facing delay.
3. Pitfall: timer callbacks cannot rely on `ngx.ctx` after the request ends—serialize data before scheduling the timer.

Improvements:

1. Add `request_id` in `rewrite_by_lua`, store in `ngx.var`, forward to upstream and logs.
2. Use Redis Stream (`XADD`) instead of a list for consumer groups and acks.
3. Set `lua_max_pending_timers` to cap timer growth under load.
4. Sample logs at high QPS to reduce Redis pressure.
