# Mini Gateway Admin UI

[English (default)](./README.md) · **简体中文**

Next.js 管理后台，通过服务端 HMAC 签名调用网关 `admin_api_v1.lua`（`POST /admin/gw/v1`）。**v1 已与 `store` 抽象对齐**，网关使用 `memory`、`redis` 或 `sqlite` 时 UI 均可 CRUD。

## 前置条件

1. 网关已启动（任意存储模式均可）：
   ```bash
   GATEWAY_STORAGE=memory ./start.sh   # 默认
   GATEWAY_STORAGE=sqlite ./start.sh
   GATEWAY_STORAGE=redis ./start.sh      # 需 Redis profile / start-redis
   ```
2. Nginx 已挂载 `location /admin/gw/v1` → `admin_api_v1.lua`。
3. **管理 IP 白名单**：
   - 本机 `npm run dev`：服务端 `fetch` 来源一般为 `127.0.0.1`，bootstrap 会写入 `admin:whitelist:ip`。
   - **Docker UI 容器**：来源为 Docker 网段 IP；Compose 默认 `GATEWAY_ADMIN_TRUST_PRIVATE=1`，信任 RFC1918 私网段；生产环境请把 UI 出口 IP 加入 `admin:whitelist:ip`。

## 本地开发

```bash
cp .env.example .env.local
cd ui && npm install && npm run dev
```

浏览器打开 [http://localhost:3000](http://localhost:3000)。页头会探测网关并显示当前 **storage**（memory / redis / sqlite）。

## Docker 独立 UI 容器

`ui/Dockerfile` 构建 **gw-ui**（默认 **3000**），经 Docker 网络访问 `http://openresty:8080/admin/gw/v1`。

```bash
./start.sh                    # memory 网关 + 可选 UI profile
./start-all.sh                # Redis → Gateway → UI（三容器）
START_UI_LOCAL=1 ./start-all.sh   # UI 用本机 npm run dev
```

## 环境变量

| 变量 | 说明 |
|------|------|
| `GATEWAY_ADMIN_URL` | 默认 `http://127.0.0.1:8080/admin/gw/v1`；Compose 内为 `http://openresty:8080/admin/gw/v1` |
| `GATEWAY_ADMIN_SECRET` | 与网关 `GATEWAY_ADMIN_SECRET` 一致，默认 `admin-secret-2026` |

## 功能

- API Key：列表、创建/更新配额、删除
- 业务 IP 白名单：`whitelist:ip`
- 管理 IP 白名单：`admin:whitelist:ip`
- 治理：审计、RBAC、URI 封禁与路由配额