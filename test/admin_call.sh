#!/usr/bin/env bash
# Admin API call with bootstrap Bearer token (default: mini-token).
# Usage: ./test/admin_call.sh whitelist_add '{"ip":"127.0.0.1"}'
set -euo pipefail

BASE_URL="${ADMIN_GW_URL:-http://127.0.0.1:8080/admin/gw}"
ADMIN_TOKEN="${ADMIN_TOKEN:-mini-token}"
ACTION="${1:?action required (e.g. whitelist_add)}"
if [[ $# -ge 2 ]]; then
  EXTRA_JSON="$2"
else
  EXTRA_JSON="{}"
fi

export ADMIN_CALL_URL="$BASE_URL"
export ADMIN_CALL_TOKEN="$ADMIN_TOKEN"
export ADMIN_CALL_ACTION="$ACTION"
export ADMIN_CALL_EXTRA="$EXTRA_JSON"

python3 <<'PY'
import json
import os
import sys
import urllib.error
import urllib.request

def main() -> None:
    url = os.environ["ADMIN_CALL_URL"]
    token = os.environ["ADMIN_CALL_TOKEN"]
    action = os.environ["ADMIN_CALL_ACTION"]
    extra_raw = os.environ.get("ADMIN_CALL_EXTRA", "{}").strip() or "{}"
    try:
        extra = json.loads(extra_raw)
    except json.JSONDecodeError as e:
        act = os.environ.get("ADMIN_CALL_ACTION", "ACTION")
        print(
            f"Invalid EXTRA JSON: {extra_raw!r}\n"
            f"Use single quotes, e.g. ./test/admin_call.sh {act} '{{\"ip\":\"127.0.0.1\"}}'\n{e}",
            file=sys.stderr,
        )
        sys.exit(2)
    if not isinstance(extra, dict):
        print("EXTRA JSON must be an object", file=sys.stderr)
        sys.exit(2)

    body = {"action": action}
    body.update(extra)
    data = json.dumps(body).encode()
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {token}",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req) as resp:
            print(resp.read().decode())
    except urllib.error.HTTPError as e:
        print(e.read().decode(), file=sys.stderr)
        sys.exit(1)

main()
PY
