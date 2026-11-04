

Intro:
1. **阶段选择：access_by_lua 适合鉴权限流，不能在 rewrite 做 redis cosocket（老版本限制），content 阶段才适合输出业务 body**
2. redis 一定要 `set_keepalive` 连接池，否则高并发大量短连接打爆 redis
3. `ngx.var.http_Xxx` 读取 header，header 名字全部小写，`X-Api-Key` → `ngx.var.http_x_api_key`
4. 限流这里是**固定窗口**，缺陷：窗口切换瞬间会双倍突刺；滑动窗口用 redis sorted set 实现
5. wrk 压测时，wrk 是同一个源 IP，很容易快速触发 429；想要压高并发不被限流，可以改造：按 token 维度限流而不是 IP
6. openresty 的 cosocket 超时必须配置，防止 redis 卡住整个 worker

cd gateway
docker compose up -d

方式一：
curl -H "X-Api-Key: abc123" http://127.0.0.1:8080

方式二：
docker exec -it gw-redis redis-cli SET apikey:abc123 1
curl -H "X-Api-Key: abc123" http://127.0.0.1:8080

压测：
wrk -t2 -c20 -d10s -H "X-Api-Key: abc123" http://127.0.0.1:8080

添加白名单限制：
    docker exec -it gw-redis redis-cli
    SADD whitelist:ip 127.0.0.1


# 添加白名单IP
SADD whitelist:ip 127.0.0.1
# 删除白名单IP
SREM whitelist:ip 127.0.0.1
# 查看所有白名单
SMEMBERS whitelist:ip

动态配额：  HSET apikey:meta:abc123 limit 20 window 30  # api key 30 秒最多允许 20 次请求


# 1. 标记apikey合法（原有）
SET apikey:abc123 1

# 2. 设置该apikey独立配额：30s最多20次
HSET apikey:meta:abc123 limit 20 window 30

# 给另一个key不同配额：60s最多5次
SET apikey:xyz789 1
HSET apikey:meta:xyz789 limit 5 window 60

# 白名单ip
SADD whitelist:ip 127.0.0.1

# 查看配额
HGETALL apikey:meta:abc123



