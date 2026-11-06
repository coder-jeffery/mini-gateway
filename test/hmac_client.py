"""HMAC client for POST /admin/gw/v1 (matches admin_api_v1.lua)."""

from __future__ import annotations

import hashlib
import hmac
import json
import os
import time
import uuid
from typing import Any
from urllib.error import HTTPError
from urllib.request import Request, urlopen

DEFAULT_SECRET = b"admin-secret-2026"
DEFAULT_URL = "http://127.0.0.1:8080/admin/gw/v1"


def admin_secret() -> bytes:
    raw = os.environ.get("GATEWAY_ADMIN_SECRET", "admin-secret-2026")
    return raw.encode("utf-8")


def admin_url() -> str:
    return os.environ.get("ADMIN_GW_V1_URL", DEFAULT_URL)


def sign_fields(ts: int | None = None, nonce: str | None = None) -> tuple[int, str, str]:
    ts = int(time.time()) if ts is None else ts
    nonce = str(uuid.uuid4()) if nonce is None else nonce
    raw = f"{ts}:{nonce}".encode("utf-8")
    sign = hmac.new(admin_secret(), raw, hashlib.sha256).hexdigest()
    return ts, nonce, sign


def signed_payload(action: str, *, ts: int | None = None, nonce: str | None = None, sign: str | None = None, **fields: Any) -> dict[str, Any]:
    ts_val, nonce_val, sign_val = sign_fields(ts=ts, nonce=nonce)
    if sign is not None:
        sign_val = sign
    body: dict[str, Any] = {
        "ts": ts_val,
        "nonce": nonce_val,
        "sign": sign_val,
        "action": action,
    }
    body.update(fields)
    return body


def post_admin_v1(body: dict[str, Any], url: str | None = None) -> tuple[int, dict[str, Any]]:
    target = url or admin_url()
    data = json.dumps(body).encode("utf-8")
    req = Request(
        target,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urlopen(req, timeout=10) as resp:
            payload = json.loads(resp.read().decode())
            return resp.status, payload
    except HTTPError as e:
        raw = e.read().decode()
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            payload = {"ok": False, "msg": raw}
        return e.code, payload
