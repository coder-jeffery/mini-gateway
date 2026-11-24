#!/usr/bin/env python3
"""P4 integration smoke: warmup header + business HMAC when configured."""

from __future__ import annotations

import hashlib
import hmac
import os
import sys
import time
import uuid
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).resolve().parent))

from hmac_client import post_admin_v1, signed_payload

GATEWAY = os.environ.get("GATEWAY_URL", "http://127.0.0.1:8080")
BIZ_SECRET = os.environ.get("GATEWAY_BUSINESS_HMAC_SECRET", "business-hmac-dev")


def gateway_get(path: str, api_key: str, extra: dict[str, str] | None = None) -> tuple[int, dict[str, str]]:
    hdrs = {"X-Api-Key": api_key}
    if extra:
        hdrs.update(extra)
    req = Request(GATEWAY + path, headers=hdrs, method="GET")
    try:
        with urlopen(req, timeout=10) as resp:
            return resp.status, {k.lower(): v for k, v in resp.headers.items()}
    except HTTPError as e:
        return e.code, {k.lower(): v for k, v in e.headers.items()}


def biz_sign(api_key: str, uri: str, ts: int) -> str:
    raw = f"{ts}:GET:{uri}:{api_key}".encode()
    return hmac.new(BIZ_SECRET.encode(), raw, hashlib.sha256).hexdigest()


def test_warmup_header() -> None:
    key = "warm-" + uuid.uuid4().hex[:10]
    body = signed_payload(
        "upsert_apikey",
        api_key=key,
        limit=100,
        window=60,
        warmup_start_limit=5,
        warmup_ramp_sec=3600,
    )
    st, data = post_admin_v1(body)
    if st != 200:
        raise SystemExit(f"upsert: {st} {data}")
    _, hdrs = gateway_get("/", key)
    warm = hdrs.get("x-ratelimit-warmup-limit")
    if not warm:
        raise SystemExit(f"missing warmup header: {hdrs}")
    if int(warm) > 100:
        raise SystemExit(f"warmup limit should be <= 100, got {warm}")
    post_admin_v1(signed_payload("del_apikey", api_key=key))


def test_business_hmac() -> None:
    if os.environ.get("GATEWAY_BUSINESS_HMAC_MODE", "optional") == "off":
        print("skip business hmac: mode off")
        return
    key = "bh-" + uuid.uuid4().hex[:10]
    post_admin_v1(
        signed_payload(
            "upsert_apikey",
            api_key=key,
            limit=50,
            window=60,
            hmac_required=1,
        )
    )
    code, _ = gateway_get("/", key)
    if code != 401:
        raise SystemExit(f"expected 401 without biz hmac, got {code}")

    ts = int(time.time())
    sig = biz_sign(key, "/", ts)
    code, _ = gateway_get(
        "/",
        key,
        {"X-Business-Ts": str(ts), "X-Business-Sign": sig},
    )
    if code not in (200, 502, 503):
        raise SystemExit(f"expected pass auth with biz hmac, got {code}")

    post_admin_v1(signed_payload("del_apikey", api_key=key))


def main() -> None:
    test_warmup_header()
    test_business_hmac()
    print("test_p4_extensions: passed")


if __name__ == "__main__":
    main()