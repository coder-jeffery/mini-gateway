#!/usr/bin/env bash
# Signed admin API call.
# Usage: ./test/admin_call.sh whitelist_add '{"ip":"127.0.0.1"}'
#        ./test/admin_call.sh upsert_apikey '{"api_key":"abc123","limit":20,"window":30}'
set -euo pipefail

BASE_URL="${ADMIN_GW_URL:-http://127.0.0.1:8080/admin/gw}"
SECRET="${ADMIN_SECRET:-admin-secret-2026}"
ACTION="${1:?action required (e.g. whitelist_add)}"
# Do not use ${2:-{}} — bash treats the first "}" as closing the expansion and appends an extra "}"
if [[ $# -ge 2 ]]; then
  EXTRA_JSON="$2"
else
  EXTRA_JSON="{}"
fi

TS=$(date +%s)
NONCE=$(uuidgen 2>/dev/null | tr -d ' \n' | tr '[:upper:]' '[:lower:]' || tr -d ' \n' </proc/sys/kernel/random/uuid)
RAW="${TS}:${NONCE}"
SIGN=$(printf '%s' "$RAW" | openssl dgst -sha256 -hmac "$SECRET" | awk '{print $NF}')

# Pass JSON via env — avoids zsh/bash mangling braces or splitting argv
export ADMIN_CALL_URL="$BASE_URL"
export ADMIN_CALL_TS="$TS"
export ADMIN_CALL_NONCE="$NONCE"
export ADMIN_CALL_SIGN="$SIGN"
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
    ts = int(os.environ["ADMIN_CALL_TS"])
    nonce = os.environ["ADMIN_CALL_NONCE"]
    sign = os.environ["ADMIN_CALL_SIGN"]
    action = os.environ["ADMIN_CALL_ACTION"]
    extra_raw = os.environ.get("ADMIN_CALL_EXTRA", "{}").strip()
    if not extra_raw:
        extra_raw = "{}"
    try:
        extra = json.loads(extra_raw)
    except json.JSONDecodeError as e:
        act = os.environ.get("ADMIN_CALL_ACTION", "ACTION")
        print(
            f"Invalid EXTRA JSON: {extra_raw!r}\n"
            f"Wrap JSON in single quotes, e.g. ./test/admin_call.sh {act} '{{\"ip\":\"127.0.0.1\"}}'\n"
            f"{e}",
            file=sys.stderr,
        )
        sys.exit(2)
    if not isinstance(extra, dict):
        print("EXTRA JSON must be an object, e.g. {\"ip\":\"127.0.0.1\"}", file=sys.stderr)
        sys.exit(2)

    body = {"ts": ts, "nonce": nonce, "sign": sign, "action": action}
    body.update(extra)
    data = json.dumps(body).encode()
    req = urllib.request.Request(
        url, data=data, headers={"Content-Type": "application/json"}, method="POST"
    )
    try:
        with urllib.request.urlopen(req) as resp:
            print(resp.read().decode())
    except urllib.error.HTTPError as e:
        print(e.read().decode(), file=sys.stderr)
        sys.exit(1)

main()
PY
