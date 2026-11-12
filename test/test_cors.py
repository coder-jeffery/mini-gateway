#!/usr/bin/env python3
"""Smoke tests for configurable CORS on business routes."""

from __future__ import annotations

import os
import urllib.error
import urllib.request


BASE_URL = os.environ.get("GATEWAY_URL", "http://127.0.0.1:8080")
ALLOWED_ORIGIN = os.environ.get("CORS_TEST_ORIGIN", "http://localhost:3000")


def request(
    path: str,
    *,
    method: str = "GET",
    headers: dict[str, str] | None = None,
) -> tuple[int, dict[str, str]]:
    req = urllib.request.Request(
        f"{BASE_URL}{path}", method=method, headers=headers or {}
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            return response.status, dict(response.headers.items())
    except urllib.error.HTTPError as error:
        return error.code, dict(error.headers.items())


def header(headers: dict[str, str], name: str) -> str | None:
    expected = name.lower()
    return next((value for key, value in headers.items() if key.lower() == expected), None)


def test_allowed_preflight() -> None:
    status, headers = request(
        "/",
        method="OPTIONS",
        headers={
            "Origin": ALLOWED_ORIGIN,
            "Access-Control-Request-Method": "GET",
            "Access-Control-Request-Headers": "authorization,x-api-key",
        },
    )
    assert status == 204, (status, headers)
    assert header(headers, "Access-Control-Allow-Origin") == ALLOWED_ORIGIN
    assert "GET" in (header(headers, "Access-Control-Allow-Methods") or "")
    assert "Authorization" in (
        header(headers, "Access-Control-Allow-Headers") or ""
    )
    assert "Origin" in (header(headers, "Vary") or "")


def test_disallowed_preflight() -> None:
    status, headers = request(
        "/",
        method="OPTIONS",
        headers={
            "Origin": "https://not-allowed.example",
            "Access-Control-Request-Method": "GET",
        },
    )
    assert status == 403, (status, headers)
    assert header(headers, "Access-Control-Allow-Origin") is None


def test_auth_error_has_cors_headers() -> None:
    status, headers = request("/", headers={"Origin": ALLOWED_ORIGIN})
    assert status == 401, (status, headers)
    assert header(headers, "Access-Control-Allow-Origin") == ALLOWED_ORIGIN
    assert "X-Request-Id" in (
        header(headers, "Access-Control-Expose-Headers") or ""
    )


def test_admin_route_has_no_cors_headers() -> None:
    status, headers = request(
        "/admin/gw/v1",
        method="POST",
        headers={"Origin": ALLOWED_ORIGIN, "Content-Type": "application/json"},
    )
    assert status == 400, (status, headers)
    assert header(headers, "Access-Control-Allow-Origin") is None


if __name__ == "__main__":
    test_allowed_preflight()
    test_disallowed_preflight()
    test_auth_error_has_cors_headers()
    test_admin_route_has_no_cors_headers()
    print("all CORS tests passed")
