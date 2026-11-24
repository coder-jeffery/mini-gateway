#!/usr/bin/env bash
# Start gateway stack with in-cluster mock upstream (same as GitHub Actions gateway job).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=scripts/lib/ci-compose.env
source "$ROOT/scripts/lib/ci-compose.env"

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

for i in $(seq 1 30); do
  if curl -sf -H "X-Api-Key: mini-key" http://127.0.0.1:8080/ >/dev/null; then
    break
  fi
  sleep 1
done

if ! curl -sf -H "X-Api-Key: mini-key" http://127.0.0.1:8080/ >/dev/null; then
  echo "ci-stack: data plane preflight failed (expected 200 via mock-upstream)" >&2
  exit 1
fi

echo "ci-stack: up OK (mock-upstream + openresty)"