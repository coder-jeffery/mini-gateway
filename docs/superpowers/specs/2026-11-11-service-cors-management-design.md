# Service 级路由与 CORS 管理设计

## 目标

在现有管理台中增加 Service CRUD。每个 Service 通过 URI 前缀识别业务流量，配置一个上游基础 URL，并拥有独立的 CORS 策略。配置更新不需要重载 OpenResty。

本次只支持单上游 URL，不包括权重、主动健康检查、重试、路径改写和自定义 Host。

## Service 模型

每个 Service 包含：

- `id`：创建时生成，不可修改。
- `name`：唯一的显示名称。
- `path_prefix`：唯一的 URI 前缀，必须以 `/` 开头。
- `upstream_url`：以 `http://` 或 `https://` 开头的基础 URL，不含查询参数。
- `cors_enabled`
- `cors_allow_origins`
- `cors_allow_methods`
- `cors_allow_headers`
- `cors_expose_headers`
- `cors_max_age`
- `cors_allow_credentials`

Redis/存储抽象中的键：

- `service:index`：Service ID 集合。
- `service:{id}`：完整 Service JSON。

Service 名称和路径前缀在创建、更新时扫描索引检查唯一性。删除 Service 时同时删除索引成员和实体。

## 路由匹配

业务请求进入 `location /` 后，在鉴权和 CORS 预检前解析 Service：

1. 从 `lua_shared_dict` 读取 Service 快照。
2. 缓存不存在或过期时，通过当前 `store` 后端读取 `service:index` 和实体 JSON。
3. 按最长 `path_prefix` 匹配请求 URI。
4. 前缀必须是完整路径边界：`/api/orders` 匹配自身及 `/api/orders/...`，但不匹配 `/api/orders-v2`。
5. 命中后把 Service 和完整代理目标写入请求上下文及 Nginx 变量。
6. 未命中时继续使用现有全局 CORS 环境变量和默认上游。

Service 上游保留原始请求 URI 和查询参数，不执行前缀剥离。例如：

```text
path_prefix=/api/orders
upstream_url=http://orders:8080
request=/api/orders/42?detail=1
target=http://orders:8080/api/orders/42?detail=1
```

动态代理使用上游 URL 中的 host 作为 Host 请求头。

## 缓存一致性

每个 OpenResty 实例使用 `lua_shared_dict` 缓存排序后的 Service 快照，默认 TTL 为 5 秒。

- 管理动作成功后立即清除当前实例缓存。
- 其他集群实例在 TTL 到期后读取最新配置。
- 不在每个业务请求上查询 Redis 版本号，避免为了强一致性抵消本地缓存收益。
- 因此配置传播是最终一致，最大延迟约为缓存 TTL。

首轮不实现 Redis Pub/Sub 主动广播失效。

## CORS 行为

命中 Service 后，`cors.lua` 优先读取 Service 策略；未命中时读取现有全局环境变量。

- `cors_enabled=false` 时不处理该 Service 的跨域请求。
- 合法预检在鉴权前返回 `204`。
- 非法 Origin、Method 或 Header 返回 `403`。
- 实际请求仍执行 API Key/OAuth 鉴权和限流。
- 401、429、503 等网关错误也附带 Service CORS 响应头。
- `cors_allow_credentials=true` 时禁止 Origin 使用 `*`。
- `/admin/*`、`/health`、`/ready` 仍不启用 CORS。

## 控制面 API

增加以下 action：

- `service_create`
- `service_update`
- `service_delete`
- `service_get`
- `service_list`

业务逻辑放入独立的 `service_admin.lua`，v0 与 v1 管理接口调用同一实现，避免两份 CRUD 规则漂移。管理台继续通过现有 Next.js `/api/admin` 代理调用 HMAC v1。

校验失败返回 `400`，名称或路径冲突返回 `409`，找不到 Service 返回 `404`。存储错误返回 `500`。

## 管理页面

管理台增加“Service CORS”页签，采用主从布局：

- 左侧显示 Service 名称、路径前缀、上游地址，提供刷新、新增和删除。
- 右侧显示创建或编辑表单。
- 保存后刷新左侧列表并保持当前 Service 选中。
- 删除前二次确认；删除成功后选择下一项或显示空状态。

表单分为“路由”和“CORS”两组。Origins、Methods 和 Headers 使用逗号分隔文本，保持与环境变量配置一致。

## 错误与降级

- Service 配置损坏时跳过该记录并写错误日志，其他 Service 继续可用。
- Service 缓存仍有效时，短暂存储故障继续使用缓存。
- 缓存缺失且存储不可用时，路由解析返回 503，避免请求被错误转发到默认上游。
- 未配置任何 Service 不视为错误，保留当前默认上游行为。

## 测试

后端测试覆盖：

- Service 创建、读取、更新、删除和列表。
- 名称、路径冲突及非法上游 URL。
- 最长前缀和路径边界匹配。
- Service 预检、非法 Origin、鉴权错误 CORS 头。
- 命中 Service 后选择动态上游，未命中时回退默认上游。

前端验证覆盖：

- TypeScript/ESLint。
- Next.js production build。
- 列表加载、创建、编辑、删除和表单错误展示。

集成验证使用 Redis 模式，因为当前管理 UI 的 v1 HMAC API 依赖 Redis。
