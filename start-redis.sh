#!/usr/bin/env bash
# Step 1: start Redis + run redis-init (must succeed before gateway/UI)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

export GATEWAY_STORAGE="${GATEWAY_STORAGE:-redis}"
export REDIS_PORT="${REDIS_PORT:-6379}"
if [[ "$GATEWAY_STORAGE" != "redis" ]]; then
  printf '[start-redis] ERROR: GATEWAY_STORAGE must be redis (current: %s)\n' "$GATEWAY_STORAGE" >&2
  exit 1
fi

# shellcheck source=start.sh
source "$ROOT/start.sh"

printf '[start-redis] (1/2) starting Redis container...\n'
gateway_require_docker
gateway_prepare_env
gateway_start_redis

printf '[start-redis] (2/2) running redis-init...\n'
gateway_run_redis_init

printf '[start-redis] OK — Redis ready on localhost:%s\n' "${REDIS_PORT:-6379}"
printf '[start-redis] next: ./start-gateway.sh\n'
