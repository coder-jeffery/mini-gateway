#!/usr/bin/env python3
"""P2-5: access log sample rate logic mirror (unit)."""

from __future__ import annotations


def should_log(status: int, sample: float, rnd: float) -> bool:
    if status >= 400:
        return True
    if sample >= 1:
        return True
    if sample <= 0:
        return False
    return rnd <= sample


def test_failures_always_logged() -> None:
    assert should_log(401, 0.0, 0.99)
    assert should_log(500, 0.1, 0.99)


def test_success_sampled() -> None:
    assert not should_log(200, 0.0, 0.5)
    assert should_log(200, 1.0, 0.99)
    assert should_log(200, 0.5, 0.1)
    assert not should_log(200, 0.5, 0.9)


def main() -> None:
    test_failures_always_logged()
    test_success_sampled()
    print("test_log_sample: passed")


if __name__ == "__main__":
    main()