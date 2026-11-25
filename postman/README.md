# Postman import

**English (default)** · [简体中文](./README.zh-CN.md)

## Files

| File | Description |
|------|-------------|
| [mini-gateway.postman_collection.json](./mini-gateway.postman_collection.json) | Collection (v2.1, import as-is) |
| [mini-gateway.postman_environment.json](./mini-gateway.postman_environment.json) | Local environment variables |

## Import steps

1. Postman → **Import** → drag both JSON files (or **Select Files**).
2. Choose environment **mini-gateway local** in the top-right.
3. Start the gateway, for example:
   ```bash
   GATEWAY_AUTH_MODE=both OAUTH2_JWT_SECRET=oauth2-dev-secret docker compose up -d openresty
   ```
4. Send requests in the **mini-gateway** collection.

## Collection contents

**Business API (GET /)** — `GET {{gateway_base_url}}/`

- JWT valid / expired / bad signature / client_id (Pre-request script signs HS256)
- API Key, unauthenticated

**Admin API HMAC** — `POST {{admin_gw_v1_url}}`

- `hmac_test`, `whitelist_list` (Pre-request computes ts/nonce/sign)

JWT payloads match `test/jwt_client.py`; tweak `oauth2_jwt_secret`, `gateway_base_url`, etc. in the environment.