
Intro:
1. **Phase choice:** use `access_by_lua` for auth and rate limits; older OpenResty cannot use Redis cosockets in rewrite; use content phase for response bodies.
2. Redis clients must use `set_keepalive` pooling or high concurrency opens too many connections.
3. Headers via `ngx.var.http_*` are lowercase: `X-Api-Key` → `ngx.var.http_x_api_key`.
4. Fixed windows can double-spike at boundaries; sliding windows use Redis sorted sets.
5. `wrk` uses one source IP and hits 429 quickly; rate limit by API key instead of IP for load tests.
6. Configure cosocket timeouts so a slow Redis does not block workers.

```bash
cd mini-gateway
./start-redis.sh    # ① Redis + 初始化（成功后才继续）
./start-gateway.sh  # ② 网关（依赖 Redis 就绪）
./start-ui.sh       # ③ 管理 UI（依赖网关就绪）
./start-all.sh      # 按顺序执行 ①→②→③
./start.sh          # 仅网关栈（memory/sqlite 或 redis 一步起）
./stop.sh           # 停止全部容器
```

Docker 三容器：`gw-redis`（6379）、`gw-openresty`（8080）、`gw-ui`（3000）。端口可用 `.env` 的 `REDIS_PORT` / `GATEWAY_PORT` / `UI_PORT` 调整。

### Storage (`GATEWAY_STORAGE`)

| Value | Description |
|-------|-------------|
| `memory` | **Default.** `lua_shared_dict` in OpenResty (fast, not persisted across container recreate) |
| `redis` | Redis + `redis-init` bootstrap ( `./start.sh` with `GATEWAY_STORAGE=redis` ) |
| `sqlite` | File DB at `./data/gateway.db` (persisted volume, needs `openresty/Dockerfile` build) |

```bash
GATEWAY_STORAGE=memory ./start.sh
GATEWAY_STORAGE=redis ./start.sh
GATEWAY_STORAGE=sqlite ./start.sh
```

Default credentials after bootstrap: API key `mini-key`, admin Bearer token `mini-token`.

Option 1:
```bash
curl -H "X-Api-Key: mini-key" http://127.0.0.1:8080
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

--

GATEWAY_STORAGE=sqlite ./start.sh
echo $?   # 应为 0
curl -H "X-Api-Key: mini-key" http://127.0.0.1:8080/
ls -la ./data/gateway.db

--
START_VERBOSE=1 GATEWAY_STORAGE=sqlite ./start.sh

--
docker logs gw-openresty

--
start:

./start.sh                                    # memory（默认，不启 Redis）
GATEWAY_STORAGE=redis ./start.sh              # Redis + redis-init
GATEWAY_STORAGE=sqlite ./start.sh             # SQLite 落盘 ./data/

--
curl -i http://127.0.0.1:8080/                              # 401
curl -i -H "X-Api-Key: mini-key" http://127.0.0.1:8080/     # 200


apt install nginx-module-http2
brew install nginx