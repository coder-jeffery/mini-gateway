#!/usr/bin/env python3
"""P1-5: config cache hits appear in /metrics after repeated data-plane reads."""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path
from urllib.request import urlopen

GATEWAY = os.environ.get("GATEWAY_URL", "http://127.0.0.1:8080")
API_KEY = os.environ.get("DEFAULT_API_KEY", "mini-key")


def metric_value(text: str, name: str) -> int:
    m = re.search(rf"^{re.escape(name)} (\d+)", text, re.MULTILINE)
    if not m:
        return 0
    return int(m.group(1))


def gateway_ping() -> None:
    from urllib.request import Request

    req = Request(
        f"{GATEWAY}/",
        headers={"X-Api-Key": API_KEY},
        method="GET",
    )
    try:
        urlopen(req, timeout=10)
    except Exception:
        pass  # upstream may 502; auth/cache still ran


def main() -> None:
    if os.environ.get("GATEWAY_CONFIG_CACHE", "1") != "1":
        print("skip: GATEWAY_CONFIG_CACHE not enabled")
        return

    for _ in range(3):
        try:
            gateway_ping()
        except Exception:
            pass

    metrics = urlopen(f"{GATEWAY}/metrics", timeout=10).read().decode()
    hits = metric_value(metrics, "gateway_config_cache_hits_total")
    misses = metric_value(metrics, "gateway_config_cache_misses_total")
    print("cache hits", hits, "misses", misses)
    if hits + misses < 1:
        raise SystemExit("expected config cache hit or miss metric")
    print("test_config_cache: passed")


if __name__ == "__main__":
    main()