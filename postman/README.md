# Postman 导入

## 文件

| 文件 | 说明 |
|------|------|
| [mini-gateway.postman_collection.json](./mini-gateway.postman_collection.json) | 请求集合（v2.1，可直接 Import） |
| [mini-gateway.postman_environment.json](./mini-gateway.postman_environment.json) | 本地环境变量 |

## 导入步骤

1. 打开 Postman → **Import** → 拖入上述两个 JSON（或 Select Files）。
2. 右上角 Environment 选择 **mini-gateway local**。
3. 启动网关，例如：
   ```bash
   GATEWAY_AUTH_MODE=both OAUTH2_JWT_SECRET=oauth2-dev-secret docker compose up -d openresty
   ```
4. 在 Collection **mini-gateway** 中依次 Send 请求。

## 集合内容

**Business API (GET /)** — 业务测试接口 `GET {{gateway_base_url}}/`

- JWT valid / expired / bad signature / client_id（Pre-request 用 HS256 动态签发）
- API Key、无凭证

**Admin API HMAC** — `POST {{admin_gw_v1_url}}`

- `hmac_test`、`whitelist_list`（Pre-request 计算 ts/nonce/sign）

JWT 与 `test/jwt_client.py` 使用相同 payload 规则；修改 `oauth2_jwt_secret`、`gateway_base_url` 等在 Environment 中即可。
