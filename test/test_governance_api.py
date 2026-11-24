#!/usr/bin/env python3
"""Smoke: governance list APIs (uri_block_list, admin_role_get)."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from hmac_client import post_admin_v1, signed_payload


def main() -> None:
    st, data = post_admin_v1(signed_payload("uri_block_list"))
    if st != 200 or not data.get("ok"):
        raise SystemExit(f"uri_block_list: {st} {data}")

    st, data = post_admin_v1(signed_payload("admin_role_get"))
    if st != 200 or not data.get("ok") or not data.get("role"):
        raise SystemExit(f"admin_role_get: {st} {data}")

    print("test_governance_api: passed")


if __name__ == "__main__":
    main()