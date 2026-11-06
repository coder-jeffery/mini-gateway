
operation doc:
    case 1: 创建 / 更新 apikey：abc123，30s 最多 20 次
        curl -X POST http://127.0.0.1:8080/admin/gw \
        -H "Content-Type: application/json" \
        -d '{
            "admin_secret":"admin-secret-2026",
            "action":"upsert_apikey",
            "api_key":"abc123",
            "limit":20,
            "window":30
        }'


    case 2:  添加 IP 到白名单
        curl -X POST http://127.0.0.1:8080/admin/gw \
        -H "Content-Type: application/json" \
        -d '{
            "admin_secret":"admin-secret-2026",
            "action":"whitelist_add",
            "ip":"127.0.0.1"
        }'

    case 3:移除白名单 IP

    curl -X POST http://127.0.0.1:8080/admin/gw \
    -H "Content-Type: application/json" \
    -d '{
        "admin_secret":"admin-secret-2026",
        "action":"whitelist_del",
        "ip":"127.0.0.1"
    }'

    case4 :查询全部白名单 IP
    curl -X POST http://127.0.0.1:8080/admin/gw \
    -H "Content-Type: application/json" \
    -d '{
        "admin_secret":"admin-secret-2026",
        "action":"whitelist_list"
    }'

    case 5:
    curl -X POST http://127.0.0.1:8080/admin/gw \
    -H "Content-Type: application/json" \
    -d '{
        "admin_secret":"admin-secret-2026",
        "action":"del_apikey",
        "api_key":"abc123"
    }'


    ADMIN_WHITELIST_IP=127.0.0.1 docker compose up -d
    项目初始化配置白名单：
        ADMIN_WHITELIST_IP=127.0.0.1 docker compose up -d


<!-- 业务网关（仅 API Key，GET 即可） -->
<!-- curl -i -H "X-Api-Key: mini-key" http://127.0.0.1:8080/ -->

OAuth2 Resource Server（阶段 1，Bearer JWT）：

    环境变量（见 .env.example）：
        GATEWAY_AUTH_MODE=api_key|bearer|both   # 默认 api_key，兼容旧行为
        OAUTH2_ISSUER / OAUTH2_JWKS_URI         # RS256（可只配 ISSUER，自动拉 OIDC discovery）
        OAUTH2_JWT_SECRET                       # 本地 HS256 联调
        OAUTH2_AUDIENCE / OAUTH2_REQUIRED_SCOPE # 可选 claim 校验
        OAUTH2_RATE_LIMIT_KEY=sub|client_id     # 限流维度，默认 sub

    HS256 联调示例（both 模式，API Key 与 Bearer 二选一）：
        export GATEWAY_AUTH_MODE=both
        export OAUTH2_JWT_SECRET=oauth2-dev-secret
        # 重启网关后
        python3 test/test_oauth2.py

    测试数据与 curl（HS256 联调）见 test/jwt-test-data.md、test/jwt_fixtures.json：
        chmod +x test/jwt_call.sh
        ./test/jwt_call.sh valid
        ./test/jwt_call.sh token valid
        TOKEN=$(./test/jwt_call.sh token valid)
        curl -i -H "Authorization: Bearer ${TOKEN}" http://127.0.0.1:8080/

    成功时响应头含 X-Gateway-Auth: oauth2、X-Gateway-Auth-Subject（限流 key）。

HMAC 管理接口 v1（/admin/gw/v1，POST + 签名；管理 IP 需在白名单）：

    与上面业务 curl 对应的 HMAC 探测（同样 curl -i，验签 action hmac_test）：

        SECRET='admin-secret-2026'
        TS=$(date +%s)
        NONCE=$(uuidgen)
        SIGN=$(printf '%s' "${TS}:${NONCE}" | openssl dgst -sha256 -hmac "$SECRET" | awk '{print $2}')
        curl -i -X POST http://127.0.0.1:8080/admin/gw/v1 \
          -H "Content-Type: application/json" \
          -d "{\"ts\":${TS},\"nonce\":\"${NONCE}\",\"sign\":\"${SIGN}\",\"action\":\"hmac_test\"}"

    期望：HTTP/1.1 200，body 含 "ok":true,"msg":"hmac verified"

HMAC 管理接口 v1（/admin/gw/v1）：

    专用探测 action（验签通过后返回 hmac verified）：
        ./test/hmac_call.sh
        ./test/hmac_call.sh hmac_test

    跑三条自动化用例（成功 / 错误签名 / 过期时间戳）：
        python3 test/test_hmac.py

    任意 v1 action 示例：
        ./test/hmac_call.sh whitelist_list
        GATEWAY_ADMIN_SECRET=admin-secret-2026 ADMIN_GW_V1_URL=http://127.0.0.1:8080/admin/gw/v1 ./test/hmac_call.sh apikey_list '{"page":1,"page_size":10}'

    签名规则：sign = HMAC-SHA256(secret, "{ts}:{nonce}").hexdigest()，body 需含 ts、nonce、sign、action。
