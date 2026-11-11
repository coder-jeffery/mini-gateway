# mini-gateway 产品级开发计划（MVP 优先）

> 目标：在现有 OpenResty 网关雏形上，按**最小可交付 MVP → 生产就绪 → 能力扩展**递进，对齐常见 API 网关的「控制面 / 数据面 / 观测面」拆分，避免一次铺开 `develop-design.md` 中的 15 项大功能。

**语言：** 中文（本文件）· [English](to-do-list.en.md)

---

## 1. 架构分层（本项目映射）

行业里的「六面」在本仓库中的对应关系（只做边界清晰，不强行上满全套）：

| 面 | 职责 | mini-gateway 落点 |
|----|------|-------------------|
| **数据面** | 转发、鉴权、限流、熔断执行 | `nginx/lua/access_check.lua`、`oauth_validate.lua`、`nginx.conf` |
| **控制面** | 配置 CRUD、下发、存储后端 | `admin_api.lua`、`admin_api_v1.lua`、`store/*` |
| **管理面** | 人用的控制台 | `ui/`（Next.js → HMAC 调 `/admin/gw/v1`） |
| **观测面** | 指标、日志、告警 | `log_access.lua`；**缺口**：`/metrics`、脱敏、大盘 |
| **策略/安全面** | 集中策略（WAF、OPA 等） | 当前：**IP 白名单 + Admin 白名单 + OAuth scope**；远期 OPA/路径黑名单 |
| **扩展面** | 插件 / Wasm / 外部鉴权 | **未做**；MVP 不纳入 |
| **开发者面** | 门户、文档、Key 申请 | **未做**；P3 可选 |
| **AI 面** | 模型路由、token 计量 | **未做**；P4 可选 |

能力域对照（与市面网关能力清单对齐，标明阶段）：

| 能力域 | 子能力 | 现状 | 计划阶段 |
|--------|--------|------|----------|
| 流量接入与路由 | 固定上游转发 | ✅ httpbin 演示 | **P0** 可配置上游 |
| | 动态路由 / 灰度 / 镜像 | ❌ | P3 |
| 认证鉴权 | API Key | ✅ | — |
| | OAuth2 JWT（HS256/RS256） | ✅ | — |
| | Admin Bearer + HMAC | ✅ v0/v1 | **P0** 管理 API 统一 |
| 安全防护 | 业务 IP 白名单、Admin IP 白名单 | ✅ | — |
| | 日志脱敏、路径/UA 拦截 | ❌ | P0 脱敏；P2 路径黑名单 |
| 流量控制 | 滑动窗口、按 Key 配额 | ✅ | — |
| | 多维度 / 接口级 / 全局限流 | ❌ | P2 |
| | 错误率熔断 | ⚠️ 存储故障简易 pass/reject | **P1** |
| | 漏桶排队 | ❌ | P3 |
| 可观测性 | 异步访问日志、Request ID | ✅ | — |
| | Prometheus `/metrics` | ❌ | **P1** |
| | 日志采样、管理操作审计分类 | ❌ | P2 |
| 管理 / 存储 | memory / redis / sqlite | ✅ 业务链路 | **P0** UI 与 v1 存储一致 |
| 协议 | HTTP | ✅ | P4 WebSocket | TCP/UDP ｜ HTTP/2 ｜ HTTP/3 ｜ WebSocket / SSE ｜ gRPC 代理 ｜ HTTP 转 gRPC ｜ Dubbo｜ MQTT｜Redis/MySQL 等协议感知｜MCP 转换


---

## 2. 基线（已实现，不再排期）

交付物以仓库代码为准，回归见 `test/`、`postman/`、`operation-doc.md`。

- [x] **数据面**：`X-Api-Key` / OAuth2 Bearer（`api_key` \| `bearer` \| `both`）
- [x] **限流**：滑动窗口；按 API Key `limit/window`；OAuth 默认可配
- [x] **白名单**：业务 IP 免限流；管理 IP 保护 Admin
- [x] **存储**：`GATEWAY_STORAGE=memory|redis|sqlite` + worker bootstrap
- [x] **控制面 v0**：`/admin/gw`（Bearer admin token + 全存储抽象）
- [x] **控制面 v1**：`/admin/gw/v1`（HMAC + nonce 防重放；**仅 Redis 直连**）
- [x] **管理面**：UI 三 Tab（API Key、业务/管理白名单）
- [x] **可观测（轻量）**：`X-Request-Id`、限流响应头、`log_by_lua` 异步写访问日志
- [x] **部署**：Docker Compose 三容器脚本链、` .env.example`

---

## 3. MVP 定义（P0：最小产品级）

**一句定义**：团队能用**一套配置 + 管理台 + 探活**把网关接到**真实上游**，在 **redis 或 sqlite** 下完成 Key/白名单运维，且**日志不泄露密钥**。

### 3.1 成功标准（验收）

| # | 标准 | 验证方式 |
|---|------|----------|
| M1 | 上游地址、超时、Host 头可配置（无改代码发版） | 环境变量或 admin 配置 + `curl` 通真实后端 |
| M2 | `GET /health`（进程级）、`GET /ready`（存储可达） | K8s/Compose healthcheck 通过 |
| M3 | 管理路径一致：**UI 与自动化脚本**在选定存储模式下均可 CRUD | `test_hmac.py` + UI 手测；sqlite 模式同类用例 |
| M4 | 访问日志与错误日志**须脱敏** api_key / Bearer | 抽检 `gateway:access_log` / 文件日志 |
| M5 | 根目录 README：架构图、能力表、存储模式选型、运维入口 | 新同学 30 分钟内按文档起全栈 |
| M6 | CI：至少跑 `test/test.py`、`test_hmac.py`、`test_oauth2.py`（可选门禁） | PR 绿 |

### 3.2 P0 任务清单

| ID | 优先级 | 任务 | 交付物 | 依赖 |
|----|--------|------|--------|------|
| P0-1 | P0 | **可配置上游**：`GATEWAY_UPSTREAM_URL`（及 proxy 超时） | `nginx.conf` + `gateway_config.lua` | — |
| P0-2 | P0 | **健康检查**：`/health`、`/ready`（ready 探测当前 storage） | 新 `location` + 文档 | P0-1 |
| P0-3 | P0 | **统一控制面**：`admin_api_v1` 改为 `store` 抽象（与 v0 同后端） | Lua 重构 + 测试更新 | — |
| P0-4 | P0 | **UI 存储模式**：sqlite/memory 下可走 v0 代理或统一 v1；Compose 文档写清 | `ui` route + README | P0-3 |
| P0-5 | P0 | **审计脱敏**：`log_access.lua` 对 `api_key`、Authorization 打码 | Lua + 单测/脚本 | — |
| P0-6 | P1→P0 | **token_list**：实现或从 admin 文档删除「未实现」 | `admin_api.lua` | — |
| P0-7 | P0 | **产品 README**：与 `to-do-list` 能力矩阵对齐 | `README.md` | — |
| P0-8 | P0 | **CI 工作流**：GitHub Actions 跑 Python 测试 + UI build | `.github/workflows/*` | — |

> **刻意不进 P0**：Prometheus、多维度限流、灰度、RBAC、业务 HMAC、WebSocket、AI 插件（见 P1+）。

---

## 4. 路线图（P1 → P4）

与 `develop-design.md` 推荐顺序对齐，并补上产品化缺口。

### P1 — 生产就绪（可观测 + 韧性）

**目标**：能接监控告警，存储抖动时不靠「一次错误就全盘 pass」。

| ID | 任务 | 验收要点 |
|----|------|----------|
| P1-1 | **错误率熔断**（`lua_shared_dict` 窗口统计 + 半开探测） | 注入 Redis 失败，观察状态机与响应头 |
| P1-2 | **`GET /metrics`**（Prometheus：2xx/401/429/503、限流命中、熔断、存储错误） | `curl /metrics` + Grafana 样例 json（可选） |
| P1-3 | **熔断/降级策略可配置**（pass/reject + 阈值 env） | `.env.example` 说明 |
| P1-4 | **管理操作审计**：admin action 写入独立 stream/列表（与访问日志区分） | 改 Key 后可追溯 |
| P1-5 | **shared_dict 本地缓存**（apikey 元数据、业务白名单 TTL + 管理侧失效） | 压测 Redis QPS 下降（对比文档） |

### P2 — 策略增强（限流与安全）

**目标**：从「单 Key 单配额」升级到可运营的策略。

| ID | 任务 | 验收要点 |
|----|------|----------|
| P2-1 | **限流维度**：`api_key` / `ip` / `api_key+ip`（env 或 per-key 元数据） | `wrk` 多 IP 场景 |
| P2-2 | **接口级配额**：URI 前缀 → limit/window（管理 action） | 同 Key 不同 path 不同 429 |
| P2-3 | **全网关 QPS 上限** | 超限 429 + metric |
| P2-4 | **URI 黑名单 + UA 拦截**（管理配置） | 命中 403 |
| P2-5 | **访问日志采样**（失败全采、成功比例可配） | 高 QPS 下 Redis 压力可控 |

### P3 — 平台化（路由与治理）

| ID | 任务 | 验收要点 |
|----|------|----------|
| P3-1 | **灰度路由**（apikey/ip/百分比 → 多 upstream，`X-Gray-Tag`） | 规则可 CRUD |
| P3-2 | **Header/URI 改写**（管理规则表） | 集成测试 |
| P3-3 | **Admin RBAC**（role + 权限点，`token_issue` 绑角色） | read_only 不能删 Key |
| P3-4 | **配置快照与回滚**（apikey/白名单/路由） | 误操作可恢复 |
| P3-5 | **开发者面（最小）**：静态 OpenAPI + Key 申请工单（可仅文档+Postman） | 可选 |

### P4 — 扩展（按需）

| ID | 任务 | 说明 |
|----|------|------|
| P4-1 | 漏桶排队限流 | 与熔断联动设计见 `develop-design.md` §2 |
| P4-2 | 业务侧 HMAC 签名校验 | 区别于 Admin v1 |
| P4-3 | 限速预热（新 Key 渐升配额） | |
| P4-4 | WebSocket + 连接/消息限流 | `nginx.conf` 大改 |
| P4-5 | 带宽限流 | 字节计数 |
| P4-6 | AI 面：模型路由、token 计量、内容安全 | 独立子项目更佳 |

---

## 5. 迭代节奏建议（产品级）

| 迭代 | 周期（建议） | 主题 | 必交付 |
|------|----------------|------|--------|
| **Iter-0** | 当前 | 技术验证 | 基线（§2） |
| **Iter-1** | 2–3 周 | **P0 MVP** | P0-1～P0-8 全绿 + M1–M6 |
| **Iter-2** | 2 周 | **P1 可观测** | P1-1、P1-2、P1-3 |
| **Iter-3** | 2–3 周 | **P1 性能/审计** | P1-4、P1-5 |
| **Iter-4+** | 按业务选 | P2/P3 切片 | 每次只上一个「可演示」策略能力 |

**原则**

1. **数据面默认不改行为**：新能力用 env 开关，默认与现网一致。  
2. **控制面先于管理面**：先有 admin action + 测试，再改 UI。  
3. **观测随功能上线**：每加一个策略，同步加 metric 与日志字段。  
4. **存储抽象唯一**：禁止再出现「仅 Redis」管理路径（P0-3 之后）。

---

## 6. 文档与测试映射

| 文档 | 用途 |
|------|------|
| `operation-doc.md` | 运维 curl / OAuth / HMAC 手册（随 P0 更新上游与健康检查） |
| `develop-design.md` | P2+ 详细设计参考，**不作为 P0 范围** |
| `QA.md` | 面试/设计追问；熔断与日志 timer 说明 |
| `postman/` | 对外 API 契约；P0 后补 health/metrics |
| `test/*.py` | CI 真相源；每新增 admin action 补用例 |

---

## 7. 快速勾选（给排期用）

**P0 MVP（未全部完成前不发「产品版」标签）**

- [ ] P0-1 可配置上游  
- [ ] P0-2 /health、/ready  
- [ ] P0-3 admin v1 → store 抽象  
- [ ] P0-4 UI 全存储模式  
- [ ] P0-5 日志脱敏  
- [ ] P0-6 token_list 或下架  
- [ ] P0-7 产品 README  
- [ ] P0-8 CI  

**P1 生产就绪**

- [ ] P1-1 错误率熔断  
- [ ] P1-2 /metrics  
- [ ] P1-3 熔断策略配置  
- [ ] P1-4 管理审计日志  
- [ ] P1-5 配置本地缓存  

（P2～P4 细项见 §4，按迭代从 backlog 拉取。）

---

## 8. 变更记录

| 日期 | 说明 |
|------|------|
| 2026-03-26 | 按最小 MVP 重写：分层映射、基线、P0 验收标准、P1–P4 路线图、与 `develop-design.md` 对齐 |
