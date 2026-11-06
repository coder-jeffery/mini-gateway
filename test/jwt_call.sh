#!/usr/bin/env bash
# Bearer JWT 调用业务网关 GET /
#
# Usage:
#   ./test/jwt_call.sh valid
#   ./test/jwt_call.sh expired
#   ./test/jwt_call.sh token valid          # 仅输出 JWT
#   ./test/jwt_call.sh curl valid           # 仅输出 curl
#   ./test/jwt_call.sh all                  # 批量 JWT 用例
#
# Env: GATEWAY_URL, OAUTH2_JWT_SECRET, OAUTH2_ISSUER, OAUTH2_AUDIENCE, OAUTH2_REQUIRED_SCOPE
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export ROOT
export GATEWAY_URL="${GATEWAY_URL:-http://127.0.0.1:8080/}"
export OAUTH2_JWT_SECRET="${OAUTH2_JWT_SECRET:-oauth2-dev-secret}"

CMD="${1:-valid}"
CASE="${2:-valid}"

if [[ "$CMD" == "token" || "$CMD" == "curl" ]]; then
  CASE="${2:-valid}"
fi

export JWT_CMD="$CMD"
export JWT_CASE="$CASE"

python3 <<'PY'
import json
import os
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.join(os.environ["ROOT"], "test"))
from jwt_client import build_case, gateway_url

cmd = os.environ["JWT_CMD"]
case_id = os.environ["JWT_CASE"]


def curl_cmd(token: str | None) -> str:
    url = gateway_url()
    if token:
        return (
            f'curl -i -H "Authorization: Bearer {token}" '
            f'-H "Accept: application/json" "{url}"'
        )
    return f'curl -i -H "Accept: application/json" "{url}"'


def do_request(token: str | None) -> tuple[int, object]:
    url = gateway_url()
    headers = {"Accept": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, headers=headers, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            body = resp.read().decode()
            try:
                data = json.loads(body)
            except json.JSONDecodeError:
                data = body
            return resp.status, data
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            data = {"msg": raw}
        return e.code, data


def emit_case(cid: str, *, send: bool) -> None:
    payload, secret_override, token = build_case(cid)
    if cmd == "token":
        print(token)
        return
    if cmd == "curl":
        print(curl_cmd(token))
        return

    print(f"=== case: {cid} ===")
    print("payload:")
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    if secret_override:
        print(f"sign_secret: {secret_override}")
    print(f"\nJWT:\n{token}\n")
    print("curl:")
    print(curl_cmd(token))
    print()
    if send:
        status, data = do_request(token)
        print("response:")
        print(json.dumps({"http_status": status, "body": data}, ensure_ascii=False, indent=2))
        print()


if cmd == "all":
    cases = [
        "valid",
        "valid_client",
        "expired",
        "bad_sig",
        "wrong_secret",
        "missing_exp",
    ]
    if os.environ.get("OAUTH2_AUDIENCE", "").strip():
        cases.append("wrong_audience")
    if os.environ.get("OAUTH2_REQUIRED_SCOPE", "").strip():
        cases.append("missing_scope")
    for cid in cases:
        emit_case(cid, send=True)
    print("=== case: no_bearer ===")
    print(curl_cmd(None))
    status, data = do_request(None)
    print(json.dumps({"http_status": status, "body": data}, ensure_ascii=False, indent=2))
    sys.exit(0)

if cmd in ("token", "curl"):
    emit_case(case_id, send=False)
    sys.exit(0)

emit_case(cmd, send=True)
PY
