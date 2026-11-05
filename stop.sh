#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

UI_PID_FILE="$ROOT/data/ui.pid"
UI_PORT="${UI_PORT:-3000}"
if [[ -f "$UI_PID_FILE" ]]; then
  pid="$(cat "$UI_PID_FILE" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    printf '[stop] stopping admin UI (pid %s)\n' "$pid"
    kill "$pid" 2>/dev/null || true
    sleep 1
    kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f "$UI_PID_FILE"
fi
if command -v lsof >/dev/null 2>&1; then
  pids="$(lsof -ti "tcp:${UI_PORT}" -sTCP:LISTEN 2>/dev/null || true)"
  if [[ -n "$pids" ]]; then
    printf '[stop] freeing host port %s\n' "$UI_PORT"
    # shellcheck disable=SC2086
    kill $pids 2>/dev/null || true
  fi
fi

REDIS_PORT="${REDIS_PORT:-6379}"
GATEWAY_PORT="${GATEWAY_PORT:-8080}"

source "$ROOT/start.sh" 2>/dev/null || true
if declare -F gateway_ensure_port_free >/dev/null 2>&1; then
  gateway_release_host_port "$UI_PORT" "" || true
  gateway_release_host_port "$GATEWAY_PORT" "" || true
  gateway_release_host_port "$REDIS_PORT" "" || true
fi

docker compose --profile redis --profile ui stop 2>/dev/null || true
docker compose --profile redis --profile ui down --remove-orphans
