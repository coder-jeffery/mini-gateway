#!/usr/bin/env bash
# HMAC-signed call to POST /admin/gw/v1
# Usage:
#   ./test/hmac_call.sh                    # default action: hmac_test
#   ./test/hmac_call.sh whitelist_list
#   ./test/hmac_call.sh apikey_list '{"page":1,"page_size":10}'
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ACTION="${1:-hmac_test}"
EXTRA_JSON="${2:-{}}"

export ROOT
export ADMIN_GW_V1_URL="${ADMIN_GW_V1_URL:-http://127.0.0.1:8080/admin/gw/v1}"
export GATEWAY_ADMIN_SECRET="${GATEWAY_ADMIN_SECRET:-admin-secret-2026}"
export HMAC_CALL_ACTION="$ACTION"
export HMAC_CALL_EXTRA="$EXTRA_JSON"

python3 <<'PY'
import json
import os
import sys

sys.path.insert(0, os.path.join(os.environ["ROOT"], "test"))
from hmac_client import admin_url, post_admin_v1, signed_payload

def main() -> None:
    action = os.environ["HMAC_CALL_ACTION"]
    extra_raw = os.environ.get("HMAC_CALL_EXTRA", "{}").strip() or "{}"
    try:
        extra = json.loads(extra_raw)
    except json.JSONDecodeError as e:
        print(f"Invalid EXTRA JSON: {extra_raw!r}\n{e}", file=sys.stderr)
        sys.exit(2)
    if not isinstance(extra, dict):
        print("EXTRA JSON must be an object", file=sys.stderr)
        sys.exit(2)

    body = signed_payload(action, **extra)
    target = admin_url()
    print("入参:")
    print("  Method: POST")
    print(f"  URL: {target}")
    print("  Body:")
    print(json.dumps(body, ensure_ascii=False, indent=4))
    print()
    status, data = post_admin_v1(body, url=target)
    print("响应:")
    print(json.dumps({"http_status": status, "body": data}, ensure_ascii=False, indent=2))
    if status >= 400 or not data.get("ok"):
        sys.exit(1)

main()
PY
