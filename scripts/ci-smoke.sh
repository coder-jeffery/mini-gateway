#!/usr/bin/env bash
# Local entry: identical stack + checks as CI gateway job, then Python smoke tests.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

"$ROOT/scripts/ci-stack-up.sh"

export GATEWAY_AUTH_MODE=both
export OAUTH2_JWT_SECRET=oauth2-dev-secret
python3 test/test.py
python3 test/test_hmac.py
python3 test/test_oauth2.py
python3 test/test_metrics.py

echo "ci-smoke: all passed"