import hmac
import hashlib
import os
import time
import uuid
import json
import requests

ADMIN_SECRET = b"admin-secret-2026"
BASE_URL = os.environ.get("ADMIN_GW_V1_URL", "http://127.0.0.1:8080/admin/gw/v1")


def signed_payload(action: str, **fields) -> dict:
    ts = int(time.time())
    nonce = str(uuid.uuid4())
    raw = f"{ts}:{nonce}".encode("utf-8")
    sign = hmac.new(ADMIN_SECRET, raw, hashlib.sha256).hexdigest()
    body = {"ts": ts, "nonce": nonce, "sign": sign, "action": action}
    body.update(fields)
    return body


if __name__ == "__main__":
    payload = signed_payload("hmac_test")
    r = requests.post(BASE_URL, json=payload)
    print("hmac_test", r.status_code, r.json())
