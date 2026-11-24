#!/usr/bin/env bash
# Start gateway stack with in-cluster mock upstream (same as GitHub Actions gateway job).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=scripts/lib/ci-compose.env
source "$ROOT/scripts/lib/ci-compose.env"

export GATEWAY_STORAGE="${GATEWAY_STORAGE:-memory}"

FORCE="${CI_STACK_FORCE_RECREATE:-1}"
UP_ARGS=(up -d)
if [[ "$FORCE" == "1" ]]; then
  UP_ARGS+=(--force-recreate)
fi

# shellcheck disable=SC2086
docker compose $COMPOSE_CI_FILES build openresty
# shellcheck disable=SC2086
docker compose $COMPOSE_CI_FILES "${UP_ARGS[@]}" $COMPOSE_CI_SERVICES

for i in $(seq 1 30); do
  if curl -sf http://127.0.0.1:8080/health >/dev/null; then
    break
  fi
  sleep 2
done

if ! curl -sf http://127.0.0.1:8080/health >/dev/null; then
  echo "ci-stack: gateway not healthy" >&2
  docker logs gw-openresty 2>&1 | tail -50 || true
  exit 1
fi

peers="$(docker exec gw-openresty printenv GATEWAY_UPSTREAM_PEERS)"
scheme="$(docker exec gw-openresty printenv GATEWAY_UPSTREAM_SCHEME)"
if [[ "$peers" != "mock-upstream:80" ]] || [[ "$scheme" != "http" ]]; then
  echo "ci-stack: bad upstream env peers=$peers scheme=$scheme (want mock-upstream:80 http)" >&2
  exit 1
fi

docker exec gw-openresty sh -ce '
  if command -v wget >/dev/null; then
    wget -q -O - http://mock-upstream/status/200
  elif command -v curl >/dev/null; then
    curl -sf http://mock-upstream/status/200
  else
    echo "no wget/curl in openresty image" >&2
    exit 1
  fi
' >/dev/null

curl -sf -H "X-Api-Key: mini-key" http://127.0.0.1:8080/ >/dev/null

echo "ci-stack: up OK (mock-upstream + openresty)"