# JWT 测试数据与 curl（业务网关）

## Postman 导入

直接导入（Collection v2.1 + Environment）：

- [`../postman/mini-gateway.postman_collection.json`](../postman/mini-gateway.postman_collection.json)
- [`../postman/mini-gateway.postman_environment.json`](../postman/mini-gateway.postman_environment.json)

说明见 [`../postman/README.md`](../postman/README.md)。JWT 在 Pre-request 中动态签发，无需手填过期 token。

## 测试接口

| 用途 | 方法 | URL | 说明 |
|------|------|-----|------|
| 业务 API（OAuth2 / API Key） | `GET` | `http://127.0.0.1:8080/` | 走 `access_check.lua`，成功后转发 httpbin |
| 管理 API（HMAC，非 JWT） | `POST` | `http://127.0.0.1:8080/admin/gw/v1` | 见 `hmac_call.sh` |

网关 OAuth2 联调前请设置（示例）：

```bash
export GATEWAY_AUTH_MODE=both
export OAUTH2_JWT_SECRET=oauth2-dev-secret
# docker compose 重启 openresty，或本地等价环境变量
```

Fixture 定义见 [`jwt_fixtures.json`](jwt_fixtures.json)。

## 一键脚本

```bash
chmod +x test/jwt_call.sh

# 合法 token：打印 payload / JWT / curl，并发起请求
./test/jwt_call.sh valid

# 仅输出 JWT 字符串
./test/jwt_call.sh token valid

# 仅输出 curl（可复制到其他机器）
./test/jwt_call.sh curl valid

# 过期 / 错签 / 错 secret 等
./test/jwt_call.sh expired
./test/jwt_call.sh bad_sig

# 批量
./test/jwt_call.sh all
```

自动化：`python3 test/test_oauth2.py`

## 示例 payload（HS256）

与网关 `OAUTH2_JWT_SECRET=oauth2-dev-secret` 一致时，由 `jwt_client.py` 动态签发：

**valid**

```json
{
  "sub": "test-user-valid",
  "exp": 1735689600
}
```

（`exp` 为 Unix 秒，脚本会使用 `now + 3600`。）

**valid_client**（配合 `OAUTH2_RATE_LIMIT_KEY=client_id`）

```json
{
  "sub": "svc-account",
  "client_id": "client-mini-gateway-01",
  "exp": 1735689600
}
```

**expired**

```json
{
  "sub": "test-user-expired",
  "exp": 1
}
```

（脚本使用 `now - OAUTH2_CLOCK_SKEW_SEC - 120`。）

若配置了 `OAUTH2_ISSUER`，valid 类 payload 会自动带上相同 `iss`；配置了 `OAUTH2_AUDIENCE` / `OAUTH2_REQUIRED_SCOPE` 时，valid 会自动附带匹配 claim。

## 手工 curl 示例

**一条命令（与 API Key 探测同级）：**

```bash
./test/jwt_curl.sh
```

等价于：

```bash
curl -i -H "Authorization: Bearer <JWT>" -H "Accept: application/json" "http://127.0.0.1:8080/"
```

（`<JWT>` 由脚本用 `OAUTH2_JWT_SECRET` 动态签发，`sub=test-user-valid`。）

或手动：

```bash
TOKEN=$(./test/jwt_call.sh token valid)
curl -i \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Accept: application/json" \
  "http://127.0.0.1:8080/"
```

期望成功响应头包含：

- `X-Gateway-Auth: oauth2`
- `X-Gateway-Auth-Subject: sub:test-user-valid`（默认按 sub 限流）

**both 模式** 下仍可用 API Key（与 JWT 二选一）：

```bash
curl -i -H "X-Api-Key: mini-key" "http://127.0.0.1:8080/"
```

**无凭证**（both 模式）：

```bash
curl -i "http://127.0.0.1:8080/"
# 401 {"code":401,"msg":"missing Authorization Bearer token or X-Api-Key header"}
```

## 期望结果速查

| case | HTTP | body.msg（典型） |
|------|------|------------------|
| valid | 200 | （httpbin JSON） |
| expired | 401 | token expired |
| bad_sig | 401 | invalid token signature |
| wrong_secret | 401 | invalid token signature |
| missing_exp | 401 | missing exp claim |
| wrong_audience | 401 | invalid audience（需配 OAUTH2_AUDIENCE） |
| missing_scope | 401 | insufficient scope（需配 OAUTH2_REQUIRED_SCOPE） |
