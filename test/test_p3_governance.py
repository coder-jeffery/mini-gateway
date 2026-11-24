#!/usr/bin/env python3
"""P3-2 rewrite + P3-3 RBAC smoke tests."""

from __future__ import annotations

import sys
import uuid
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).resolve().parent))

from hmac_client import post_admin_v1, signed_payload

GATEWAY = "http://127.0.0.1:8080"
API_KEY = "mini-key"


def gateway_get(path: str) -> tuple[int, dict[str, str]]:
    req = Request(GATEWAY + path, headers={"X-Api-Key": API_KEY}, method="GET")
    try:
        with urlopen(req, timeout=10) as resp:
            return resp.status, {k.lower(): v for k, v in resp.headers.items()}
    except HTTPError as e:
        return e.code, {k.lower(): v for k, v in e.headers.items()}


def test_rbac_read_only_cannot_delete() -> None:
    post_admin_v1(signed_payload("admin_role_set", role="full_admin"))
    post_admin_v1(signed_payload("admin_role_set", role="read_only"))
    body = signed_payload("del_apikey", api_key="mini-key")
    status, data = post_admin_v1(body)
    if status != 403:
        raise SystemExit(f"read_only should not del_apikey, got {status} {data}")
    post_admin_v1(signed_payload("admin_role_set", role="full_admin"))


def test_rewrite_header() -> None:
    name = "rw" + uuid.uuid4().hex[:8]
    rule = signed_payload(
        "rewrite_rule_set",
        name=name,
        match_prefix="/p3-rewrite",
        headers={"X-P3-Rewrite": "ok"},
    )
    st, data = post_admin_v1(rule)
    if st != 200 or not data.get("ok"):
        raise SystemExit(f"rewrite_rule_set failed: {st} {data}")

    _, hdrs = gateway_get("/p3-rewrite/demo")
    if hdrs.get("x-gateway-rewrite-applied") != name:
        raise SystemExit(f"expected rewrite applied header, got {hdrs}")

    post_admin_v1(signed_payload("rewrite_rule_del", name=name))


def main() -> None:
    test_rbac_read_only_cannot_delete()
    test_rewrite_header()
    print("test_p3_governance: passed")


if __name__ == "__main__":
    main()