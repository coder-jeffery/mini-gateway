
- IP whitelist: Redis set `whitelist:ip`; matches skip rate limiting
- Dynamic quota: per-apikey limit/window in Redis, not hard-coded in Lua
- Rate limit headers: `X-RateLimit-Limit` / `X-RateLimit-Remaining` / `X-RateLimit-Reset`
- Circuit breaker: on Redis failure, pass or reject all traffic
