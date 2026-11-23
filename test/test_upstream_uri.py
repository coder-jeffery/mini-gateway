#!/usr/bin/env python3
"""Gateway request-target passthrough against a local mock upstream.

Requires the openresty binary. Does not call external hosts.
The nginx.conf under test is the repo file; only the lua directory prefix
and worker_processes are rewritten in a temporary copy so the suite can run
outside the Docker image layout.
"""

from __future__ import annotations

import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
NGINX_CONF = REPO / "nginx" / "conf" / "nginx.conf"
LUA_DIR = REPO / "nginx" / "lua"
OPENRESTY = shutil.which("openresty")
MIME_CANDIDATES = [
    Path("/usr/local/openresty/nginx/conf/mime.types"),
    Path("/usr/local/openresty/nginx/conf/mime.types.default"),
]


class MockHandler(BaseHTTPRequestHandler):
    def _handle(self) -> None:
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        self.server.hits.append(  # type: ignore[attr-defined]
            {"method": self.command, "raw_path": self.path, "body": body}
        )
        payload = json.dumps(
            {
                "method": self.command,
                "raw_path": self.path,
                "body": body.decode("latin1"),
            }
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
    def __init__(self, upstream_peers: str, upstream_path: str | None = None, extra_env: dict | None = None):
        self.upstream_peers = upstream_peers
        self.upstream_path = upstream_path
        self.extra_env = extra_env or {}
        self.prefix = tempfile.TemporaryDirectory(prefix="gw-uri-")
        self.proc: subprocess.Popen | None = None

    def start(self) -> None:
        root = Path(self.prefix.name)
        conf_dir = root / "conf"
        log_dir = root / "logs"
        conf_dir.mkdir()
        log_dir.mkdir()
        mime = next((p for p in MIME_CANDIDATES if p.is_file()), None)
        if mime is None:
            raise SystemExit("mime.types not found next to the OpenResty install")
        shutil.copy(mime, conf_dir / "mime.types")
        text = NGINX_CONF.read_text()
        text = text.replace("/usr/local/openresty/nginx/lua/", f"{LUA_DIR.as_posix()}/")
        text = text.replace("worker_processes  auto;", "worker_processes 1;")
        if "proxy_pass $gateway_upstream_scheme://gateway_backend$gateway_upstream_path;" not in text:
            raise SystemExit("repo nginx.conf proxy_pass line changed; update this test")
        (conf_dir / "nginx.conf").write_text(text)

        env = os.environ.copy()
        # Do not inherit a developer override.
        env.pop("GATEWAY_UPSTREAM_PATH", None)
        env.update(
            {
                "GATEWAY_STORAGE": "memory",
                "GATEWAY_AUTH_MODE": "api_key",
                "DEFAULT_API_KEY": "mini-key",
                "DEFAULT_API_KEY_LIMIT": "1000",
                "DEFAULT_API_KEY_WINDOW": "60",
                "DEFAULT_ADMIN_TOKEN": "mini-token",
                "ADMIN_WHITELIST_IPS": "127.0.0.1",
                "GATEWAY_UPSTREAM_SCHEME": "http",
                "GATEWAY_UPSTREAM_PEERS": self.upstream_peers,
                "GATEWAY_UPSTREAM_HOST": "127.0.0.1",
                "GATEWAY_UPSTREAM_HEALTH_PATH": "/status/200",
                "GATEWAY_UPSTREAM_HEALTH_INTERVAL": "3600",
                "GATEWAY_UPSTREAM_HEALTH_FAIL_THRESHOLD": "1000",
                "GATEWAY_UPSTREAM_MAX_TRIES": "2",
            }
        )
        if self.upstream_path is not None:
            env["GATEWAY_UPSTREAM_PATH"] = self.upstream_path
        env.update(self.extra_env)

        self.proc = subprocess.Popen(
            [
                OPENRESTY,
                "-p",
                str(root),
                "-c",
                str(conf_dir / "nginx.conf"),
                "-g",
                "daemon off;",
            ],
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
                raise SystemExit(f"openresty exited early\n{err}\n{log}")
            if port_open(8080):
                return
            time.sleep(0.05)
        log = (log_dir / "error.log").read_text() if (log_dir / "error.log").is_file() else ""
        raise SystemExit(f"gateway did not listen on 8080\n{log}")

    def stop(self) -> None:
        if self.proc is not None and self.proc.poll() is None:
            os.killpg(self.proc.pid, signal.SIGTERM)
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(self.proc.pid, signal.SIGKILL)
                self.proc.wait(timeout=5)
        self.prefix.cleanup()


def call(method: str, target: str, body: bytes | None = None, headers: dict | None = None):
    import http.client

    conn = http.client.HTTPConnection("127.0.0.1", 8080, timeout=5)
    try:
        conn.request(method, target, body=body, headers=headers or {})
        resp = conn.getresponse()
        payload = resp.read()
        return resp.status, payload
    finally:
        conn.close()


def expect_upstream(method: str, target: str, raw_path: str, body: bytes = b"", headers: dict | None = None) -> None:
    status, payload = call(method, target, body=body or None, headers=headers)
    if status != 200:
        raise SystemExit(f"{method} {target} -> {status} {payload!r}")
    data = json.loads(payload.decode())
    if data.get("method") != method or data.get("raw_path") != raw_path:
        raise SystemExit(f"{method} {target} forwarded as {data!r}, want {raw_path}")
    if data.get("body", "").encode("latin1") != body:
        raise SystemExit(f"body mismatch for {target}: {data.get('body')!r}")
    print(f"ok {method} {target} -> {raw_path}")


def main() -> None:
    if not OPENRESTY:
        raise SystemExit("SKIP openresty binary not installed")
    if port_open(8080):
        raise SystemExit("SKIP port 8080 is already in use")

    mock = ThreadingHTTPServer(("127.0.0.1", 0), MockHandler)
    mock.hits = []  # type: ignore[attr-defined]
    import threading

    thread = threading.Thread(target=mock.serve_forever, daemon=True)
    thread.start()
    mock_port = mock.server_address[1]
    dead_port = free_port()
    print(f"mock 127.0.0.1:{mock_port} dead 127.0.0.1:{dead_port}")

    key = {"X-Api-Key": "mini-key"}
    gw = Gateway(f"127.0.0.1:{mock_port}")
    legacy = None
    pinned = None
    retry = None
    try:
        gw.start()
        status, payload = 0, b""
        last_err: object = None
        for _ in range(50):
            try:
                status, payload = call("GET", "/health")
                if status == 200:
                    break
            except OSError as exc:
                last_err = exc
            time.sleep(0.05)
        else:
            raise SystemExit(f"/health not ready {status} {payload!r} {last_err}")
        if json.loads(payload).get("status") != "healthy":
            raise SystemExit(f"/health {status} {payload!r}")
        print("ok /health")
        status, payload = call("GET", "/ready")
        ready = json.loads(payload)
        if status != 200 or ready.get("status") != "ready" or ready.get("storage") != "memory":
            raise SystemExit(f"/ready {status} {payload!r}")
        print("ok /ready")

        before = len(mock.hits)
        status, payload = call("GET", "/v1/orders")
        if status != 401 or len(mock.hits) != before:
            raise SystemExit(f"unauthenticated request was proxied: {status} hits {len(mock.hits)}")
        print("ok auth 401 does not proxy")

        expect_upstream("GET", "/", "/", headers=key)
        expect_upstream("GET", "/?a=1&a=1", "/?a=1&a=1", headers=key)
        expect_upstream("GET", "/v1/orders", "/v1/orders", headers=key)
        expect_upstream("GET", "/v1/orders/42", "/v1/orders/42", headers=key)
        expect_upstream(
            "GET",
            "/a%2Fb%20c?x=1&x=2&q=a%20b",
            "/a%2Fb%20c?x=1&x=2&q=a%20b",
            headers=key,
        )
        expect_upstream("GET", "/pct%2520?q=a+b&q=a+b", "/pct%2520?q=a+b&q=a+b", headers=key)
        expect_upstream("GET", "/w/%E4%B8%AD?x=1&x=2", "/w/%E4%B8%AD?x=1&x=2", headers=key)
        body = b'{"n":1,"raw":"a+b %20"}\xff'
        expect_upstream(
            "POST",
            "/v1/items?a=1&a=2",
            "/v1/items?a=1&a=2",
            body=body,
            headers={**key, "Content-Type": "application/json"},
        )
        expect_upstream(
            "PUT",
            "/v1/items/7",
            "/v1/items/7",
            body=b"put-body",
            headers={**key, "Content-Type": "text/plain"},
        )

        admin_body = json.dumps(
            {"action": "upsert_apikey", "api_key": "rate-key", "limit": 2, "window": 60}
        ).encode()
        status, payload = call(
            "POST",
            "/admin/gw",
            body=admin_body,
            headers={
                "Authorization": "Bearer mini-token",
                "Content-Type": "application/json",
            },
        )
        if status != 200:
            raise SystemExit(f"admin upsert failed {status} {payload!r}")
        rate_headers = {"X-Api-Key": "rate-key"}
        for i in (1, 2):
            status, payload = call("GET", f"/limited/{i}", headers=rate_headers)
            if status != 200:
                raise SystemExit(f"rate request {i} -> {status} {payload!r}")
        before = len(mock.hits)
        status, payload = call("GET", "/limited/3", headers=rate_headers)
        if status != 429 or len(mock.hits) != before:
            raise SystemExit(f"rate limit did not stop proxy: {status} hits delta")
        print("ok rate limit 429")
        gw.stop()
        gw = None

        legacy = Gateway(f"127.0.0.1:{mock_port}", upstream_path="legacy/fixed")
        legacy.start()
        expect_upstream(
            "POST",
            "/v1/orders?a=1&a=2&q=a%20b",
            "/legacy/fixed",
            body=b"kept",
            headers={**key, "Content-Type": "text/plain"},
        )
        legacy.stop()
        legacy = None

        pinned = Gateway(f"127.0.0.1:{mock_port}", upstream_path="/pinned?fixed=1")
        pinned.start()
        expect_upstream("GET", "/v1/orders?a=1&a=2", "/pinned?fixed=1", headers=key)
        pinned.stop()
        pinned = None

        # dead peer first, live peer second. Round-robin sends one request to each.
        retry = Gateway(f"127.0.0.1:{dead_port}:1,127.0.0.1:{mock_port}:1", upstream_path=None)
        retry.start()
        expect_upstream("GET", "/retry/one?a=1&a=2", "/retry/one?a=1&a=2", headers=key)
        expect_upstream("GET", "/retry/two%2Fok", "/retry/two%2Fok", headers=key)
        error_log = Path(retry.prefix.name) / "logs" / "error.log"
        log_text = error_log.read_text() if error_log.is_file() else ""
        if str(dead_port) not in log_text or "connect() failed" not in log_text:
            raise SystemExit(
                "retry did not attempt the dead peer; both requests may have hit the live peer\n"
                + log_text[-2000:]
            )
        print("ok retry across dead peer")
        retry.stop()
        retry = None
        print("all upstream uri tests passed")
    finally:
        mock.shutdown()
        for item in (gw, legacy, pinned, retry):
            if item is not None:
                item.stop()


if __name__ == "__main__":
    main()
