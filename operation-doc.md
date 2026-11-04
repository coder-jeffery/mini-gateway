
operation doc:
    case 1: 创建 / 更新 apikey：abc123，30s 最多 20 次
        curl -X POST http://127.0.0.1:8080/admin/gw \
        -H "Content-Type: application/json" \
        -d '{
            "admin_secret":"admin-secret-2026",
            "action":"upsert_apikey",
            "api_key":"abc123",
            "limit":20,
            "window":30
        }'


    case 2:  添加 IP 到白名单
        curl -X POST http://127.0.0.1:8080/admin/gw \
        -H "Content-Type: application/json" \
        -d '{
            "admin_secret":"admin-secret-2026",
            "action":"whitelist_add",
            "ip":"127.0.0.1"
        }'

    case 3:移除白名单 IP

    curl -X POST http://127.0.0.1:8080/admin/gw \
    -H "Content-Type: application/json" \
    -d '{
        "admin_secret":"admin-secret-2026",
        "action":"whitelist_del",
        "ip":"127.0.0.1"
    }'

    case4 :查询全部白名单 IP
    curl -X POST http://127.0.0.1:8080/admin/gw \
    -H "Content-Type: application/json" \
    -d '{
        "admin_secret":"admin-secret-2026",
        "action":"whitelist_list"
    }'

    case 5:
    curl -X POST http://127.0.0.1:8080/admin/gw \
    -H "Content-Type: application/json" \
    -d '{
        "admin_secret":"admin-secret-2026",
        "action":"del_apikey",
        "api_key":"abc123"
    }'


    ADMIN_WHITELIST_IP=127.0.0.1 docker compose up -d
    项目初始化配置白名单：
        ADMIN_WHITELIST_IP=127.0.0.1 docker compose up -d


<!-- curl -i -H "X-Api-Key: mini-key" http://127.0.0.1:8080 -->
