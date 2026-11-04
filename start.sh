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

command -v docker >/dev/null 2>&1 || die "docker not found"
docker info >/dev/null 2>&1 || die "docker daemon not running"

if [[ -z "${ADMIN_WHITELIST_IPS:-}" ]]; then
  export ADMIN_WHITELIST_IPS
  ADMIN_WHITELIST_IPS="$(bash "$ROOT/scripts/collect-admin-whitelist-ips.sh")"
fi

mkdir -p "$ROOT/data"
log "GATEWAY_STORAGE=${STORAGE}"

stop_redis_stack() {
  # Leftover gw-redis from a previous GATEWAY_STORAGE=redis session keeps running (restart: always)
  if docker container inspect gw-redis >/dev/null 2>&1; then
    log "stopping gw-redis (not used when GATEWAY_STORAGE=${STORAGE})"
    docker compose --profile redis stop redis >/dev/null 2>&1 || docker stop gw-redis >/dev/null 2>&1 || true
  fi
}

case "$STORAGE" in
  memory|sqlite)
    stop_redis_stack
    run docker compose up -d --build openresty
    assert_container_running gw-openresty
    ;;
  redis)
    run docker compose --profile redis up -d --build redis
    run docker compose --profile redis run --rm redis-init
    run docker compose up -d --build openresty
    assert_container_running gw-openresty
    ;;
  *)
    die "unknown GATEWAY_STORAGE=${STORAGE} (use memory, redis, or sqlite)"
    ;;
esac

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

wait_http "http://127.0.0.1:8080/" || die "gateway not ready on :8080 (docker logs gw-openresty)"
