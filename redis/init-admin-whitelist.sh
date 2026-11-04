#!/bin/sh
set -eu

REDIS_HOST="${REDIS_HOST:-redis}"
# Comma-separated list, e.g. 127.0.0.1,192.168.1.10,192.168.65.1
IPS="${ADMIN_WHITELIST_IPS:-127.0.0.1,172.17.0.1,192.168.65.1}"

until redis-cli -h "$REDIS_HOST" ping 2>/dev/null | grep -q PONG; do
  sleep 0.5
done

added=""
for ip in $(echo "$IPS" | tr ',' ' '); do
  ip=$(echo "$ip" | tr -d ' ')
  [ -z "$ip" ] && continue
  redis-cli -h "$REDIS_HOST" SADD "admin:whitelist:ip" "$ip" >/dev/null
  if [ -z "$added" ]; then
    added="$ip"
  else
    added="$added, $ip"
  fi
done

echo "admin whitelist seeded: $added"
