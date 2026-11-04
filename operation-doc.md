
Operations reference (admin API uses HMAC, not `admin_secret` in JSON).

Sign string: `HMAC-SHA256(secret, "{ts}:{nonce}")` as **hex** (same as Python `hmac.hexdigest()`).
Required fields on every request: `ts`, `nonce`, `sign`, `action`.

Quick call (from repo root):

```bash
chmod +x test/admin_call.sh
./test/admin_call.sh upsert_apikey '{"api_key":"abc123","limit":20,"window":30}'
./test/admin_call.sh whitelist_list
```

Or Python: `python test/test.py`

---

Case 1: Create / update api key `abc123`, 20 requests per 30s

```bash
SECRET="admin-secret-2026"
TS=$(date +%s)
NONCE=$(uuidgen | tr '[:upper:]' '[:lower:]')
SIGN=$(printf '%s' "${TS}:${NONCE}" | openssl dgst -sha256 -hmac "$SECRET" | awk '{print $NF}')

curl -sS -X POST http://127.0.0.1:8080/admin/gw \
  -H "Content-Type: application/json" \
  -d "{
    \"ts\": ${TS},
    \"nonce\": \"${NONCE}\",
    \"sign\": \"${SIGN}\",
    \"action\": \"upsert_apikey\",
    \"api_key\": \"abc123\",
    \"limit\": 20,
    \"window\": 30
  }"
```

Case 2: Add IP to business whitelist — same signing; body includes `"action":"whitelist_add","ip":"127.0.0.1"`.

Case 3: Remove whitelist IP — `"action":"whitelist_del","ip":"127.0.0.1"`.

Case 4: List whitelist — `"action":"whitelist_list"` (no extra fields).

Case 5: Delete api key — `"action":"del_apikey","api_key":"abc123"`.

Bootstrap admin whitelist on start (loopback + host LAN IP + common Docker gateway IPs):

```bash
./install.sh
```

Manual override:

```bash
ADMIN_WHITELIST_IPS=127.0.0.1,192.168.1.50 docker compose up -d
```

Common errors:

- `missing sign params` — use `ts`, `nonce`, `sign` instead of `admin_secret`.
- `forbidden: ip not in admin whitelist` — `SADD admin:whitelist:ip <your-ip>` or set `ADMIN_WHITELIST_IP` on compose up.
- `invalid signature` — sign must be hex over exactly `{ts}:{nonce}` with secret `admin-secret-2026`.
