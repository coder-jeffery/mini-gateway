#!/usr/bin/env python3
"""P3-1 gray tag + P3-4 config snapshot smoke."""

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


def get_headers(path: str = "/") -> dict[str, str]:
    req = Request(GATEWAY + path, headers={"X-Api-Key": API_KEY}, method="GET")
    try:
        with urlopen(req, timeout=10) as resp:
            return {k.lower(): v for k, v in resp.headers.items()}
    except HTTPError as e:
        return {k.lower(): v for k, v in e.headers.items()}


def test_gray_tag() -> None:
    name = "g" + uuid.uuid4().hex[:8]
    body = signed_payload(
        "gray_rule_set",
        name=name,
        percent=100,
        tag="canary",
        match_api_key=API_KEY,
    )
    st, data = post_admin_v1(body)
    if st != 200 or not data.get("ok"):
        raise SystemExit(f"gray_rule_set: {st} {data}")

    hdrs = get_headers("/")
    tag = hdrs.get("x-gray-tag")
    if tag != "canary":
        raise SystemExit(f"expected X-Gray-Tag canary, got {tag!r} headers={hdrs}")

    post_admin_v1(signed_payload("gray_rule_del", name=name))


def test_snapshot_roundtrip() -> None:
    snap_key = "snap-" + uuid.uuid4().hex[:10]
    post_admin_v1(signed_payload("upsert_apikey", api_key=snap_key, limit=5, window=30))
    st, data = post_admin_v1(signed_payload("config_snapshot_save"))
    if st != 200 or not data.get("ok"):
        raise SystemExit(f"snapshot save: {st} {data}")

    post_admin_v1(signed_payload("del_apikey", api_key=snap_key))
    g_st, g_data = post_admin_v1(signed_payload("get_apikey", api_key=snap_key))
    if g_st != 404:
        raise SystemExit(f"expected key gone before restore, got {g_st}")

    st, data = post_admin_v1(signed_payload("config_snapshot_restore"))
    if st != 200 or not data.get("ok"):
        raise SystemExit(f"snapshot restore: {st} {data}")

    g_st, g_data = post_admin_v1(signed_payload("get_apikey", api_key=snap_key))
    if g_st != 200:
        raise SystemExit(f"expected key after restore, got {g_st} {g_data}")

    post_admin_v1(signed_payload("del_apikey", api_key=snap_key))


def main() -> None:
    test_gray_tag()
    test_snapshot_roundtrip()
    print("test_gray_snapshot: passed")


if __name__ == "__main__":
    main()