#!/usr/bin/env bash
# Step 2: start mini-gateway (requires Redis when GATEWAY_STORAGE=redis)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

export GATEWAY_STORAGE="${GATEWAY_STORAGE:-redis}"
export GATEWAY_PORT="${GATEWAY_PORT:-8080}"

# shellcheck source=start.sh
source "$ROOT/start.sh"

gateway_require_docker
gateway_prepare_env

if [[ "$STORAGE" == "redis" ]]; then
  printf '[start-gateway] checking Redis...\n'
  gateway_require_redis_ready
fi

printf '[start-gateway] starting gw-openresty...\n'
gateway_start_openresty

printf '[start-gateway] OK — http://127.0.0.1:%s\n' "$GATEWAY_PORT"
printf '[start-gateway] next: ./start-ui.sh\n'
