#!/usr/bin/env python3
"""P4-3 unit: effective limit ramp (mirrors rate_warmup.lua)."""

from __future__ import annotations


def effective_limit(nominal: int, start: int, ramp_sec: float, created: float, now: float) -> int:
    if ramp_sec <= 0 or start >= nominal:
        return nominal
    elapsed = max(0.0, now - created)
    progress = min(1.0, elapsed / ramp_sec)
    eff = int(start + (nominal - start) * progress)
    return max(1, min(nominal, eff))


def test_ramp_midpoint() -> None:
    assert effective_limit(100, 10, 100.0, 1000.0, 1050.0) == 55


def test_ramp_complete() -> None:
    assert effective_limit(100, 10, 100.0, 1000.0, 1200.0) == 100


def main() -> None:
    test_ramp_midpoint()
    test_ramp_complete()
    print("test_rate_warmup: passed")


if __name__ == "__main__":
    main()