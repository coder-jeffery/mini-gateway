"""HS256 JWT helpers for mini-gateway OAuth2 (Resource Server) tests."""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import time
from typing import Any


def oauth_secret() -> str:
    return os.environ.get("OAUTH2_JWT_SECRET", "oauth2-dev-secret")


def gateway_url() -> str:
    base = os.environ.get("GATEWAY_URL", "http://127.0.0.1:8080/").rstrip("/")
    return base + "/"


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def make_hs256_jwt(payload: dict[str, Any], secret: str | None = None) -> str:
    secret = secret if secret is not None else oauth_secret()
    header = b64url(
        json.dumps({"alg": "HS256", "typ": "JWT"}, separators=(",", ":")).encode()
    )
    body = b64url(json.dumps(payload, separators=(",", ":")).encode())
    signing_input = f"{header}.{body}".encode()
    sig = hmac.new(secret.encode(), signing_input, hashlib.sha256).digest()
    return f"{header}.{body}.{b64url(sig)}"


def payload_with_exp(
    sub: str = "test-user-001",
    exp_offset_sec: int = 3600,
    extra: dict[str, Any] | None = None,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "sub": sub,
        "exp": int(time.time()) + exp_offset_sec,
    }
    issuer = os.environ.get("OAUTH2_ISSUER", "").strip()
    if issuer:
        payload["iss"] = issuer
    audience = os.environ.get("OAUTH2_AUDIENCE", "").strip()
    if audience and "," not in audience:
        payload["aud"] = audience
    scope = os.environ.get("OAUTH2_REQUIRED_SCOPE", "").strip()
    if scope:
        payload["scope"] = scope.split(",")[0].strip()
    if extra:
        payload.update(extra)
    return payload


def build_case(case_id: str) -> tuple[dict[str, Any], str | None, str]:
    """Return (payload, secret_override, token) for a named fixture case."""
    skew = int(os.environ.get("OAUTH2_CLOCK_SKEW_SEC", "60"))

    if case_id == "valid":
        pl = payload_with_exp(sub="test-user-valid", exp_offset_sec=3600)
        return pl, None, make_hs256_jwt(pl)

    if case_id == "valid_client":
        pl = payload_with_exp(
            sub="svc-account",
            exp_offset_sec=3600,
            extra={"client_id": "client-mini-gateway-01"},
        )
        return pl, None, make_hs256_jwt(pl)

    if case_id == "expired":
        pl = payload_with_exp(sub="test-user-expired", exp_offset_sec=-(skew + 120))
        return pl, None, make_hs256_jwt(pl)

    if case_id == "bad_sig":
        pl = payload_with_exp(sub="test-user-badsig", exp_offset_sec=3600)
        token = make_hs256_jwt(pl) + "tampered"
        return pl, None, token

    if case_id == "wrong_secret":
        pl = payload_with_exp(sub="test-user-wrongsec", exp_offset_sec=3600)
        return pl, "not-the-gateway-secret", make_hs256_jwt(pl, "not-the-gateway-secret")

    if case_id == "missing_exp":
        pl = {"sub": "test-user-no-exp"}
        if os.environ.get("OAUTH2_ISSUER", "").strip():
            pl["iss"] = os.environ["OAUTH2_ISSUER"].strip()
        return pl, None, make_hs256_jwt(pl)

    if case_id == "wrong_audience":
        pl = payload_with_exp(sub="test-user-bad-aud", exp_offset_sec=3600)
        pl["aud"] = "wrong-audience-value"
        return pl, None, make_hs256_jwt(pl)

    if case_id == "missing_scope":
        pl = payload_with_exp(sub="test-user-noscope", exp_offset_sec=3600)
        pl.pop("scope", None)
        return pl, None, make_hs256_jwt(pl)

    raise KeyError(f"unknown jwt case: {case_id}")
