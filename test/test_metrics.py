#!/usr/bin/env python3
"""Smoke test for GET /metrics (Prometheus text format)."""

from __future__ import annotations

import os
import re
import urllib.request

GATEWAY = os.environ.get("GATEWAY_URL", "http://127.0.0.1:8080").rstrip("/")
METRICS_URL = f"{GATEWAY}/metrics"


def test_metrics_endpoint() -> None:
    with urllib.request.urlopen(METRICS_URL, timeout=10) as resp:
        body = resp.read().decode()
    assert resp.status == 200, resp.status
    assert "text/plain" in resp.headers.get("Content-Type", "")
    assert "gateway_http_requests_total" in body
    assert re.search(r"^# TYPE gateway_http_requests_total counter$", body, re.M)
    assert re.search(r"^gateway_circuit_breaker_open \d+$", body, re.M)
    print("metrics OK, sample lines:")
    for line in body.splitlines()[:8]:
        print(" ", line)


if __name__ == "__main__":
    test_metrics_endpoint()
    print("metrics test passed")