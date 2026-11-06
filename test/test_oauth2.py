#!/usr/bin/env python3
"""Smoke tests for OAuth2 Bearer auth (HS256 dev secret)."""

from __future__ import annotations

import hashlib
import hmac
import json
import os
import time
import urllib.error
import urllib.request
import base64
import uuid


GATEWAY_URL = os.environ.get("GATEWAY_URL", "http://127.0.0.1:8080/").rstrip("/") + "/"
SECRET = os.environ.get("OAUTH2_JWT_SECRET", "oauth2-dev-secret")


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def make_hs256_jwt(payload: dict, secret: str) -> str:
    header = b64url(json.dumps({"alg": "HS256", "typ": "JWT"}, separators=(",", ":")).encode())
    body = b64url(json.dumps(payload, separators=(",", ":")).encode())
    signing_input = f"{header}.{body}".encode()
    sig = hmac.new(secret.encode(), signing_input, hashlib.sha256).digest()
    return f"{header}.{body}.{b64url(sig)}"


def call_bearer(token: str | None) -> tuple[int, dict]:
    headers = {"Accept": "application/json"}
    if token is not None:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(GATEWAY_URL, headers=headers, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.status, json.loads(resp.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        try:
            data = json.loads(body)
        except json.JSONDecodeError:
            data = {"msg": body}
        return e.code, data


def test_bearer_ok() -> None:
    now = int(time.time())
    payload: dict = {
        "sub": f"user-{uuid.uuid4()}",
        "exp": now + 300,
    }
    issuer = os.environ.get("OAUTH2_ISSUER", "").strip()
    if issuer:
        payload["iss"] = issuer
    token = make_hs256_jwt(payload, SECRET)
    status, data = call_bearer(token)
    print("bearer OK:", status, data)
    assert status == 200, data


def test_bearer_bad_sig() -> None:
    now = int(time.time())
    token = make_hs256_jwt({"sub": "x", "exp": now + 300}, SECRET) + "x"
    status, data = call_bearer(token)
    print("bad sig:", status, data)
    assert status == 401, data


def test_bearer_expired() -> None:
    skew = int(os.environ.get("OAUTH2_CLOCK_SKEW_SEC", "60"))
    token = make_hs256_jwt({"sub": "x", "exp": int(time.time()) - skew - 30}, SECRET)
    status, data = call_bearer(token)
    print("expired:", status, data)
    assert status == 401, data


if __name__ == "__main__":
    if os.environ.get("GATEWAY_AUTH_MODE", "both") not in ("bearer", "both"):
        raise SystemExit(
            "Set GATEWAY_AUTH_MODE=bearer or both on the gateway and re-run "
            "(e.g. GATEWAY_AUTH_MODE=both OAUTH2_JWT_SECRET=oauth2-dev-secret ./start-gateway.sh)"
        )
    test_bearer_ok()
    test_bearer_bad_sig()
    test_bearer_expired()
    print("all oauth2 tests passed")
