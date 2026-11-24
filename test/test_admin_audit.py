#!/usr/bin/env python3
"""P1-4: admin mutation audit via audit_list."""

from __future__ import annotations

import sys
import time
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from hmac_client import post_admin_v1, signed_payload


def test_audit_after_upsert() -> None:
    key = "audit-" + uuid.uuid4().hex[:12]
    body = signed_payload("upsert_apikey", api_key=key, limit=10, window=60)
    status, data = post_admin_v1(body)
    if status != 200 or not data.get("ok"):
        raise SystemExit(f"upsert failed: {status} {data}")

    time.sleep(0.3)

    list_body = signed_payload("audit_list", limit=20)
    status, data = post_admin_v1(list_body)
    if status != 200 or not data.get("ok"):
        raise SystemExit(f"audit_list failed: {status} {data}")

    events = data.get("events") or []
    hit = None
    for ev in events:
        if ev.get("action") == "upsert_apikey":
            detail = ev.get("detail") or {}
            if detail.get("api_key") and key[:4] in str(detail.get("api_key")):
                hit = ev
                break
    if not hit:
        raise SystemExit(f"no upsert_apikey audit event for {key}; events={events}")

    if "mini" in str(hit.get("detail", {}).get("api_key", "")):
        raise SystemExit("audit detail must not contain full api_key")

    del_body = signed_payload("del_apikey", api_key=key)
    post_admin_v1(del_body)


def main() -> None:
    test_audit_after_upsert()
    print("test_admin_audit: passed")


if __name__ == "__main__":
    main()