
Operations reference:

Case 1: Create / update api key `abc123`, 20 requests per 30s
```bash
curl -X POST http://127.0.0.1:8080/admin/gw \
  -H "Content-Type: application/json" \
  -d '{
    "admin_secret":"admin-secret-2026",
    "action":"upsert_apikey",
    "api_key":"abc123",
    "limit":20,
    "window":30
  }'
```

Case 2: Add IP to business whitelist
```bash
curl -X POST http://127.0.0.1:8080/admin/gw \
  -H "Content-Type: application/json" \
  -d '{
    "admin_secret":"admin-secret-2026",
    "action":"whitelist_add",
    "ip":"127.0.0.1"
  }'
```

Case 3: Remove whitelist IP
```bash
curl -X POST http://127.0.0.1:8080/admin/gw \
  -H "Content-Type: application/json" \
  -d '{
    "admin_secret":"admin-secret-2026",
    "action":"whitelist_del",
    "ip":"127.0.0.1"
  }'
```

Case 4: List all whitelist IPs
```bash
curl -X POST http://127.0.0.1:8080/admin/gw \
  -H "Content-Type: application/json" \
  -d '{
    "admin_secret":"admin-secret-2026",
    "action":"whitelist_list"
  }'
```

Case 5: Delete api key
```bash
curl -X POST http://127.0.0.1:8080/admin/gw \
  -H "Content-Type: application/json" \
  -d '{
    "admin_secret":"admin-secret-2026",
    "action":"del_apikey",
    "api_key":"abc123"
  }'
```

Bootstrap admin whitelist on compose up:
```bash
ADMIN_WHITELIST_IP=127.0.0.1 docker compose up -d
```
