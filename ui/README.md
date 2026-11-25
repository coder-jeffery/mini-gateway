# Mini Gateway Admin UI

**English (default)** · [简体中文](./README.zh-CN.md)

Next.js admin console. Server-side HMAC signs requests to `admin_api_v1.lua` (`POST /admin/gw/v1`). **v1 uses the same `store` abstraction**, so CRUD works when the gateway runs on `memory`, `redis`, or `sqlite`.

## Prerequisites

1. Gateway running (any storage mode):
   ```bash
   GATEWAY_STORAGE=memory ./start.sh   # default
   GATEWAY_STORAGE=sqlite ./start.sh
   GATEWAY_STORAGE=redis ./start.sh      # Redis profile / start-redis
   ```
2. Nginx routes `location /admin/gw/v1` → `admin_api_v1.lua`.
3. **Admin IP allowlist**:
   - Local `npm run dev`: server `fetch` is usually from `127.0.0.1`; bootstrap seeds `admin:whitelist:ip`.
   - **Docker UI container**: source is a Docker network IP; Compose sets `GATEWAY_ADMIN_TRUST_PRIVATE=1` for RFC1918; in production add the UI egress IP to `admin:whitelist:ip`.

## Local development

```bash
cp .env.example .env.local
cd ui && npm install && npm run dev
```

Open [http://localhost:3000](http://localhost:3000). The header probes the gateway and shows **storage** (memory / redis / sqlite).

## Docker UI container

`ui/Dockerfile` builds **gw-ui** (default **3000**), calling `http://openresty:8080/admin/gw/v1` on the Docker network.

```bash
./start.sh                    # memory gateway + optional UI profile
./start-all.sh                # Redis → Gateway → UI (three containers)
START_UI_LOCAL=1 ./start-all.sh   # UI via local npm run dev
```

## Environment variables

| Variable | Description |
|----------|-------------|
| `GATEWAY_ADMIN_URL` | Default `http://127.0.0.1:8080/admin/gw/v1`; in Compose `http://openresty:8080/admin/gw/v1` |
| `GATEWAY_ADMIN_SECRET` | Must match gateway `GATEWAY_ADMIN_SECRET`; default `admin-secret-2026` |

## Features

- API keys: list, create/update quotas, delete
- Business IP allowlist: `whitelist:ip`
- Admin IP allowlist: `admin:whitelist:ip`
- Governance: audit, RBAC, URI blocks, route quotas