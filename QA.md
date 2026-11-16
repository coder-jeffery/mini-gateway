Why use `log_by_lua` + `ngx.timer.at` for access logs?

1. `access_by_lua` runs before the upstream; `log_by_lua` runs after the response is sent—good for audit and metrics.
2. Sync Redis in `log_by_lua` would add latency; `ngx.timer.at(0)` runs off the request coroutine with no user-facing delay.
3. Pitfall: timer callbacks cannot rely on `ngx.ctx` after the request ends—serialize data before scheduling the timer.

Improvements:

1. Add `request_id` in `rewrite_by_lua`, store in `ngx.var`, forward to upstream and logs.
2. Use Redis Stream (`XADD`) instead of a list for consumer groups and acks.
3. Set `lua_max_pending_timers` to cap timer growth under load.
4. Sample logs at high QPS to reduce Redis pressure.


### 

1. SSE 大模型流式场景，API 网关 proxy_buffering 需要怎么配置？为什么？
   解答：`proxy_buffering off`，关闭后端响应缓冲；同时关闭 proxy_cache 
   a.`proxy_buffering`开启时，网关会把上游返回的响应块全部缓存到缓冲区,等待上游完整返回全部数据之后，才一次性转发给客户端
   b.SSE 是分片流式输出，模型逐 token 返回数据；如果开启缓冲，前端不会收到实时 token，要等大模型全部生成完毕才拿到完整结果，**SSE 流式效果完全失效，变成普通一次性 HTTP 响应
   c.同时关闭 cache，SSE 流不允许做缓存
2. proxy_read_timeout 在 SSE 场景代表什么含义，如果设置成普通接口的 5s，会出现什么现象？
   a.**含义**：`proxy_read_timeout`不是整个请求的最大总超时；是**网关从上游推理服务两次收到数据包之间的最大空闲等待时间**,只要上游持续吐出 token，计时器就会不断重置；只有上游长时间没有任何数据返回才触发超时断开
   b.设置为 5s 现象：大模型生成时，受模型、输入 prompt、GPU 负载影响，有可能出现 > 5 秒没有新 token 输出的间隙。此时网关判定上游超时，**主动切断 SSE 长连接，对话中途直接断开，用户体验为生成到一半突然终止**,SSE 场景一般调至 60‑300s，同时保留上限，防止僵尸连接
3. 用户前端关闭页面断开 SSE 连接，网关层面需要做什么，否则会带来什么资源问题？
   a.需要：网关感知**客户端连接断开事件（client abort），立刻向上游推理服务传递关闭信号，终止后端推理任务**
   b.如果网关不向上游传递断开：前端页面已经关闭，但 GPU 推理服务仍然继续执行生成逻辑，持续消耗 GPU 显存、算力；造成**GPU 资源浪费、资源泄漏，高并发场景下 GPU 被无效任务占满，正常请求排队阻塞**
4. 想在 Kong 网关插件统计 SSE 流返回 token 数量，会遇到什么技术难点？
   a.**SSE 是分 chunk 流式返回，没有完整 response body**，不能等全部响应回来再解析；插件需要逐块处理每一个 TCP 分片,
   b.**JSON 跨分片（跨 chunk）问题**：一个 SSE 的 JSON payload 可能被 TCP 切割拆分到两个不同的数据包，单次拿到的片段不是合法 JSON，直接 JSON 解析会报错，需要做流拼装，实现复杂度高
   c.SSE 协议格式：`data: xxx\n\n`，需要先剥离 SSE 协议前缀，再解析内部 JSON
   d.CPU 开销：网关侧每一个 token 流都要做流式 JSON 解析，高 QPS 场景会增加网关 CPU 消耗
5. 现有 APISIX grpc‑transcode 插件，能不能直接实现客户端 SSE 到后端 gRPC‑Stream 推理服务？为什么？有哪些替代方案？
   解答：不能直接实现；`grpc‑transcode` 仅支持 **Unary 一元调用**，**不支持服务端 Stream / 双向 Stream**；插件只处理普通 HTTP‑JSON 请求，无法接收 SSE 长连接、无法把 SSE 转换成 gRPC‑Stream 流式会话
   a. **方案 1（推荐）**：推理服务同时暴露 HTTP‑SSE 接口，网关直接代理 HTTP‑SSE，不做 grpc 转码；网关与后端走 HTTP。
   b. **方案 2**：独立开发适配中间服务，接收客户端 SSE，内部作为 gRPC 客户端调用后端 gRPC‑Stream 推理服务，完成 SSE ↔ gRPC‑Stream 协议转换；网关代理到这个适配层。
   c. **方案 3**：扩展网关自定义插件，手写 gRPC‑Stream 客户端逻辑；开发维护成本高
6. SSE 流请求 HTTP 返回 200，但业务对话失败，是什么情况，监控如何识别这类错误？
      a. 网关侧逐 SSE 事件解析 payload，识别流内`error`字段，统计业务错误指标（流业务失败计数器）。注意处理 JSON 跨分片问题。
      b. 识别 SSE 流结束事件：正常结束会返回结束标记；没有正常结束标记、提前关闭连接，标记为异常流。
      c. 增加指标：SSE 连接异常断开数，区分：客户端主动断开、网关超时断开、业务错误断开。
      d. 将 traceId 透传到 SSE 事件，把流内业务错误上报到可观测系统；**不能单纯依靠 HTTP 响应码做成功率统计**。
      e. 业务层上报 usage/token 计数：如果一个会话返回 0 个有效 token，也作为异常信号