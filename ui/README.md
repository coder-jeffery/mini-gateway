# Mini Gateway Admin UI

Next.js 管理后台，通过服务端 HMAC 签名调用网关 `admin_api_v1.lua`（`POST /admin/gw/v1`）。

## 前置条件

1. 网关使用 **Redis 存储**（v1 接口依赖 Redis）：
   ```bash
   GATEWAY_STORAGE=redis ./start.sh
   ```
2. Nginx 已挂载 `location /admin/gw/v1` → `admin_api_v1.lua`（仓库 `nginx.conf` 已包含）。
3. 运行 UI 的机器 IP 在 **admin:whitelist:ip** 中（Next 服务端 `fetch` 会以本机 IP 访问网关，一般为 `127.0.0.1`）。

## 本地开发

```bash
cp .env.example .env.local
cd ui && npm install && npm run dev
```

浏览器打开 [http://localhost:3000](http://localhost:3000)。

## Docker 独立 UI 容器

`ui/Dockerfile` 构建 **gw-ui** 容器（默认 **3000**），通过 Docker 网络访问 `http://openresty:8080/admin/gw/v1`。

```bash
./start-all.sh              # Redis → Gateway → UI 三个容器
START_UI_LOCAL=1 ./start-all.sh   # UI 仍用本机 npm run dev（调试用）
```

## 环境变量

| 变量 | 说明 |
|------|------|
| `GATEWAY_ADMIN_URL` | 默认 `http://127.0.0.1:8080/admin/gw/v1` |
| `GATEWAY_ADMIN_SECRET` | 与网关 `GATEWAY_ADMIN_SECRET` 相同。未设置或短于 16 字符时管理请求失败，没有内置默认值 |

## 功能

- API Key：创建/更新配额、删除（v1 无列表接口）
- 业务 IP 白名单：`whitelist:ip`
- 管理 IP 白名单：`admin:whitelist:ip`
