
# function: 

- IP whitelist: Redis set `whitelist:ip`; matches skip rate limiting
- Dynamic quota: per-apikey limit/window in Redis, not hard-coded in Lua
- Rate limit headers: `X-RateLimit-Limit` / `X-RateLimit-Remaining` / `X-RateLimit-Reset`
- Circuit breaker: error-rate window on storage failures; half-open probes; pass/reject via `GATEWAY_STORAGE_CB_POLICY`
- Metrics: `GET /metrics` (Prometheus counters/gauges)
