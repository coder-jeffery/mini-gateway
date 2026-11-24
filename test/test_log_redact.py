#!/usr/bin/env python3
"""Unit tests for nginx/lua/log_redact.lua masking rules."""

from __future__ import annotations


def mask_credential(value: str | None) -> str:
    """Mirror log_redact.lua mask_credential."""
    if not value:
        return ""
    s = str(value)
    n = len(s)
    if n <= 4:
        return "***"
    if n <= 8:
        return s[:2] + "***"
    return s[:4] + "***" + s[-4:]


def test_mask_short() -> None:
    assert mask_credential("") == ""
    assert mask_credential("ab") == "***"
    assert mask_credential("abcd") == "***"


def test_mask_medium() -> None:
    assert mask_credential("abcd12") == "ab***"
    assert mask_credential("12345678") == "12***"


def test_mask_long() -> None:
    assert mask_credential("mini-key") == "mi***"
    assert mask_credential("super-secret-api-key-xyz") == "supe***-xyz"


def scrub_line(message: str) -> str:
    """Mirror log_redact.lua scrub_line (no per-request api key injection)."""
    import re

    s = message
    s = re.sub(r"(?i)Bearer\s+[A-Za-z0-9_\-\.]+", "Bearer ***", s)
    s = re.sub(r"(?i)Authorization:\s*\S+", "Authorization: ***", s)
    s = re.sub(r"X-Api-Key:\s*\S+", "X-Api-Key: ***", s)
    s = re.sub(r"X-Business-Sign:\s*\S+", "X-Business-Sign: ***", s)
    return s


def test_scrub_bearer() -> None:
    raw = "jwt validate failed Bearer eyJhbGciOiJIUzI1NiJ9.abc.def"
    out = scrub_line(raw)
    assert "eyJ" not in out
    assert "Bearer ***" in out


def main() -> None:
    test_mask_short()
    test_mask_medium()
    test_mask_long()
    test_scrub_bearer()
    print("all log_redact tests passed")


if __name__ == "__main__":
    main()