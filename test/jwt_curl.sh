#!/usr/bin/env bash
# JWT Bearer 业务网关探测（对标: curl -i -H "X-Api-Key: mini-key" http://127.0.0.1:8080/）
#
# 网关需: GATEWAY_AUTH_MODE=bearer|both 且 OAUTH2_JWT_SECRET 与本脚本一致（默认 oauth2-dev-secret）
#
# Usage:
#   ./test/jwt_curl.sh
#   OAUTH2_JWT_SECRET=my-secret ./test/jwt_curl.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export ROOT
export GATEWAY_URL="${GATEWAY_URL:-http://127.0.0.1:8080/}"
export OAUTH2_JWT_SECRET="${OAUTH2_JWT_SECRET:-oauth2-dev-secret}"

TOKEN="$(python3 -c "
import os, sys
sys.path.insert(0, os.path.join(os.environ['ROOT'], 'test'))
from jwt_client import build_case
_, _, t = build_case('valid')
print(t)
")"

echo "# curl -i -H \"Authorization: Bearer <JWT>\" \"${GATEWAY_URL}\""
echo "# sub=test-user-valid HS256 secret=${OAUTH2_JWT_SECRET}"
echo
exec curl -i \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Accept: application/json" \
  "${GATEWAY_URL}"
