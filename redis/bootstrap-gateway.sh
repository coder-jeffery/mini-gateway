#!/bin/sh
# Idempotent gateway bootstrap: admin IP whitelist, default API key, permanent admin token.
set -eu

REDIS_HOST="${REDIS_HOST:-redis}"
IPS="${ADMIN_WHITELIST_IPS:-127.0.0.1,172.17.0.1,192.168.65.1}"

DEFAULT_API_KEY="${DEFAULT_API_KEY:-mini-key}"
DEFAULT_API_KEY_LIMIT="${DEFAULT_API_KEY_LIMIT:-1000}"
DEFAULT_API_KEY_WINDOW="${DEFAULT_API_KEY_WINDOW:-60}"
DEFAULT_ADMIN_TOKEN="${DEFAULT_ADMIN_TOKEN:-mini-token}"

until redis-cli -h "$REDIS_HOST" ping 2>/dev/null | grep -q PONG; do
  sleep 0.5
done

cli() {
  redis-cli -h "$REDIS_HOST" "$@"
}

for ip in $(echo "$IPS" | tr ',' ' '); do
  ip=$(echo "$ip" | tr -d ' ')
  [ -z "$ip" ] && continue
  cli SADD "admin:whitelist:ip" "$ip" >/dev/null
done

cli SET "apikey:${DEFAULT_API_KEY}" "1" >/dev/null
cli HSET "apikey:meta:${DEFAULT_API_KEY}" limit "$DEFAULT_API_KEY_LIMIT" window "$DEFAULT_API_KEY_WINDOW" >/dev/null
cli SADD "apikey:index" "$DEFAULT_API_KEY" >/dev/null
cli SET "admin:token:${DEFAULT_ADMIN_TOKEN}" '{"creator":"bootstrap","expire_at":0}' >/dev/null
