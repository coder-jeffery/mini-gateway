#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
docker compose --profile redis stop 2>/dev/null || true
docker compose down --remove-orphans
