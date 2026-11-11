网关能转发的协议，按网络层次可以分成四层、七层和应用层专用协议三类。下面每项都标了 Nginx/OpenResty 能不能做、要怎么做，最后附主流网关的对比。

**四层（L4）**

- TCP：Nginx 用 `stream` 模块，OpenResty 用 `stream-lua` 可以写逻辑。常拿来代理 MySQL、Redis、Kafka 这类自定义 TCP 协议。
- UDP：同样用 `stream` 模块，适合 DNS、日志收集（syslog）、游戏等场景。
- TLS 透传或终结：可以按 SNI 分流而不解密（`ssl_preread`），也可以在网关卸载 TLS 后再转发明文。
- PROXY Protocol：透传客户端真实 IP 给后端，L4 场景下很常用。

**七层（L7）HTTP 系**

- HTTP/1.0、HTTP/1.1：基础能力。
- HTTP/2：客户端侧原生支持；upstream 侧 Nginx 只在 `grpc_pass` 里走 HTTP/2，普通 `proxy_pass` 是 HTTP/1.1，这是 Nginx 的一个限制。
- HTTP/3（QUIC）：Nginx 1.25 起正式支持，OpenResty 新版本也跟进了；Envoy 早就支持了。
- HTTPS 和 mTLS：双向证书认证，可以在网关做终结，也可以对上游重新发起 mTLS。
- WebSocket：靠 `Upgrade` 头升级，配好 `proxy_http_version 1.1` 和 `Connection` 头就行，注意把读超时调长。
- SSE（Server-Sent Events）：AI 流式输出靠它，要关闭 `proxy_buffering`、放宽超时。
- gRPC：`grpc_pass` 原生代理，支持 unary 和流式；gRPC-Web 需要额外模块或插件转换。

**应用层专用协议（多数靠插件或扩展）**

- Dubbo：APISIX 有 `dubbo-proxy` 插件（HTTP 转 Dubbo），Higress、Envoy 也有支持。
- Thrift：Envoy 有原生过滤器，OpenResty 需要自己写编解码。
- MQTT：APISIX 的 `mqtt-proxy` 可以按 client ID 做负载均衡，EMQX 这类专业 MQTT broker 能力更全。
- Redis、MySQL、Kafka、MongoDB 协议感知：Envoy 有对应的过滤器，可以做命令级路由、统计、限流；APISIX 也在做 xRPC 框架来支持这类协议。
- GraphQL：可以按 query 字段路由、限流、做查询深度限制，APISIX、Kong 都有插件。
- SOAP、WebService：一般做 REST 转 SOAP 的转换，Kong、APISIX 都有相关插件。

**协议转换（网关最有价值的能力之一）**

- HTTP/JSON 转 gRPC：前端发 REST，后端是 gRPC，APISIX 的 `grpc-transcode` 和 Envoy 的 `grpc_json_transcoder` 都能做。
- gRPC-Web 转 gRPC：浏览器直接调 gRPC 服务。
- HTTP 转 Dubbo：让 Java Dubbo 服务直接对外暴露 HTTP 接口。
- REST 转 SOAP、REST 转 GraphQL。
- AI 场景：OpenAI 格式转其他厂商格式（Claude、Gemini、通义等），这本质上也是一种协议转换。
- AI Agent 场景：HTTP/REST 转 MCP，把现有 API 包装成 MCP 工具给 Agent 调用，Higress 和 APISIX 都已经在做。


协议	Nginx/OpenResty	APISIX	Kong	Envoy	Higress
TCP/UDP	✅ stream	✅	✅	✅	✅
HTTP/2 到上游	仅 gRPC	仅 gRPC	✅	✅	✅
HTTP/3	✅ 新版本	✅ 新版本	实验性	✅	✅
WebSocket / SSE	✅	✅	✅	✅	✅
gRPC 代理	✅	✅	✅	✅	✅
HTTP 转 gRPC	需自己实现	✅ 插件	✅ 插件	✅ 原生	✅
Dubbo	需自己实现	✅ 插件	无	✅	✅
MQTT	需自己实现	✅ 插件	无	有限	有限
Redis/MySQL 等协议感知	需自己实现	部分（xRPC）	无	✅ 过滤器	部分
MCP 转换	需自己实现	✅ 插件	✅ 插件	通过 AI Gateway	✅