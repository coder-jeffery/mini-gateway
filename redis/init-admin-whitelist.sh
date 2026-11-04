#!/bin/sh
set -eu

REDIS_HOST="${REDIS_HOST:-redis}"
ADMIN_IP="${ADMIN_WHITELIST_IP:-192.168.65.1}"

until redis-cli -h "$REDIS_HOST" ping 2>/dev/null | grep -q PONG; do
  sleep 0.5
done

redis-cli -h "$REDIS_HOST" SADD "admin:whitelist:ip" "$ADMIN_IP" >/dev/null
echo "admin whitelist: SADD admin:whitelist:ip ${ADMIN_IP}"
