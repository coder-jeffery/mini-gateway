

- 白名单 IP：redis set `whitelist:ip`，命中直接跳过限流
- 动态配额：每个 apikey 在 redis 存自己的 limit/window，不写死在 lua 里
- 限流响应头：返回 `X-RateLimit-Limit` / `X-RateLimit-Remaining` / `X-RateLimit-Reset`
- 熔断：Redis 异常时开关，直接放行或者全部拒绝