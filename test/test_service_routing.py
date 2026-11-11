#!/usr/bin/env python3
"""Smoke tests for Service routing and per-Service CORS."""

from __future__ import annotations

import json
import os
import sys
import uuid
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))

from hmac_client import post_admin_v1, signed_payload

BASE_URL = os.environ.get("GATEWAY_URL", "http://127.0.0.1:8080")
API_KEY = os.environ.get("GATEWAY_TEST_API_KEY", "mini-key")
HTTPBIN_BASE = os.environ.get("SERVICE_TEST_UPSTREAM", "https://httpbin.org/anything")


def admin(action: str, **fields: Any) -> tuple[int, dict[str, Any]]:
    status, data = post_admin_v1(signed_payload(action, **fields))
    print(action, status, data)
    return status, data


def gateway_headers(
    path: str,
    *,
    method: str = "GET",
    headers: dict[str, str] | None = None,
) -> tuple[int, dict[str, str]]:
    req = urllib.request.Request(
        f"{BASE_URL}{path}",
        method=method,
        headers=headers or {},
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as response:
            response.read()
            return response.status, dict(response.headers.items())
    except urllib.error.HTTPError as error:
        error.read()
        return error.code, dict(error.headers.items())


def gateway_json(
    path: str,
    *,
    method: str = "GET",
    headers: dict[str, str] | None = None,
) -> tuple[int, dict[str, Any], dict[str, str]]:
    req = urllib.request.Request(
        f"{BASE_URL}{path}",
        method=method,
        headers=headers or {},
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as response:
            body = json.loads(response.read().decode())
            return response.status, body, dict(response.headers.items())
    except urllib.error.HTTPError as error:
        raw = error.read().decode()
        try:
            body = json.loads(raw)
        except json.JSONDecodeError:
            body = {"raw": raw}
        return error.code, body, dict(error.headers.items())


def header(headers: dict[str, str], name: str) -> str | None:
    expected = name.lower()
    return next((value for key, value in headers.items() if key.lower() == expected), None)


def delete_service(service_id: str) -> None:
    admin("service_delete", id=service_id)


def test_longest_prefix_and_fallback() -> None:
    suffix = uuid.uuid4().hex[:8]
    base = f"/api-{suffix}"
    child = f"{base}/orders"
    created: list[str] = []
    try:
        status, data = admin(
            "service_create",
            name=f"api-{suffix}",
            path_prefix=f"{base}/",
            upstream_url=HTTPBIN_BASE,
            cors_enabled=0,
            cors_allow_origins="",
            cors_allow_methods="GET,OPTIONS",
            cors_allow_headers="",
            cors_expose_headers="",
            cors_max_age=0,
            cors_allow_credentials=0,
        )
        assert status == 201, data
        parent_id = data["service"]["id"]
        created.append(parent_id)

        status, data = admin(
            "service_create",
            name=f"orders-{suffix}",
            path_prefix=f"{child}/",
            upstream_url=HTTPBIN_BASE,
            cors_enabled=0,
            cors_allow_origins="",
            cors_allow_methods="GET,OPTIONS",
            cors_allow_headers="",
            cors_expose_headers="",
            cors_max_age=0,
            cors_allow_credentials=0,
        )
        assert status == 201, data
        child_id = data["service"]["id"]
        created.append(child_id)

        detail_path = f"{child}/42?detail=1"
        status, body, _ = gateway_json(
            detail_path,
            headers={"X-Api-Key": API_KEY},
        )
        assert status == 200, (status, body)
        assert body["url"].endswith(detail_path), body

        boundary_path = f"{base}/orders-v2"
        status, body, _ = gateway_json(
            boundary_path,
            headers={"X-Api-Key": API_KEY},
        )
        assert status == 200, (status, body)
        assert boundary_path in body["url"], body
        assert f"{child}/" not in body["url"], body

        unmatched = f"/no-service-{suffix}"
        status, body, _ = gateway_json(
            unmatched,
            headers={"X-Api-Key": API_KEY},
        )
        assert status == 200, (status, body)
        assert body.get("url", "").endswith("/get"), body
    finally:
        for sid in created:
            delete_service(sid)


def test_per_service_cors() -> None:
    suffix = uuid.uuid4().hex[:8]
    orders_path = f"/api/orders-{suffix}"
    users_path = f"/api/users-{suffix}"
    allowed = "https://app.example.com"
    created: list[str] = []
    try:
        status, data = admin(
            "service_create",
            name=f"orders-{suffix}",
            path_prefix=f"{orders_path}/",
            upstream_url=HTTPBIN_BASE,
            cors_enabled=1,
            cors_allow_origins=allowed,
            cors_allow_methods="GET,OPTIONS",
            cors_allow_headers="Content-Type,Authorization,X-Api-Key",
            cors_expose_headers="X-Request-Id",
            cors_max_age=600,
            cors_allow_credentials=0,
        )
        assert status == 201, data
        created.append(data["service"]["id"])

        status, data = admin(
            "service_create",
            name=f"users-{suffix}",
            path_prefix=f"{users_path}/",
            upstream_url=HTTPBIN_BASE,
            cors_enabled=1,
            cors_allow_origins="https://other.example.com",
            cors_allow_methods="GET,OPTIONS",
            cors_allow_headers="Content-Type",
            cors_expose_headers="",
            cors_max_age=60,
            cors_allow_credentials=0,
        )
        assert status == 201, data
        created.append(data["service"]["id"])

        status, hdrs = gateway_headers(
            orders_path,
            method="OPTIONS",
            headers={
                "Origin": allowed,
                "Access-Control-Request-Method": "GET",
                "Access-Control-Request-Headers": "x-api-key",
            },
        )
        assert status == 204, (status, hdrs)
        assert header(hdrs, "Access-Control-Allow-Origin") == allowed, hdrs

        status, hdrs = gateway_headers(
            users_path,
            method="OPTIONS",
            headers={
                "Origin": allowed,
                "Access-Control-Request-Method": "GET",
            },
        )
        assert status == 403, (status, hdrs)

        status, _, hdrs = gateway_json(
            orders_path,
            headers={"Origin": allowed},
        )
        assert status == 401, (status, hdrs)
        assert header(hdrs, "Access-Control-Allow-Origin") == allowed, hdrs
    finally:
        for sid in created:
            delete_service(sid)


def main() -> None:
    print("URL:", BASE_URL)
    test_longest_prefix_and_fallback()
    test_per_service_cors()
    print("all service routing tests passed")


if __name__ == "__main__":
    main()
