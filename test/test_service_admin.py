#!/usr/bin/env python3
"""HMAC smoke tests for Service CRUD and validation."""

from __future__ import annotations

import sys
import uuid
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))

from hmac_client import admin_url, post_admin_v1, signed_payload


def call(action: str, **fields: Any) -> tuple[int, dict[str, Any]]:
    status, data = post_admin_v1(signed_payload(action, **fields))
    print(action, status, data)
    return status, data


def service_fields(suffix: str, **overrides: Any) -> dict[str, Any]:
    fields: dict[str, Any] = {
        "name": f"orders-{suffix}",
        "path_prefix": f"/api/orders-{suffix}/",
        "upstream_url": "http://orders:8080",
        "cors_enabled": 1,
        "cors_allow_origins": "https://app.example.com",
        "cors_allow_methods": "GET,POST,OPTIONS",
        "cors_allow_headers": "Content-Type,Authorization,X-Api-Key",
        "cors_expose_headers": "X-Request-Id",
        "cors_max_age": 600,
        "cors_allow_credentials": 0,
    }
    fields.update(overrides)
    return fields


def expect(status: int, data: dict[str, Any], wanted: int) -> None:
    assert status == wanted, data


def test_service_crud_and_conflicts() -> None:
    suffix = uuid.uuid4().hex[:10]
    created_ids: list[str] = []
    try:
        status, data = call("service_create", **service_fields(suffix))
        expect(status, data, 201)
        service = data["service"]
        service_id = service["id"]
        created_ids.append(service_id)
        assert service["path_prefix"] == f"/api/orders-{suffix}", data
        assert service["cors_enabled"] is True, data
        assert service["cors_allow_credentials"] is False, data

        status, data = call("service_get", id=service_id)
        expect(status, data, 200)
        assert data["service"]["name"] == f"orders-{suffix}", data

        status, data = call("service_list")
        expect(status, data, 200)
        assert any(item["id"] == service_id for item in data["services"]), data

        status, data = call(
            "service_update",
            id=service_id,
            name=f"orders-updated-{suffix}",
            path_prefix=f"/api/orders-updated-{suffix}/",
            upstream_url="https://orders:8443",
            cors_enabled=False,
            cors_allow_origins="https://admin.example.com",
            cors_allow_methods="GET,OPTIONS",
            cors_allow_headers="Authorization",
            cors_expose_headers="",
            cors_max_age=120,
            cors_allow_credentials=True,
        )
        expect(status, data, 200)
        assert data["service"]["id"] == service_id, data
        assert data["service"]["path_prefix"] == f"/api/orders-updated-{suffix}", data

        status, data = call("service_get", id=service_id)
        expect(status, data, 200)
        assert data["service"]["name"] == f"orders-updated-{suffix}", data
        assert data["service"]["cors_allow_credentials"] is True, data

        conflict = service_fields(
            f"conflict-{suffix}",
            name=f"orders-updated-{suffix}",
        )
        status, data = call("service_create", **conflict)
        expect(status, data, 409)

        conflict = service_fields(
            f"other-{suffix}",
            path_prefix=f"/api/orders-updated-{suffix}/",
        )
        status, data = call("service_create", **conflict)
        expect(status, data, 409)

        status, data = call("service_delete", id=service_id)
        expect(status, data, 200)
        assert data.get("msg"), data
        created_ids.remove(service_id)

        status, data = call("service_get", id=service_id)
        expect(status, data, 404)
    finally:
        for service_id in created_ids:
            call("service_delete", id=service_id)


def test_service_validation() -> None:
    suffix = uuid.uuid4().hex[:10]
    invalid_cases = [
        service_fields(f"path-{suffix}", path_prefix="api/orders"),
        service_fields(f"url-query-{suffix}", upstream_url="https://orders:8443/path?q=1"),
        service_fields(f"url-scheme-{suffix}", upstream_url="ftp://orders"),
        service_fields(
            f"credentials-{suffix}",
            cors_allow_origins="*",
            cors_allow_credentials=1,
        ),
    ]
    for fields in invalid_cases:
        status, data = call("service_create", **fields)
        expect(status, data, 400)


def main() -> None:
    print("URL:", admin_url())
    test_service_crud_and_conflicts()
    test_service_validation()
    print("all service admin tests passed")


if __name__ == "__main__":
    main()
