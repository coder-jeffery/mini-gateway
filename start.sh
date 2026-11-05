#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

VERBOSE="${START_VERBOSE:-0}"
STORAGE="${GATEWAY_STORAGE:-memory}"
export GATEWAY_STORAGE="$STORAGE"

log() {
  if [[ "$VERBOSE" == "1" ]]; then
    printf '[start] %s\n' "$*"
  fi
}

die() {
  printf '[start] ERROR: %s\n' "$*" >&2
  exit 1
}

run() {
  if [[ "$VERBOSE" == "1" ]]; then
    "$@"
    return
  fi
  if ! "$@" >/dev/null 2>&1; then
    die "command failed: $* (try: START_VERBOSE=1 ./start.sh)"
  fi
}

assert_container_running() {
  local name="$1"
  sleep 1
  if ! docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null | grep -q true; then
    die "container ${name} is not running. logs: docker logs ${name}"
  fi
}

assert_container_not_paused() {
  local name="$1"
  if docker inspect -f '{{.State.Paused}}' "$name" 2>/dev/null | grep -q true; then
    die "container ${name} is paused (docker unpause ${name} or docker rm -f ${name})"
  fi
}

gateway_normalize_container() {
  local name="$1"
  if ! docker container inspect "$name" >/dev/null 2>&1; then
    return 0
  fi
  if docker inspect -f '{{.State.Paused}}' "$name" 2>/dev/null | grep -q true; then
    log "container ${name} is paused, removing before start"
    docker rm -f "$name" 2>/dev/null || true
  fi
}

gateway_port_host_listeners() {
  local port="$1"
  if ! command -v lsof >/dev/null 2>&1; then
    return 0
  fi
  lsof -ti "tcp:${port}" -sTCP:LISTEN 2>/dev/null || true
}

gateway_port_docker_using() {
  local port="$1"
  local cid port_map
  for cid in $(docker ps -aq 2>/dev/null); do
    port_map="$(docker port "$cid" 2>/dev/null || true)"
    if echo "$port_map" | grep -qE "(0\.0\.0\.0|:::|127\.0\.0\.1):${port}(-|>|$)"; then
      echo "$cid"
      return 0
    fi
  done
  return 1
}

# Returns 0 if host port is occupied (process and/or docker publish).
gateway_port_in_use() {
  local port="$1"
  local pids
  pids="$(gateway_port_host_listeners "$port")"
  if [[ -n "$pids" ]]; then
    return 0
  fi
  gateway_port_docker_using "$port" >/dev/null 2>&1
}

# Kill listeners / remove docker bindings for this host port.
gateway_release_host_port() {
  local port="$1"
  local container_name="${2:-}"

  local pids
  pids="$(gateway_port_host_listeners "$port")"
  if [[ -n "$pids" ]]; then
    printf '[start] killing host process on port %s (pid: %s)\n' "$port" "${pids//$'\n'/ }"
    # shellcheck disable=SC2086
    kill $pids 2>/dev/null || true
    sleep 1
    # shellcheck disable=SC2086
    kill -9 $pids 2>/dev/null || true
  fi

  local cid name tries=0
  while [[ $tries -lt 20 ]]; do
    cid="$(gateway_port_docker_using "$port" 2>/dev/null || true)"
    [[ -z "$cid" ]] && break
    name="$(docker inspect -f '{{.Name}}' "$cid" 2>/dev/null | sed 's/^\///')"
    printf '[start] removing container %s using host port %s\n' "$name" "$port"
    docker rm -f "$cid" 2>/dev/null || true
    sleep 0.5
    tries=$((tries + 1))
  done

  if [[ -n "$container_name" ]]; then
    docker rm -f "$container_name" 2>/dev/null || true
  fi
}

# Check port; if occupied, release and verify before continuing.
gateway_ensure_port_free() {
  local port="$1"
  local container_name="${2:-}"

  if ! gateway_port_in_use "$port"; then
    log "port ${port} is free"
    return 0
  fi

  printf '[start] port %s is in use, releasing before continue...\n' "$port"
  gateway_release_host_port "$port" "$container_name"
  sleep 1

  if gateway_port_in_use "$port"; then
    die "port ${port} still in use after kill/remove (run ./stop.sh or set a different port in .env)"
  fi
  printf '[start] port %s is now free\n' "$port"
}

compose_extract_bind_port() {
  local msg="$1"
  local p
  p="$(echo "$msg" | sed -n 's/.*0\.0\.0\.0:\([0-9][0-9]*\).*/\1/p' | head -1)"
  if [[ -z "$p" ]]; then
    p="$(echo "$msg" | sed -n 's/.*:\([0-9][0-9]*\).*failed: port is already allocated.*/\1/p' | head -1)"
  fi
  echo "$p"
}

wait_redis_pong() {
  local max="${1:-60}" i=0
  while [[ $i -lt $max ]]; do
    if docker exec gw-redis redis-cli ping 2>/dev/null | grep -q PONG; then
      return 0
    fi
    sleep 1
    i=$((i + 1))
  done
  return 1
}

verify_redis_bootstrap() {
  local api_key="${DEFAULT_API_KEY:-mini-key}"
  local exists admin_ok
  exists="$(docker exec gw-redis redis-cli EXISTS "apikey:${api_key}" 2>/dev/null || echo 0)"
  admin_ok="$(docker exec gw-redis redis-cli SISMEMBER "admin:whitelist:ip" "127.0.0.1" 2>/dev/null || echo 0)"
  [[ "$exists" == "1" && "$admin_ok" == "1" ]]
}

wait_http() {
  local url="$1" max="${2:-45}" i=0 code
  while [[ $i -lt $max ]]; do
    code="$(curl -s -o /dev/null --connect-timeout 1 -w '%{http_code}' "$url" 2>/dev/null || true)"
    case "$code" in
      200|401|429) return 0 ;;
    esac
    sleep 1
    i=$((i + 1))
  done
  return 1
}

stop_redis_stack() {
  if docker container inspect gw-redis >/dev/null 2>&1; then
    log "stopping gw-redis (not used when GATEWAY_STORAGE=${STORAGE})"
    docker compose --profile redis stop redis >/dev/null 2>&1 || docker stop gw-redis >/dev/null 2>&1 || true
  fi
}

# Old containers can reference deleted compose networks after Docker restarts.
gateway_docker_recover_stale() {
  log "removing stale gw containers / compose networks, then retrying"
  docker rm -f gw-redis gw-openresty gw-ui 2>/dev/null || true
  docker compose --profile redis down --remove-orphans 2>/dev/null || true
  docker compose down --remove-orphans 2>/dev/null || true
}

compose_run() {
  local compose_log rc=0 output
  compose_log="$(mktemp)"

  if [[ "$VERBOSE" == "1" ]]; then
    docker compose "$@" 2>&1 | tee "$compose_log" || rc=$?
  else
    docker compose "$@" >"$compose_log" 2>&1 || rc=$?
  fi

  if [[ "$rc" -eq 0 ]]; then
    rm -f "$compose_log"
    return 0
  fi

  output="$(cat "$compose_log")"

  if echo "$output" | grep -qiE 'port is already allocated|ports are not available'; then
    local bound_port
    bound_port="$(compose_extract_bind_port "$output")"
    [[ -z "$bound_port" ]] && bound_port="${GATEWAY_PORT:-8080}"
    log "port ${bound_port} in use, releasing and retrying once"
    gateway_ensure_port_free "$bound_port" ""
    rc=0
    if [[ "$VERBOSE" == "1" ]]; then
      docker compose "$@" 2>&1 | tee "$compose_log" || rc=$?
    else
      docker compose "$@" >"$compose_log" 2>&1 || rc=$?
    fi
    if [[ "$rc" -eq 0 ]]; then
      rm -f "$compose_log"
      return 0
    fi
    output="$(cat "$compose_log")"
    rm -f "$compose_log"
    die "docker 端口 ${bound_port} 仍被占用。请执行 ./stop.sh 或设置 GATEWAY_PORT / UI_PORT。详情: $(echo "$output" | tail -1)"
  fi

  if echo "$output" | grep -qiE 'network.*not found|cannot start a paused container|paused container'; then
    gateway_docker_recover_stale
    rc=0
    if [[ "$VERBOSE" == "1" ]]; then
      docker compose "$@" 2>&1 | tee "$compose_log" || rc=$?
    else
      docker compose "$@" >"$compose_log" 2>&1 || rc=$?
    fi
    if [[ "$rc" -eq 0 ]]; then
      rm -f "$compose_log"
      return 0
    fi
    output="$(cat "$compose_log")"
  fi

  rm -f "$compose_log"
  die "command failed: docker compose $* — $(echo "$output" | tail -1) (try: START_VERBOSE=1 ./start.sh)"
}

gateway_require_docker() {
  command -v docker >/dev/null 2>&1 || die "docker not found"
  docker info >/dev/null 2>&1 || die "docker daemon not running"
}

gateway_prepare_env() {
  if [[ -z "${ADMIN_WHITELIST_IPS:-}" ]]; then
    export ADMIN_WHITELIST_IPS
    ADMIN_WHITELIST_IPS="$(bash "$ROOT/scripts/collect-admin-whitelist-ips.sh")"
  fi
  mkdir -p "$ROOT/data"
  log "GATEWAY_STORAGE=${STORAGE}"
}

# Phase 1a: Redis container up + PING
gateway_start_redis() {
  local redis_port="${REDIS_PORT:-6379}"

  if docker inspect -f '{{.State.Running}}' gw-redis 2>/dev/null | grep -q true; then
    if wait_redis_pong 5; then
      log "gw-redis already running on :${redis_port}"
      return 0
    fi
    docker rm -f gw-redis 2>/dev/null || true
  fi

  gateway_normalize_container gw-redis
  gateway_ensure_port_free "$redis_port" gw-redis
  compose_run --profile redis up -d --build redis
  assert_container_running gw-redis
  assert_container_not_paused gw-redis
  wait_redis_pong 60 || die "redis PING failed (docker logs gw-redis)"
  log "redis is ready (PONG)"
}

# Phase 1b: redis-init seed (requires gateway_start_redis first)
gateway_run_redis_init() {
  compose_run --profile redis run --rm redis-init
  verify_redis_bootstrap || die "redis-init verification failed (missing apikey or admin whitelist)"
  log "redis-init verified"
}

gateway_require_redis_ready() {
  assert_container_running gw-redis
  assert_container_not_paused gw-redis
  wait_redis_pong 15 || die "redis is not ready; run ./start-redis.sh first"
  verify_redis_bootstrap || die "redis data not initialized; run ./start-redis.sh first"
}

# Phase 1: bootstrap storage / seed data
gateway_init_data() {
  gateway_require_docker
  gateway_prepare_env

  case "$STORAGE" in
    memory|sqlite)
      stop_redis_stack
      log "storage=${STORAGE}: seed data on first openresty worker bootstrap"
      ;;
    redis)
      gateway_start_redis
      gateway_run_redis_init
      ;;
    *)
      die "unknown GATEWAY_STORAGE=${STORAGE} (use memory, redis, or sqlite)"
      ;;
  esac
}

gateway_require_openresty_ready() {
  assert_container_running gw-openresty
  local gw_port="${GATEWAY_PORT:-8080}"
  wait_http "http://127.0.0.1:${gw_port}/" 15 || die "gateway not ready; run ./start-gateway.sh first"
}

# Phase 2: start OpenResty gateway
gateway_start_openresty() {
  if [[ "$STORAGE" == "redis" ]]; then
    gateway_require_redis_ready
  fi

  local gw_port="${GATEWAY_PORT:-8080}"

  if docker inspect -f '{{.State.Running}}' gw-openresty 2>/dev/null | grep -q true; then
    if wait_http "http://127.0.0.1:${gw_port}/" 5; then
      log "gw-openresty already running on :${gw_port}"
      return 0
    fi
    log "gw-openresty running but unhealthy, recreating"
    docker rm -f gw-openresty 2>/dev/null || true
  fi

  gateway_normalize_container gw-openresty
  gateway_ensure_port_free "$gw_port" gw-openresty
  compose_run up -d --build openresty

  assert_container_running gw-openresty
  wait_http "http://127.0.0.1:${gw_port}/" || die "gateway not ready on :${gw_port} (docker logs gw-openresty)"
  log "gateway is ready on :${gw_port}"
}

# Phase 3: Admin UI container (profile ui)
gateway_start_ui() {
  gateway_require_openresty_ready

  local ui_port="${UI_PORT:-3000}"

  if docker inspect -f '{{.State.Running}}' gw-ui 2>/dev/null | grep -q true; then
    if wait_http "http://127.0.0.1:${ui_port}/" 5; then
      log "gw-ui already running on :${ui_port}"
      return 0
    fi
    docker rm -f gw-ui 2>/dev/null || true
  fi

  gateway_normalize_container gw-ui
  gateway_ensure_port_free "$ui_port" gw-ui
  compose_run --profile ui up -d --build ui
  assert_container_running gw-ui
  wait_http "http://127.0.0.1:${ui_port}/" || die "admin UI not ready on :${ui_port} (docker logs gw-ui)"
  log "admin UI is ready on :${ui_port}"
}

gateway_start() {
  gateway_init_data
  gateway_start_openresty
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  gateway_start
fi
