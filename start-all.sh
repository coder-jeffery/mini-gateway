#!/usr/bin/env bash
# Ordered startup: Redis → Gateway → UI (each step must pass before the next)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

export GATEWAY_STORAGE="${GATEWAY_STORAGE:-redis}"
export UI_PORT="${UI_PORT:-3000}"
export GATEWAY_PORT="${GATEWAY_PORT:-8080}"
export REDIS_PORT="${REDIS_PORT:-6379}"

UI_PID_FILE="$ROOT/data/ui.pid"
UI_LOG="$ROOT/data/ui.log"

say() {
  printf '[start-all] %s\n' "$*"
}

die_all() {
  printf '[start-all] ERROR: %s\n' "$*" >&2
  exit 1
}

stop_ui_if_running() {
  if [[ ! -f "$UI_PID_FILE" ]]; then
    return 0
  fi
  local pid
  pid="$(cat "$UI_PID_FILE" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    say "stopping local dev UI (pid ${pid})"
    kill "$pid" 2>/dev/null || true
    sleep 1
    kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f "$UI_PID_FILE"
}

prepare_ports_for_stack() {
  source "$ROOT/start.sh"
  stop_ui_if_running
  say "checking ports ${REDIS_PORT}, ${GATEWAY_PORT}, ${UI_PORT} ..."
  gateway_ensure_port_free "${REDIS_PORT}" gw-redis
  gateway_ensure_port_free "${GATEWAY_PORT}" gw-openresty
  gateway_ensure_port_free "${UI_PORT}" gw-ui
}

start_ui_local_dev() {
  command -v node >/dev/null 2>&1 || die_all "node not found"
  command -v npm >/dev/null 2>&1 || die_all "npm not found"

  local ui_dir="$ROOT/ui"
  [[ -d "$ui_dir" ]] || die_all "ui directory missing: ${ui_dir}"

  if [[ ! -f "$ui_dir/.env.local" ]]; then
    cp "$ui_dir/.env.example" "$ui_dir/.env.local"
  fi

  if [[ ! -d "$ui_dir/node_modules" ]]; then
    say "npm install (first run) ..."
    (cd "$ui_dir" && npm install)
  fi

  mkdir -p "$ROOT/data"
  say "starting local Next.js dev on port ${UI_PORT} (log: ${UI_LOG})"
  cd "$ui_dir"
  nohup npm run dev -- -p "$UI_PORT" >>"$UI_LOG" 2>&1 &
  echo $! >"$UI_PID_FILE"
  cd "$ROOT"
}

if [[ "$GATEWAY_STORAGE" != "redis" ]]; then
  say "WARN: 分步启动推荐 GATEWAY_STORAGE=redis（当前: ${GATEWAY_STORAGE}）"
fi

prepare_ports_for_stack

say "[1/3] Redis — 启动并校验 ..."
bash "$ROOT/start-redis.sh"

say "[2/3] Gateway — 启动并校验 ..."
bash "$ROOT/start-gateway.sh"

say "[3/3] Admin UI — 启动并校验 ..."
if [[ "${START_UI_LOCAL:-0}" == "1" ]]; then
  source "$ROOT/start.sh"
  gateway_ensure_port_free "$UI_PORT" ""
  gateway_require_openresty_ready
  start_ui_local_dev
  wait_http "http://127.0.0.1:${UI_PORT}/" 120 || die_all "local UI not ready (see ${UI_LOG})"
else
  bash "$ROOT/start-ui.sh"
fi

say "完成"
say "  Redis:    localhost:${REDIS_PORT:-6379}"
say "  Gateway:  http://127.0.0.1:${GATEWAY_PORT}"
say "  Admin UI: http://127.0.0.1:${UI_PORT}"
say "  停止: ./stop.sh"
