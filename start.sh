#!/usr/bin/env bash
# One-click start: detect host IPs -> seed admin whitelist -> docker compose up
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

log() { printf '[start] %s\n' "$*"; }
die() { printf '[start] ERROR: %s\n' "$*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || die "docker not found; install Docker Desktop or docker CLI first."

if ! docker info >/dev/null 2>&1; then
  die "docker daemon not running; start Docker and retry."
fi

if [[ -z "${ADMIN_WHITELIST_IPS:-}" ]]; then
  export ADMIN_WHITELIST_IPS
  ADMIN_WHITELIST_IPS="$(bash "$ROOT/scripts/collect-admin-whitelist-ips.sh")"
fi

log "Admin whitelist IPs: ${ADMIN_WHITELIST_IPS}"
log "Starting services (redis, redis-init, openresty)..."
docker compose up -d

wait_http() {
  local url="$1" max="${2:-30}" i=0 code
  while [[ $i -lt $max ]]; do
    code="$(curl -s -o /dev/null --connect-timeout 1 -w '%{http_code}' "$url" 2>/dev/null || true)"
    # 401 = gateway up (missing X-Api-Key); 200/429 also OK
    case "$code" in
      200|401|429) return 0 ;;
    esac
    sleep 1
    i=$((i + 1))
  done
  return 1
}

if wait_http "http://127.0.0.1:8080/" 45; then
  log "Gateway HTTP ready: http://127.0.0.1:8080/"
else
  log "Gateway not responding yet; check: docker compose logs openresty"
fi

log "Containers:"
docker compose ps

log "Admin whitelist in Redis:"
docker exec gw-redis redis-cli SMEMBERS admin:whitelist:ip 2>/dev/null || true

cat <<'EOF'

Next steps:
  1) Create API key (signed admin API):
       ./test/admin_call.sh upsert_apikey '{"api_key":"abc123","limit":20,"window":30}'
  2) Call gateway:
       curl -H "X-Api-Key: abc123" http://127.0.0.1:8080/
  3) Stop:
       ./stop.sh

Env overrides:
  ADMIN_WHITELIST_IPS=127.0.0.1,10.0.0.5 ./start.sh
  ADMIN_WHITELIST_IP_EXTRA=203.0.113.1 ./start.sh

EOF
