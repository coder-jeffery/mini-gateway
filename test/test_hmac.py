#!/usr/bin/env python3
"""Smoke tests for HMAC auth on /admin/gw/v1."""

from __future__ import annotations

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from hmac_client import admin_url, post_admin_v1, signed_payload


def test_hmac_ok() -> None:
    body = signed_payload("hmac_test")
    status, data = post_admin_v1(body)
    print("hmac_test OK:", status, data)
    if status != 200 or not data.get("ok"):
        raise SystemExit(f"expected 200 ok=true, got {status} {data}")
    if data.get("msg") != "hmac verified":
        raise SystemExit(f"unexpected msg: {data}")


def test_hmac_bad_sign() -> None:
    body = signed_payload("hmac_test", sign="deadbeef")
    status, data = post_admin_v1(body)
    print("bad sign:", status, data)
    if status != 403 or data.get("msg") != "invalid signature":
        raise SystemExit(f"expected 403 invalid signature, got {status} {data}")


def test_hmac_expired_ts() -> None:
    old_ts = int(time.time()) - 120
    body = signed_payload("hmac_test", ts=old_ts)
    status, data = post_admin_v1(body)
    print("expired ts:", status, data)
    if status != 403 or data.get("msg") != "signature expired":
        raise SystemExit(f"expected 403 signature expired, got {status} {data}")


def main() -> None:
    print("URL:", admin_url())
    test_hmac_ok()
    test_hmac_bad_sign()
    test_hmac_expired_ts()
    print("all hmac tests passed")


if __name__ == "__main__":
    main()
