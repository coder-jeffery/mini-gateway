import hmac
import hashlib
import time
import uuid
import json
import requests

ADMIN_SECRET = b"admin-secret-2026"
BASE_URL = "http://127.0.0.1:8080/admin/gw"


def signed_payload(action: str, **fields) -> dict:
    ts = int(time.time())
    nonce = str(uuid.uuid4())
    raw = f"{ts}:{nonce}".encode("utf-8")
    sign = hmac.new(ADMIN_SECRET, raw, hashlib.sha256).hexdigest()
    body = {"ts": ts, "nonce": nonce, "sign": sign, "action": action}
    body.update(fields)
    return body


if __name__ == "__main__":
    payload = signed_payload(
        "upsert_apikey",
        api_key="abc123",
        limit=20,
        window=30,
    )
    r = requests.post(BASE_URL, json=payload)
    print(r.status_code, r.json())
