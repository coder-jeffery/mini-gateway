import hmac
import hashlib
import time
import uuid
import json
import requests

secret = b"admin-secret-2026"
ts = int(time.time())
nonce = str(uuid.uuid4())
raw = f"{ts}:{nonce}".encode("utf-8")
sign = hmac.new(secret, raw, hashlib.sha256).hexdigest()

payload = {
    "ts": ts,
    "nonce": nonce,
    "sign": sign,
    "action": "whitelist_list"
}
r = requests.post("http://127.0.0.1:8080/admin/gw", json=payload)
print(r.json())
