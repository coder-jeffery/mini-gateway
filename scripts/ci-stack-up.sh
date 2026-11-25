#!/usr/bin/env bash
# Start gateway stack with in-cluster mock upstream (same as GitHub Actions gateway job).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
require_docker() {
  if ! docker info >/dev/null 2>&1; then
    cat >&2 <<'EOF'
ci-stack: Docker daemon is not reachable.

  macOS: start Docker Desktop and wait until it shows "Running", then run:
    docker info

  Linux: ensure the docker service is up (e.g. sudo systemctl start docker).

EOF
    exit 1
  fi
}

wait_gateway_http() {
  local url="$1" label="$2" attempts="${3:-60}"
  local i
  for i in $(seq 1 "$attempts"); do
    if curl -sf "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "ci-stack: timed out waiting for $label ($url)" >&2
  docker ps -a --filter name=gw- 2>/dev/null || true
  docker logs gw-openresty 2>&1 | tail -80 || true
  return 1
}

require_docker

# shellcheck source=scripts/lib/ci-compose.env
source "$ROOT/scripts/lib/ci-compose.env"

export GATEWAY_STORAGE="${GATEWAY_STORAGE:-memory}"

FORCE="${CI_STACK_FORCE_RECREATE:-1}"
WAIT_TIMEOUT="${CI_STACK_WAIT_TIMEOUT:-120}"
UP_ARGS=(up -d --wait "--wait-timeout" "$WAIT_TIMEOUT")
if [[ "$FORCE" == "1" ]]; then
  UP_ARGS+=(--force-recreate)
fi

# shellcheck disable=SC2086
docker compose $COMPOSE_CI_FILES build openresty
# shellcheck disable=SC2086
docker compose $COMPOSE_CI_FILES "${UP_ARGS[@]}" $COMPOSE_CI_SERVICES

# Host-side probe (published :8080); --wait covers container healthchecks only.
wait_gateway_http "http://127.0.0.1:8080/health" "gateway /health"

peers="$(docker exec gw-openresty printenv GATEWAY_UPSTREAM_PEERS)"
scheme="$(docker exec gw-openresty printenv GATEWAY_UPSTREAM_SCHEME)"
if [[ "$peers" != "mock-upstream:80" ]] || [[ "$scheme" != "http" ]]; then
  echo "ci-stack: bad upstream env peers=$peers scheme=$scheme (want mock-upstream:80 http)" >&2
  echo "ci-stack: ensure you use both compose files (see scripts/lib/ci-compose.env)" >&2
  exit 1
fi

if ! docker exec gw-openresty sh -ce '
  if command -v wget >/dev/null; then
    wget -q -O - http://mock-upstream/status/200
  elif command -v curl >/dev/null; then
    curl -sf http://mock-upstream/status/200
  else
    echo "no wget/curl in openresty image" >&2
    exit 1
  fi
' >/dev/null; then
  echo "ci-stack: openresty cannot reach mock-upstream on the compose network" >&2
  docker logs gw-mock-upstream 2>&1 | tail -30 || true
  exit 1
fi

data_plane_preflight() {
  local code body_file
  body_file="$(mktemp)"
  for i in $(seq 1 45); do
    code="$(curl -s -o "$body_file" -w "%{http_code}" -H "X-Api-Key: mini-key" http://127.0.0.1:8080/ || echo "000")"
    if [[ "$code" == "200" ]]; then
      rm -f "$body_file"
      return 0
    fi
    sleep 1
  done
  echo "ci-stack: data plane preflight failed (expected HTTP 200, got $code)" >&2
  echo "ci-stack: response body (first 300 bytes):" >&2
  head -c 300 "$body_file" >&2 || true
  echo >&2
  docker logs gw-openresty 2>&1 | tail -40 >&2 || true
  rm -f "$body_file"
  return 1
}

if [[ "${CI_STACK_SKIP_DATA_PLANE_PREFLIGHT:-0}" == "1" ]]; then
  echo "ci-stack: skipping data plane preflight (CI_STACK_SKIP_DATA_PLANE_PREFLIGHT=1)" >&2
elif ! data_plane_preflight; then
  echo "ci-stack: bypass tip: CI_STACK_SKIP_DATA_PLANE_PREFLIGHT=1 ./scripts/ci-smoke-lite.sh" >&2
  exit 1
fi

echo "ci-stack: up OK (mock-upstream + openresty)"