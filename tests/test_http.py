#!/usr/bin/env python3
"""HTTP coverage of the shipped server shell linked to the fake catalog.

Requests go through listen, parse, and CALL of HANDLE-GET. This file does
not route.
"""

from __future__ import annotations

import json
import os
import re
import socket
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BIN = ROOT / "bin" / "carolina-http-test"


def fail(msg: str) -> None:
    raise SystemExit(f"FAIL: {msg}")


def free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def child_env(port: int) -> dict[str, str]:
    env = os.environ.copy()
    env["PORT"] = str(port)
    env.pop("CAROLINA_URL", None)
    env.pop("POLYGLOT_REGISTER_TOKEN", None)
    lib = Path.home() / ".local" / "opt" / "gnucobol-3.2" / "lib"
    if lib.is_dir():
        prev = env.get("LD_LIBRARY_PATH", "")
        env["LD_LIBRARY_PATH"] = str(lib) + (f":{prev}" if prev else "")
    return env


def exchange(port: int, request: bytes, timeout: float = 5.0):
    with socket.create_connection(("127.0.0.1", port), timeout=timeout) as sock:
        sock.settimeout(timeout)
        sock.sendall(request)
        data = b""
        while b"\r\n\r\n" not in data:
            chunk = sock.recv(65536)
            if not chunk:
                break
            data += chunk
        if b"\r\n\r\n" not in data:
            fail(f"short response {data[:180]!r}")
        head, _, body = data.partition(b"\r\n\r\n")
        match = re.search(br"(?im)^content-length:\s*(\d+)\s*$", head)
        if not match:
            fail(f"missing Content-Length in {head!r}")
        need = int(match.group(1))
        while len(body) < need:
            chunk = sock.recv(65536)
            if not chunk:
                break
            body += chunk
        extra = b""
        if len(body) > need:
            extra = body[need:]
            body = body[:need]
        sock.settimeout(0.2)
        try:
            while True:
                chunk = sock.recv(65536)
                if not chunk:
                    break
                extra += chunk
        except socket.timeout:
            pass
        status = int(head.split(b" ", 2)[1])
        return status, body, extra


def request_line(port: int, target: str, extra_headers: bytes = b"") -> tuple[int, bytes, bytes]:
    req = b"GET " + target.encode() + b" HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n"
    req += extra_headers
    if extra_headers and not extra_headers.endswith(b"\r\n"):
        req += b"\r\n"
    req += b"\r\n"
    return exchange(port, req)


def start_server(port: int) -> subprocess.Popen:
    if not BIN.is_file():
        fail(f"missing {BIN}; build the HTTP shell first")
    proc = subprocess.Popen(
        [str(BIN)],
        env=child_env(port),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            out, err = proc.communicate()
            fail(f"http shell exited {proc.returncode}: {out!r} {err!r}")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return proc
        except OSError:
            time.sleep(0.02)
    stop(proc)
    fail("http shell did not accept within 5s")
    raise AssertionError("unreachable")


def stop(proc: subprocess.Popen) -> None:
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)


def expect(status: int, body: bytes, extra: bytes, code: int, label: str) -> None:
    if status != code:
        fail(f"{label} status {status} body={body[:200]!r}")
    if extra:
        fail(f"{label} sent {len(extra)} bytes past Content-Length")
    if len(body) != len(body.rstrip(b" ")):
        fail(f"{label} body has trailing spaces")


def main() -> None:
    port = free_port()
    proc = start_server(port)
    try:
        status, body, extra = request_line(port, "/health")
        expect(status, body, extra, 200, "/health")
        if body != b'{"status":"ok"}':
            fail(f"/health body {body!r}")
        print("ok: /health 200 exact JSON")

        status, body, extra = request_line(port, "/")
        expect(status, body, extra, 200, "/")
        text = body.decode()
        if "COBOL" not in text or "POSIX sockets" not in text:
            fail(f"/ identity {text[:240]}")
        print("ok: / reports COBOL and POSIX sockets")

        status, body, extra = request_line(port, "/no-such")
        expect(status, body, extra, 404, "unknown path")
        if b"not_found" not in body:
            fail(f"unknown path body {body!r}")
        print("ok: unknown path 404 not_found")

        status, body, extra = request_line(port, "/v1/years")
        expect(status, body, extra, 200, "/v1/years")
        if b'"data"' not in body:
            fail("/v1/years missing data")
        print("ok: /v1/years")

        status, body, extra = request_line(port, "/v1/speakers")
        expect(status, body, extra, 200, "speakers")
        json.loads(body)
        slugs = body.count(b'"slug":"diana-pham"')
        if slugs <= 64:
            fail(f"unscoped speakers kept {slugs} rows")
        if b"languages" in body:
            fail("unscoped speakers unexpectedly included languages")
        print(f"ok: unscoped speakers {slugs} rows valid JSON")

        status, body, extra = request_line(
            port,
            "/v1/speakers",
            b"X-Year: 2026\r\nyear: 2026\r\n",
        )
        expect(status, body, extra, 200, "speakers header year")
        if body.count(b'"slug":"diana-pham"') <= 64 or b"languages" in body:
            fail("year was honored from a header, not the request line")
        print("ok: year header is not a query")

        status, body, extra = exchange(
            port,
            b"GET /v1/speakers HTTP/1.1\r\nHost: 127.0.0.1\r\n"
            b"Content-Length: 10\r\nConnection: close\r\n\r\nyear=2026\n",
        )
        expect(status, body, extra, 200, "speakers body year")
        if body.count(b'"slug":"diana-pham"') <= 64 or b"languages" in body:
            fail("year was honored from the body, not the request line")
        print("ok: year body is not a query")

        status, body, extra = request_line(port, "/v1/speakers?year=2026")
        expect(status, body, extra, 200, "speakers?year=")
        text = body.decode()
        if "languages" not in text or "topics" not in text:
            fail(f"year speakers missing tags {text[:300]}")
        if "v1_year_speakers" in text:
            fail("year speakers exposed v1_year_speakers")
        print("ok: year= on the request line scopes speakers")

        status, body, extra = request_line(port, "/v1/speakers/no-such-slug")
        expect(status, body, extra, 404, "unknown speaker")
        if b"not_found" not in body:
            fail(f"unknown speaker body {body!r}")
        print("ok: unknown speaker 404 not_found")

        status, body, extra = request_line(port, "/v1/speakers/2025/diana-pham")
        expect(status, body, extra, 200, "speaker year detail")
        text = body.decode()
        json.loads(text)
        if '"talks"' not in text or '"youtube_id":"dPhamYtFix01"' not in text:
            fail(f"speaker detail missing talks {text[:400]}")
        if '"website_url":""' in text or '"website_url":null' not in text:
            fail(f"website_url contract {text[:400]}")
        print("ok: year speaker detail talks, youtube id, website null")

        status, body, extra = request_line(port, "/v1/sponsors")
        expect(status, body, extra, 200, "sponsors")
        json.loads(body)
        print("ok: /v1/sponsors")

        status, body, extra = request_line(port, "/v1/sponsors?year=2026")
        expect(status, body, extra, 200, "sponsors?year=")
        text = body.decode()
        if "platinum" not in text or "tier" not in text:
            fail(f"year sponsors missing platinum {text[:300]}")
        print("ok: year sponsors include platinum")

        status, body, extra = request_line(port, "/v1/sponsors/flywheel")
        expect(status, body, extra, 200, "sponsor slug")
        text = body.decode()
        json.loads(text)
        if "flywheel" not in text or "Flywheel" not in text:
            fail(f"sponsor slug identity {text[:300]}")
        print("ok: sponsor slug 200 flywheel")

        status, body, extra = request_line(port, "/v1/sponsors/2026/flywheel")
        expect(status, body, extra, 200, "sponsor year slug")
        text = body.decode()
        json.loads(text)
        if "flywheel" not in text:
            fail(f"year sponsor identity {text[:300]}")
        print("ok: year sponsor detail 200 flywheel")

        print("http shell tests passed")
    finally:
        stop(proc)


if __name__ == "__main__":
    main()
