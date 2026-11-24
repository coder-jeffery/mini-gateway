#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=scripts/lib/ci-compose.env
source "$ROOT/scripts/lib/ci-compose.env"

# shellcheck disable=SC2086
docker compose $COMPOSE_CI_FILES down -v || true