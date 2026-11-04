#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

docker compose up -d
echo "Gateway is up. Admin whitelist default: admin:whitelist:ip -> ${ADMIN_WHITELIST_IP:-192.168.65.1}"
echo "Override IP: ADMIN_WHITELIST_IP=127.0.0.1 docker compose up -d"
