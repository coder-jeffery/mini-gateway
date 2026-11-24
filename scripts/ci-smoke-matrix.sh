#!/usr/bin/env bash
# M6: smoke suite on all supported storage backends.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for storage in memory sqlite redis; do
  "$ROOT/scripts/ci-smoke-storage.sh" "$storage"
done
echo "ci-smoke-matrix: all storage backends passed"