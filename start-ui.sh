#!/usr/bin/env bash
# Step 3: start Admin UI container (requires gateway)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

export UI_PORT="${UI_PORT:-3000}"
export GATEWAY_PORT="${GATEWAY_PORT:-8080}"

# shellcheck source=start.sh
source "$ROOT/start.sh"

gateway_require_docker

printf '[start-ui] checking gateway...\n'
gateway_require_openresty_ready

printf '[start-ui] starting gw-ui...\n'
gateway_start_ui

printf '[start-ui] OK — http://127.0.0.1:%s\n' "$UI_PORT"
