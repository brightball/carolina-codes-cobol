#!/usr/bin/env python3
"""Production server: /health returns before a stalled or dead CMS register."""

from __future__ import annotations

import os
import re
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path
from queue import Queue

ROOT = Path(__file__).resolve().parent.parent
BIN = ROOT / "bin" / "carolina-cobol"
HEALTH = b'{"status":"ok"}'


def fail(msg: str) -> None:
    raise SystemExit(f"FAIL: {msg}")


def free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def base_env(port: int) -> dict[str, str]:
    env = os.environ.copy()
    env["PORT"] = str(port)
    lib = Path.home() / ".local" / "opt" / "gnucobol-3.2" / "lib"
    if lib.is_dir():
        prev = env.get("LD_LIBRARY_PATH", "")
        env["LD_LIBRARY_PATH"] = str(lib) + (f":{prev}" if prev else "")
    return env


def stop(proc: subprocess.Popen | None) -> None:
    if proc is None or proc.poll() is not None:
        return
    proc.terminate()
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=2)


def exchange(port: int, timeout: float = 1.0):
    req = b"GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
    with socket.create_connection(("127.0.0.1", port), timeout=timeout) as sock:
        sock.settimeout(timeout)
        sock.sendall(req)
        data = b""
        while b"\r\n\r\n" not in data:
            chunk = sock.recv(4096)
            if not chunk:
                break
            data += chunk
        head, _, body = data.partition(b"\r\n\r\n")
        match = re.search(br"(?im)^content-length:\s*(\d+)\s*$", head)
        if not match:
            fail(f"health missing Content-Length {head!r}")
        need = int(match.group(1))
        while len(body) < need:
            chunk = sock.recv(4096)
            if not chunk:
                break
            body += chunk
        extra = body[need:]
        body = body[:need]
        status = int(head.split(b" ", 2)[1])
        return status, body, extra


def health_within(port: int, started: float, budget: float = 2.0):
    deadline = started + budget
    last = "no attempt"
    while time.monotonic() < deadline:
        try:
            status, body, extra = exchange(port, timeout=max(0.05, deadline - time.monotonic()))
            return status, body, extra, time.monotonic() - started
        except OSError as exc:
            last = str(exc)
            time.sleep(0.02)
    fail(f"/health not ready within {budget}s ({last})")
    raise AssertionError("unreachable")


def start_server(port: int, env: dict[str, str]) -> tuple[subprocess.Popen, float]:
    if not BIN.is_file():
        fail(f"missing {BIN}")
    started = time.monotonic()
    proc = subprocess.Popen(
        [str(BIN)],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return proc, started


def assert_health(port: int, started: float, label: str) -> None:
    status, body, extra, elapsed = health_within(port, started)
    if status != 200 or body != HEALTH or extra:
        fail(f"{label} status={status} body={body!r} extra={extra!r}")
    if elapsed >= 2.0:
        fail(f"{label} took {elapsed:.3f}s")
    print(f"ok: {label} HTTP 200 {body.decode()} in {elapsed:.3f}s")


def serve_stall(ready: Queue, done: Queue) -> None:
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 0))
    srv.listen(1)
    ready.put(srv.getsockname()[1])
    srv.settimeout(5)
    try:
        conn, _ = srv.accept()
    except OSError:
        srv.close()
        done.put(b"")
        return
    try:
        time.sleep(8)
    finally:
        conn.close()
        srv.close()
        done.put(b"stalled")


def serve_register(ready: Queue, captured: Queue) -> None:
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 0))
    srv.listen(1)
    ready.put(srv.getsockname()[1])
    srv.settimeout(5)
    try:
        conn, _ = srv.accept()
    except OSError as exc:
        captured.put(b"")
        srv.close()
        fail(f"register stub accept failed: {exc}")
        return
    conn.settimeout(3)
    data = b""
    try:
        while b"\r\n\r\n" not in data:
            chunk = conn.recv(4096)
            if not chunk:
                break
            data += chunk
        head, _, rest = data.partition(b"\r\n\r\n")
        match = re.search(br"(?i)content-length:\s*(\d+)", head)
        need = int(match.group(1)) if match else 0
        while len(rest) < need:
            chunk = conn.recv(4096)
            if not chunk:
                break
            rest += chunk
        conn.sendall(b"HTTP/1.1 204 No Content\r\nConnection: close\r\nContent-Length: 0\r\n\r\n")
    finally:
        conn.close()
        srv.close()
        captured.put(head + b"\r\n\r\n" + rest)


def run_stall() -> None:
    ready: Queue = Queue()
    done: Queue = Queue()
    thread = threading.Thread(target=serve_stall, args=(ready, done), daemon=True)
    thread.start()
    cms = ready.get(timeout=2)
    port = free_port()
    env = base_env(port)
    env["CAROLINA_URL"] = f"http://127.0.0.1:{cms}"
    env["POLYGLOT_REGISTER_TOKEN"] = "dev"
    proc, started = start_server(port, env)
    try:
        assert_health(port, started, "stall")
    finally:
        stop(proc)


def run_unroutable() -> None:
    port = free_port()
    env = base_env(port)
    env["CAROLINA_URL"] = "http://192.0.2.1:9"
    env["POLYGLOT_REGISTER_TOKEN"] = "dev"
    proc, started = start_server(port, env)
    try:
        assert_health(port, started, "unroutable")
    finally:
        stop(proc)


def run_register() -> None:
    ready: Queue = Queue()
    captured: Queue = Queue()
    thread = threading.Thread(target=serve_register, args=(ready, captured), daemon=True)
    thread.start()
    cms = ready.get(timeout=2)
    port = free_port()
    env = base_env(port)
    env["CAROLINA_URL"] = f"http://127.0.0.1:{cms}"
    env["POLYGLOT_REGISTER_TOKEN"] = "dev"
    env["PUBLIC_BASE_URL"] = f"http://127.0.0.1:{port}"
    proc, started = start_server(port, env)
    try:
        assert_health(port, started, "register")
        payload = captured.get(timeout=4)
    finally:
        stop(proc)
    if b"POST /internal/api-endpoints/register" not in payload or b"COBOL" not in payload:
        fail(f"register POST missing COBOL payload {payload[:400]!r}")
    print("ok: register POST advertises COBOL")


def run_health_without_postgres() -> None:
    port = free_port()
    env = base_env(port)
    env.pop("CAROLINA_URL", None)
    env.pop("POLYGLOT_REGISTER_TOKEN", None)
    env["DATABASE_URL"] = "postgres://postgres:postgres@192.0.2.1:5432/postgres?sslmode=disable"
    proc, started = start_server(port, env)
    try:
        assert_health(port, started, "postgres-unroutable")
    finally:
        stop(proc)


def main() -> None:
    case = sys.argv[1] if len(sys.argv) > 1 else "all"
    if case == "stall":
        run_stall()
    elif case == "unroutable":
        run_unroutable()
    elif case == "register":
        run_register()
    elif case == "postgres":
        run_health_without_postgres()
    elif case == "all":
        run_stall()
        run_stall()
        run_unroutable()
        run_unroutable()
        run_register()
        run_health_without_postgres()
        print("health ready tests passed")
    else:
        fail(f"unknown case {case}")


if __name__ == "__main__":
    main()
