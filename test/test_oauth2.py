#!/usr/bin/env python3
"""Smoke tests for OAuth2 Bearer auth (HS256 dev secret)."""

from __future__ import annotations

import os
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(__file__))
from jwt_client import build_case, gateway_url


def call_bearer(token: str | None) -> tuple[int, dict]:
    headers = {"Accept": "application/json"}
    if token is not None:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(gateway_url(), headers=headers, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.status, __import__("json").loads(resp.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        try:
            data = __import__("json").loads(body)
        except __import__("json").JSONDecodeError:
            data = {"msg": body}
        return e.code, data


def test_bearer_ok() -> None:
    _, _, token = build_case("valid")
    status, data = call_bearer(token)
    print("bearer OK:", status, data)
    assert status == 200, data


def test_bearer_bad_sig() -> None:
    _, _, token = build_case("bad_sig")
    status, data = call_bearer(token)
    print("bad sig:", status, data)
    assert status == 401, data


def test_bearer_expired() -> None:
    _, _, token = build_case("expired")
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
