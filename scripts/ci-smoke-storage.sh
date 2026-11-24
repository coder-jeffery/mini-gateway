#!/usr/bin/env bash
# Run ci-smoke-lite against memory | sqlite | redis storage backends.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

STORAGE="${1:-memory}"
export GATEWAY_STORAGE="$STORAGE"
export CI_STACK_SKIP_DATA_PLANE_PREFLIGHT=1

# shellcheck source=scripts/lib/ci-compose.env
source "$ROOT/scripts/lib/ci-compose.env"

case "$STORAGE" in
  memory)
    export COMPOSE_CI_FILES="-f docker-compose.yml -f docker-compose.ci.yml"
    COMPOSE_SERVICES=(mock-upstream openresty)
    ;;
  sqlite)
    export COMPOSE_CI_FILES="-f docker-compose.yml -f docker-compose.ci.yml -f docker-compose.ci-sqlite.yml"
    COMPOSE_SERVICES=(mock-upstream openresty)
    ;;
  redis)
    export COMPOSE_CI_FILES="-f docker-compose.yml -f docker-compose.ci.yml -f docker-compose.ci-redis.yml"
    COMPOSE_SERVICES=(mock-upstream redis openresty)
    ;;
  *)
    echo "usage: $0 memory|sqlite|redis" >&2
    exit 1
    ;;
esac

export COMPOSE_CI_SERVICES="${COMPOSE_SERVICES[*]}"
"$ROOT/scripts/ci-stack-down.sh" 2>/dev/null || true
"$ROOT/scripts/ci-stack-up.sh"
"$ROOT/scripts/ci-smoke-lite.sh"
"$ROOT/scripts/ci-stack-down.sh"
echo "ci-smoke-storage: $STORAGE OK"