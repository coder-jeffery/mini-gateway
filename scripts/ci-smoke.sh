#!/usr/bin/env bash
# Reproduce GitHub Actions gateway job locally (mock upstream + python smoke tests).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export GATEWAY_STORAGE="${GATEWAY_STORAGE:-memory}"

docker compose -f docker-compose.yml -f docker-compose.ci.yml build openresty
docker compose -f docker-compose.yml -f docker-compose.ci.yml up -d --force-recreate mock-upstream openresty

for i in $(seq 1 30); do
  if curl -sf http://127.0.0.1:8080/health >/dev/null; then
    break
  fi
  sleep 2
done

curl -sf http://127.0.0.1:8080/health >/dev/null
docker exec gw-openresty printenv GATEWAY_UPSTREAM_PEERS
docker exec gw-openresty printenv GATEWAY_UPSTREAM_SCHEME
curl -sf -H "X-Api-Key: mini-key" http://127.0.0.1:8080/

export GATEWAY_AUTH_MODE=both OAUTH2_JWT_SECRET=oauth2-dev-secret
python3 test/test.py
python3 test/test_hmac.py
python3 test/test_oauth2.py
python3 test/test_metrics.py

echo "ci-smoke: all passed"