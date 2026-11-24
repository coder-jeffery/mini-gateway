#!/usr/bin/env python3
"""P2 policy smoke: URI blocklist + route quota (needs gateway on 8080)."""

from __future__ import annotations

import json
import os
import sys
import uuid
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).resolve().parent))

from hmac_client import post_admin_v1, signed_payload

GATEWAY = os.environ.get("GATEWAY_URL", "http://127.0.0.1:8080")
API_KEY = os.environ.get("DEFAULT_API_KEY", "mini-key")


def gateway_get(path: str, headers: dict | None = None) -> tuple[int, str]:
    hdrs = {"X-Api-Key": API_KEY}
    if headers:
        hdrs.update(headers)
    req = Request(GATEWAY + path, headers=hdrs, method="GET")
    try:
        with urlopen(req, timeout=10) as resp:
            return resp.status, resp.read().decode()
    except HTTPError as e:
        return e.code, e.read().decode()


def test_uri_block() -> None:
    blocked = "/p2-block-" + uuid.uuid4().hex[:8]
    add = signed_payload("uri_block_add", prefix=blocked)
    st, data = post_admin_v1(add)
    if st != 200 or not data.get("ok"):
        raise SystemExit(f"uri_block_add: {st} {data}")

    code, _ = gateway_get(blocked + "/x")
    if code != 403:
        raise SystemExit(f"expected 403 on blocked uri, got {code}")

    rm = signed_payload("uri_block_del", prefix=blocked)
    post_admin_v1(rm)


def test_route_quota() -> None:
    prefix = "/p2-quota-" + uuid.uuid4().hex[:6]
    setq = signed_payload("route_quota_set", prefix=prefix, limit=1, window=60)
    st, data = post_admin_v1(setq)
    if st != 200 or not data.get("ok"):
        raise SystemExit(f"route_quota_set: {st} {data}")

    c1, _ = gateway_get(prefix)
    c2, body = gateway_get(prefix)
    if c1 not in (200, 502, 503):
        raise SystemExit(f"first request unexpected {c1}")
    if c2 != 429:
        raise SystemExit(f"expected 429 on route quota, got {c2} body={body[:200]}")

    rm = signed_payload("route_quota_del", prefix=prefix)
    post_admin_v1(rm)


def test_ua_block() -> None:
    pattern = "P2BadBot/" + uuid.uuid4().hex[:6]
    add = signed_payload("ua_block_add", pattern=pattern)
    st, data = post_admin_v1(add)
    if st != 200:
        raise SystemExit(f"ua_block_add: {st} {data}")

    code, _ = gateway_get("/", headers={"User-Agent": pattern + " 1.0"})
    if code != 403:
        raise SystemExit(f"expected 403 for blocked UA, got {code}")

    rm = signed_payload("ua_block_del", pattern=pattern)
    post_admin_v1(rm)


def main() -> None:
    test_uri_block()
    test_route_quota()
    test_ua_block()
    print("test_policy_p2: passed")


if __name__ == "__main__":
    main()