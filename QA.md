为什么日志上报要放在 `log_by_lua` + `ngx.timer.at`？

1. `access_by_lua` 是请求前置校验；`log_by_lua` 是请求生命周期后置钩子，**响应已经发给客户端**，适合审计、埋点、统计
2. 如果直接在 log_by_lua 里面同步 Redis 请求：Redis 慢会拖慢整个请求；`ngx.timer.at(0)` 把任务脱离当前请求协程，异步后台执行，**零延迟影响用户**
3. 坑：timer 回调不能直接捕获 `ngx.ctx`，请求协程销毁后 ctx 失效，必须提前序列化 / 拷贝数据传参

1. 日志加 `request_id`：在 rewrite_by_lua 生成 uuid 放到 ngx.var，透传到上游、日志，方便链路追踪
2. 日志改成写入 Redis Stream（`XADD`），比 list 更适合消费程序拉取（有消费组、ack 机制）
3. 增加定时器数量保护：`lua_max_pending_timers`，防止突发流量创建海量 timer
4. 日志采样：高 QPS 时只采样一部分请求上报，降低 Redis 压力