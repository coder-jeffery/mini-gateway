
Intro:
1. **Phase choice:** use `access_by_lua` for auth and rate limits; older OpenResty cannot use Redis cosockets in rewrite; use content phase for response bodies.
2. Redis clients must use `set_keepalive` pooling or high concurrency opens too many connections.
3. Headers via `ngx.var.http_*` are lowercase: `X-Api-Key` → `ngx.var.http_x_api_key`.
4. Fixed windows can double-spike at boundaries; sliding windows use Redis sorted sets.
5. `wrk` uses one source IP and hits 429 quickly; rate limit by API key instead of IP for load tests.
6. Configure cosocket timeouts so a slow Redis does not block workers.

```bash
cd mini-gateway
./start.sh
```

Option 1:
```bash
curl -H "X-Api-Key: abc123" http://127.0.0.1:8080
```

Option 2:
```bash
docker exec -it gw-redis redis-cli SET apikey:abc123 1
curl -H "X-Api-Key: abc123" http://127.0.0.1:8080
```

Load test:
```bash
wrk -t2 -c20 -d10s -H "X-Api-Key: abc123" http://127.0.0.1:8080
```

Business IP whitelist:
```bash
docker exec -it gw-redis redis-cli
SADD whitelist:ip 127.0.0.1
```

```redis
# Add whitelist IP
SADD whitelist:ip 127.0.0.1
# Remove whitelist IP
SREM whitelist:ip 127.0.0.1
# List whitelist
SMEMBERS whitelist:ip
```

Dynamic quota: `HSET apikey:meta:abc123 limit 20 window 30`  # 20 requests per 30s for this key

```redis
# Mark api key valid
SET apikey:abc123 1

# Per-key quota: 20 requests / 30s
HSET apikey:meta:abc123 limit 20 window 30

# Another key: 5 requests / 60s
SET apikey:xyz789 1
HSET apikey:meta:xyz789 limit 5 window 60

# Whitelist IP
SADD whitelist:ip 127.0.0.1

# Inspect quota
HGETALL apikey:meta:abc123
```

View access logs:
```bash
docker exec -it gw-redis redis-cli
LRANGE gateway:access_log -10 -1
```


docker exec -it gw-redis redis-cli SMEMBERS admin:whitelist:ip

ADMIN_WHITELIST_IP=127.0.0.1 docker compose up -d

