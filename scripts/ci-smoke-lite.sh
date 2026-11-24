#!/usr/bin/env bash
# Lite smoke: control plane + metrics only (no full data-plane / OAuth E2E).
# Use when Docker is up but mock upstream / proxy path is flaky, or for quick local checks.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export CI_STACK_SKIP_DATA_PLANE_PREFLIGHT=1
if [[ "${CI_SMOKE_SKIP_STACK_UP:-0}" != "1" ]]; then
  # shellcheck source=scripts/lib/ci-compose.env
  source "$ROOT/scripts/lib/ci-compose.env"
  "$ROOT/scripts/ci-stack-up.sh"
fi

export GATEWAY_AUTH_MODE=both
export OAUTH2_JWT_SECRET=oauth2-dev-secret
export CI_SMOKE_LITE=1

python3 test/test.py
python3 test/test_hmac.py
python3 test/test_oauth2.py
python3 test/test_metrics.py
python3 test/test_log_sample.py
python3 test/test_admin_audit.py
python3 test/test_config_cache.py
python3 test/test_policy_p2.py
python3 test/test_gray_snapshot.py
python3 test/test_p3_governance.py
python3 test/test_rate_warmup.py
python3 test/test_p4_extensions.py
python3 test/test_governance_api.py

echo "ci-smoke-lite: passed (data-plane preflight and bearer_ok skipped)"