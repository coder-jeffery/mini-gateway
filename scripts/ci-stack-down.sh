#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# Prefer caller-exported COMPOSE_CI_FILES (e.g. redis/sqlite overlays).
if [[ -z "${COMPOSE_CI_FILES:-}" ]]; then
  # shellcheck source=scripts/lib/ci-compose.env
  source "$ROOT/scripts/lib/ci-compose.env"
fi

# shellcheck disable=SC2086
docker compose $COMPOSE_CI_FILES down -v || true