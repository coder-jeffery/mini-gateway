#!/usr/bin/env python3
"""Redaction, admin HMAC configuration, and service routing.

Uses local mock upstreams only. Redis and SQLite are used when available.
REQUIRE_REDIS=1 or REQUIRE_SQLITE=1 turns a missing backend into a failure.
"""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import signal
import socket
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from hmac_client import post_admin_v1, signed_payload  # noqa: E402

REPO = Path(__file__).resolve().parents[1]
NGINX_CONF = REPO / "nginx" / "conf" / "nginx.conf"
LUA_DIR = REPO / "nginx" / "lua"
OPENRESTY = shutil.which("openresty")
REDIS_CLI = shutil.which("redis-cli")
MIME_CANDIDATES = [
    Path("/usr/local/openresty/nginx/conf/mime.types"),
]
TEST_SECRET = "test-only-hmac-secret"
API_KEY = "mini-key"


class MockHandler(BaseHTTPRequestHandler):
    def _handle(self) -> None:
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        self.server.hits.append(  # type: ignore[attr-defined]
            {"method": self.command, "raw_path": self.path, "body": body}
        )
        payload = json.dumps(
            {"method": self.command, "raw_path": self.path, "body": body.decode("latin1")}
        ).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self) -> None:
        self._handle()

    def do_POST(self) -> None:
        self._handle()

    def do_PUT(self) -> None:
        self._handle()

    def do_OPTIONS(self) -> None:
        self._handle()

    def log_message(self, fmt: str, *args) -> None:
        return


def free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def port_open(port: int) -> bool:
    with socket.socket() as sock:
        sock.settimeout(0.2)
        return sock.connect_ex(("127.0.0.1", port)) == 0


class Gateway:
    def __init__(self, peers: str, extra: dict[str, str] | None = None):
        self.peers = peers
        self.extra = extra or {}
        self.prefix = tempfile.TemporaryDirectory(prefix="gw-sec-")
        self.proc: subprocess.Popen | None = None

    def start(self) -> None:
        root = Path(self.prefix.name)
        conf_dir = root / "conf"
        log_dir = root / "logs"
        conf_dir.mkdir()
        log_dir.mkdir()
        mime = next(p for p in MIME_CANDIDATES if p.is_file())
        shutil.copy(mime, conf_dir / "mime.types")
        text = NGINX_CONF.read_text()
        text = text.replace("/usr/local/openresty/nginx/lua/", f"{LUA_DIR.as_posix()}/")
        text = text.replace("worker_processes  auto;", "worker_processes 1;")
        (conf_dir / "nginx.conf").write_text(text)
        env = os.environ.copy()
        env.pop("GATEWAY_UPSTREAM_PATH", None)
        env.pop("GATEWAY_ADMIN_SECRET", None)
        env.update(
            {
                "GATEWAY_STORAGE": "memory",
                "GATEWAY_AUTH_MODE": "api_key",
                "DEFAULT_API_KEY": API_KEY,
                "DEFAULT_API_KEY_LIMIT": "1000",
                "DEFAULT_API_KEY_WINDOW": "60",
                "DEFAULT_ADMIN_TOKEN": "mini-token",
                "ADMIN_WHITELIST_IPS": "127.0.0.1",
                "GATEWAY_ADMIN_TRUST_PRIVATE": "1",
                "GATEWAY_UPSTREAM_SCHEME": "http",
                "GATEWAY_UPSTREAM_PEERS": self.peers,
                "GATEWAY_UPSTREAM_HOST": "127.0.0.1",
                "GATEWAY_UPSTREAM_HEALTH_PATH": "/status/200",
                "GATEWAY_UPSTREAM_HEALTH_INTERVAL": "3600",
                "GATEWAY_UPSTREAM_HEALTH_FAIL_THRESHOLD": "1000",
                "GATEWAY_UPSTREAM_MAX_TRIES": "2",
                "GATEWAY_REDIS_HOST": os.environ.get("REDIS_HOST", "127.0.0.1"),
                "GATEWAY_REDIS_PORT": os.environ.get("REDIS_PORT", "6379"),
            }
        )
        env.update(self.extra)
        self.proc = subprocess.Popen(
            [OPENRESTY, "-p", str(root), "-c", str(conf_dir / "nginx.conf"), "-g", "daemon off;"],
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            start_new_session=True,
        )
        deadline = time.time() + 8
        while time.time() < deadline:
            if self.proc.poll() is not None:
                err = self.proc.stderr.read().decode() if self.proc.stderr else ""
                log = (log_dir / "error.log").read_text() if (log_dir / "error.log").is_file() else ""
                raise SystemExit(f"openresty exited\n{err}\n{log}")
            if port_open(8080):
                return
            time.sleep(0.05)
        log = (log_dir / "error.log").read_text() if (log_dir / "error.log").is_file() else ""
        raise SystemExit(f"gateway did not listen\n{log}")

    def stop(self) -> None:
        if self.proc is not None and self.proc.poll() is None:
            os.killpg(self.proc.pid, signal.SIGTERM)
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(self.proc.pid, signal.SIGKILL)
                self.proc.wait(timeout=5)
        self.prefix.cleanup()

    def error_log(self) -> str:
        path = Path(self.prefix.name) / "logs" / "error.log"
        return path.read_text() if path.is_file() else ""


def call(method: str, target: str, body: bytes | None = None, headers: dict | None = None):
    import http.client

    conn = http.client.HTTPConnection("127.0.0.1", 8080, timeout=5)
    try:
        conn.request(method, target, body=body, headers=headers or {})
        resp = conn.getresponse()
        payload = resp.read()
        header_map = {k.lower(): v for k, v in resp.getheaders()}
        return resp.status, payload, header_map
    finally:
        conn.close()


def wait_ready(storage: str) -> None:
    last = ""
    for _ in range(40):
        try:
            status, payload, _headers = call("GET", "/ready")
            last = payload.decode()
            if status == 200 and json.loads(payload).get("storage") == storage:
                return
        except OSError:
            pass
        time.sleep(0.05)
    raise SystemExit(f"/ready not {storage}: {last}")


def redis_cmd(*args: str) -> str:
    if not REDIS_CLI:
        raise SystemExit("redis-cli is required")
    host = os.environ.get("REDIS_HOST", "127.0.0.1")
    port = os.environ.get("REDIS_PORT", "6379")
    proc = subprocess.run(
        [REDIS_CLI, "-h", host, "-p", port, *args],
        check=True,
        capture_output=True,
        text=True,
    )
    return proc.stdout


def fingerprint(secret: str) -> str:
    return "fp_" + hashlib.sha256(secret.encode()).hexdigest()[:16]


def start_mock() -> ThreadingHTTPServer:
    server = ThreadingHTTPServer(("127.0.0.1", 0), MockHandler)
    server.hits = []  # type: ignore[attr-defined]
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def admin_v0(action: str, **fields) -> tuple[int, dict]:
    payload = json.dumps({"action": action, **fields}).encode()
    status, body, _headers = call(
        "POST",
        "/admin/gw",
        body=payload,
        headers={"Authorization": "Bearer mini-token", "Content-Type": "application/json"},
    )
    return status, json.loads(body.decode() or "{}")


def expect_proxy(method: str, target: str, raw_path: str, headers: dict) -> None:
    status, payload, _headers = call(method, target, headers=headers)
    if status != 200:
        raise SystemExit(f"{method} {target} -> {status} {payload!r}")
    data = json.loads(payload.decode())
    if data.get("raw_path") != raw_path:
        raise SystemExit(f"{target} forwarded as {data!r}, want {raw_path}")
    print(f"ok {method} {target} -> {raw_path}")


def test_hmac_and_logs(redis_port: str) -> None:
    os.environ["REDIS_PORT"] = redis_port
    redis_cmd("FLUSHDB")
    redis_cmd("SET", f"apikey:{API_KEY}", "1")
    redis_cmd("HSET", f"apikey:meta:{API_KEY}", "limit", "1000", "window", "60")
    redis_cmd("DEL", "gateway:access_log")
    mock = start_mock()
    port = mock.server_address[1]
    missing = Gateway(
        f"127.0.0.1:{port}",
        {"GATEWAY_STORAGE": "memory"},
    )
    secured = None
    short = None
    try:
        missing.start()
        status, payload, _headers = call(
            "POST",
            "/admin/gw/v1",
            body=b'{"action":"hmac_test"}',
            headers={"Content-Type": "application/json"},
        )
        data = json.loads(payload.decode() or "{}")
        if status != 503 or data.get("msg") != "admin hmac secret is not configured":
            raise SystemExit(f"missing secret -> {status} {payload!r}")
        if TEST_SECRET in payload.decode() or "admin-secret" in payload.decode():
            raise SystemExit("secret error leaked a secret value")
        print("ok hmac missing secret fails closed")
        missing.stop()
        missing = None

        short = Gateway(
            f"127.0.0.1:{port}",
            {"GATEWAY_STORAGE": "memory", "GATEWAY_ADMIN_SECRET": "too-short"},
        )
        short.start()
        status, payload, _headers = call(
            "POST",
            "/admin/gw/v1",
            body=b'{"action":"hmac_test"}',
            headers={"Content-Type": "application/json"},
        )
        data = json.loads(payload.decode() or "{}")
        if status != 503 or data.get("msg") != "admin hmac secret must be at least 16 characters":
            raise SystemExit(f"short secret -> {status} {payload!r}")
        if "too-short" in payload.decode():
            raise SystemExit("short secret error leaked the value")
        print("ok hmac short secret fails closed")
        short.stop()
        short = None

        secured = Gateway(
            f"127.0.0.1:{port}",
            {
                "GATEWAY_STORAGE": "redis",
                "GATEWAY_ADMIN_SECRET": TEST_SECRET,
                "GATEWAY_REDIS_PORT": redis_port,
            },
        )
        os.environ["GATEWAY_ADMIN_SECRET"] = TEST_SECRET
        os.environ["ADMIN_GW_V1_URL"] = "http://127.0.0.1:8080/admin/gw/v1"
        secured.start()
        wait_ready("redis")
        status, data = post_admin_v1(signed_payload("hmac_test"))
        if status != 200 or data.get("msg") != "hmac verified":
            raise SystemExit(f"hmac ok -> {status} {data}")
        bad = signed_payload("hmac_test", sign="00" * 32)
        status, data = post_admin_v1(bad)
        if status != 403 or data.get("msg") != "invalid signature":
            raise SystemExit(f"bad sign -> {status} {data}")
        old = signed_payload("hmac_test", ts=int(time.time()) - 120)
        status, data = post_admin_v1(old)
        if status != 403 or data.get("msg") != "signature expired":
            raise SystemExit(f"expired -> {status} {data}")
        replay = signed_payload("hmac_test")
        status, data = post_admin_v1(replay)
        if status != 200:
            raise SystemExit(f"replay first -> {status} {data}")
        status, data = post_admin_v1(replay)
        if status != 403 or "nonce" not in str(data.get("msg")):
            raise SystemExit(f"replay second -> {status} {data}")
        print("ok hmac signature, timestamp, and nonce")

        status, payload, headers = call("GET", "/v1/orders?a=1", headers={"X-Api-Key": API_KEY})
        if status != 200:
            raise SystemExit(f"logged request -> {status} {payload!r}")
        if not headers.get("x-request-id"):
            raise SystemExit("missing X-Request-Id")
        fp = fingerprint(API_KEY)
        found = ""
        for _ in range(30):
            found = redis_cmd("LRANGE", "gateway:access_log", "0", "-1")
            if fp in found:
                break
            time.sleep(0.05)
        normalized = found.replace("\\/", "/")
        if API_KEY in normalized or "Bearer" in normalized or TEST_SECRET in normalized:
            raise SystemExit(f"access log leaked a credential: {found}")
        if fp not in normalized or '"status":200' not in normalized.replace(" ", ""):
            raise SystemExit(f"access log missing fingerprint or status: {found}")
        if "/v1/orders" not in normalized:
            raise SystemExit(f"access log missing uri: {found}")
        print("ok redis access log redacted")
    finally:
        mock.shutdown()
        if missing is not None:
            missing.stop()
        if short is not None:
            short.stop()
        if secured is not None:
            secured.stop()
        os.environ.pop("GATEWAY_ADMIN_SECRET", None)


def test_sqlite_log(db_path: Path) -> None:
    mock = start_mock()
    gw = Gateway(
        f"127.0.0.1:{mock.server_address[1]}",
        {
            "GATEWAY_STORAGE": "sqlite",
            "GATEWAY_SQLITE_PATH": str(db_path),
        },
    )
    try:
        gw.start()
        status, payload, _headers = call("GET", "/ready")
        if status != 200:
            if os.environ.get("REQUIRE_SQLITE") == "1":
                raise SystemExit(f"sqlite required but /ready returned {status} {payload!r}")
            print(f"SKIP sqlite ({payload.decode()[:180]})")
            return
        status, payload, _headers = call("GET", "/sqlite-log", headers={"X-Api-Key": API_KEY})
        if status != 200:
            raise SystemExit(f"sqlite proxy {status} {payload!r}")
        blob = ""
        for _ in range(40):
            if db_path.is_file():
                conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
                try:
                    rows = [row[0] for row in conn.execute("SELECT v FROM access_log")]
                except sqlite3.OperationalError:
                    rows = []
                finally:
                    conn.close()
                blob = "\n".join(rows)
                if fingerprint(API_KEY) in blob:
                    break
            time.sleep(0.05)
        gw.stop()
        gw = None
        if API_KEY in blob:
            raise SystemExit(f"sqlite log leaked api key: {blob}")
        if fingerprint(API_KEY) not in blob:
            raise SystemExit(f"sqlite log missing fingerprint: {blob}")
        print("ok sqlite access log redacted")
    finally:
        mock.shutdown()
        if gw is not None:
            gw.stop()


def create_service(name: str, prefix: str, url: str, peers: str = "", **cors) -> dict:
    fields = {
        "name": name,
        "path_prefix": prefix,
        "upstream_url": url,
        "upstream_peers": peers,
        "cors_enabled": cors.get("cors_enabled", 0),
        "cors_allow_origins": cors.get("cors_allow_origins", ""),
        "cors_allow_methods": cors.get("cors_allow_methods", "GET,POST,OPTIONS"),
        "cors_allow_headers": cors.get("cors_allow_headers", "Content-Type,X-Api-Key"),
        "cors_allow_credentials": cors.get("cors_allow_credentials", 0),
    }
    status, data = admin_v0("service_create", **fields)
    if status != 201 or not data.get("ok"):
        raise SystemExit(f"create {name} -> {status} {data}")
    return data["service"]


def test_routes() -> None:
    default = start_mock()
    orders = start_mock()
    billing = start_mock()
    dead = free_port()
    key = {"X-Api-Key": API_KEY}
    gw = Gateway(
        f"127.0.0.1:{default.server_address[1]}",
        {"GATEWAY_UPSTREAM_PATH": "/legacy"},
    )
    try:
        gw.start()
        wait_ready("memory")
        status, data = admin_v0(
            "service_create",
            name="reserved",
            path_prefix="/admin",
            upstream_url=f"http://127.0.0.1:{orders.server_address[1]}",
            cors_enabled=0,
        )
        if status != 400 or "reserved" not in str(data.get("msg")):
            raise SystemExit(f"reserved prefix -> {status} {data}")
        status, data = admin_v0(
            "service_create",
            name="star",
            path_prefix="/star",
            upstream_url=f"http://127.0.0.1:{orders.server_address[1]}",
            cors_enabled=1,
            cors_allow_origins="*",
            cors_allow_credentials=1,
        )
        if status != 400:
            raise SystemExit(f"credentials star -> {status} {data}")
        print("ok service validation")

        create_service(
            "orders",
            "/api/orders",
            f"http://127.0.0.1:{orders.server_address[1]}",
            f"127.0.0.1:{dead}:1,127.0.0.1:{orders.server_address[1]}:1",
            cors_enabled=1,
            cors_allow_origins="https://app.example",
            cors_allow_methods="GET,POST,OPTIONS",
            cors_allow_headers="Content-Type,X-Api-Key",
        )
        create_service(
            "api",
            "/api",
            f"http://127.0.0.1:{billing.server_address[1]}",
        )
        before = len(orders.hits)
        status, payload, headers = call(
            "OPTIONS",
            "/api/orders",
            headers={
                "Origin": "https://app.example",
                "Access-Control-Request-Method": "GET",
                "Access-Control-Request-Headers": "content-type,x-api-key",
            },
        )
        if status != 204 or headers.get("access-control-allow-origin") != "https://app.example":
            raise SystemExit(f"preflight -> {status} {payload!r} {headers}")
        if len(orders.hits) != before:
            raise SystemExit("preflight reached the upstream")
        status, payload, _headers = call(
            "OPTIONS",
            "/api/orders",
            headers={
                "Origin": "https://evil.example",
                "Access-Control-Request-Method": "GET",
            },
        )
        if status != 403:
            raise SystemExit(f"bad origin -> {status} {payload!r}")
        print("ok service CORS")

        before = len(orders.hits)
        status, payload, _headers = call("GET", "/api/orders/a%2Fb?x=1&x=2")
        if status != 401 or len(orders.hits) != before:
            raise SystemExit(f"missing key was proxied: {status} hits {len(orders.hits)}")
        print("ok routed request still requires auth")

        expect_proxy("GET", "/api/orders/a%2Fb?x=1&x=2", "/api/orders/a%2Fb?x=1&x=2", key)
        if not orders.hits or orders.hits[-1]["raw_path"] != "/api/orders/a%2Fb?x=1&x=2":
            raise SystemExit(f"orders mock saw {orders.hits[-1] if orders.hits else None}")
        expect_proxy("GET", "/api/orders-v2?q=a+b", "/api/orders-v2?q=a+b", key)
        if billing.hits[-1]["raw_path"] != "/api/orders-v2?q=a+b":
            raise SystemExit("boundary prefix matched the longer service")
        expect_proxy("GET", "/api/other", "/api/other", key)
        if billing.hits[-1]["raw_path"] != "/api/other":
            raise SystemExit("shorter prefix did not receive /api/other")
        expect_proxy("GET", "/unmatched?a=1&a=2", "/legacy", key)
        if default.hits[-1]["raw_path"] != "/legacy":
            raise SystemExit(f"no-match did not use legacy path: {default.hits[-1]}")
        print("ok prefix match, encoding, no-match legacy")

        status, payload, headers = call(
            "GET",
            "/api/orders/1",
            headers={**key, "Origin": "https://app.example"},
        )
        if status != 200 or headers.get("access-control-allow-origin") != "https://app.example":
            raise SystemExit(f"cors on response -> {status} {headers}")
        print("ok CORS on authenticated response")

        status, data = admin_v0(
            "upsert_apikey",
            api_key="route-limit",
            limit=1,
            window=60,
        )
        if status != 200:
            raise SystemExit(f"upsert limit key -> {status} {data}")
        status, _payload, _headers = call("GET", "/api/other/once", headers={"X-Api-Key": "route-limit"})
        if status != 200:
            raise SystemExit(f"first limited -> {status}")
        before = len(billing.hits)
        status, payload, _headers = call("GET", "/api/other/twice", headers={"X-Api-Key": "route-limit"})
        if status != 429 or len(billing.hits) != before:
            raise SystemExit(f"rate limit did not stop the routed call: {status}")
        print("ok routed rate limit")

        expect_proxy("GET", "/api/orders/retry/one?a=1", "/api/orders/retry/one?a=1", key)
        expect_proxy("GET", "/api/orders/retry/two%2Fok", "/api/orders/retry/two%2Fok", key)
        if str(dead) not in gw.error_log() or "connect() failed" not in gw.error_log():
            raise SystemExit("service failover did not touch the dead peer\n" + gw.error_log()[-1500:])
        expect_proxy("GET", "/api/isolated", "/api/isolated", key)
        if billing.hits[-1]["raw_path"] != "/api/isolated":
            raise SystemExit("billing service was affected by the orders failover")
        print("ok per-service failover isolation")

        status, payload, _headers = call(
            "POST",
            "/admin/gw",
            body=b'{"action":"service_list"}',
            headers={"Authorization": "Bearer mini-token", "Content-Type": "application/json"},
        )
        listed = json.loads(payload.decode())
        if status != 200 or not listed.get("ok") or any(item["raw_path"].startswith("/admin") for item in default.hits + orders.hits + billing.hits):
            raise SystemExit(f"admin list was proxied or failed: {status} {payload!r}")
        print("ok admin route stays on the gateway")
    finally:
        for server in (default, orders, billing):
            server.shutdown()
        gw.stop()


def main() -> None:
    if not OPENRESTY:
        raise SystemExit("openresty is required")
    if port_open(8080):
        raise SystemExit("port 8080 is already in use")
    redis_port = os.environ.get("REDIS_PORT", "6379")
    if port_open(int(redis_port)) and REDIS_CLI:
        test_hmac_and_logs(redis_port)
    elif os.environ.get("REQUIRE_REDIS") == "1":
        raise SystemExit("redis is required but not reachable")
    else:
        print("SKIP redis hmac/log tests (redis not reachable)")
    with tempfile.TemporaryDirectory() as tmp:
        test_sqlite_log(Path(tmp) / "gateway.db")
    test_routes()
    print("all security and route tests passed")


if __name__ == "__main__":
    main()
