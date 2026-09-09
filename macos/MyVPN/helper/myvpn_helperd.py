#!/usr/bin/env python3
"""Root daemon: up/down sing-box without per-action admin password."""
from __future__ import annotations

import ctypes
import os
import pwd
import signal
import socket
import subprocess
import sys
import threading
import time

SOCK_PATH = os.environ.get("MYVPN_HELPER_SOCK", "/var/run/myvpn-helper.sock")
OWNER = os.environ.get("MYVPN_OWNER", "")
HOME = os.environ.get("HOME", "")
MYVPN_ROOT = os.environ.get("MYVPN_ROOT", "")
LOG_PATH = os.environ.get("MYVPN_HELPER_LOG", "/var/log/myvpn-helper.log")
CMD_TIMEOUT = float(os.environ.get("MYVPN_HELPER_TIMEOUT", "45"))
# Bump when allowed commands / behavior change — app prompts reinstall if running proto < required.
HELPER_PROTO = 2

_lock = threading.Lock()


def log(msg: str) -> None:
    line = f"{time.strftime('%H:%M:%S')} {msg.rstrip()}\n"
    try:
        with open(LOG_PATH, "a", encoding="utf-8") as fh:
            fh.write(line)
    except OSError:
        sys.stderr.write(line)


def owner_uid() -> int:
    if not OWNER:
        raise RuntimeError("MYVPN_OWNER not set")
    return pwd.getpwnam(OWNER).pw_uid


def peer_uid(conn: socket.socket) -> int:
    uid = ctypes.c_uint()
    gid = ctypes.c_uint()
    libc = ctypes.CDLL("/usr/lib/libc.dylib", use_errno=True)
    if libc.getpeereid(conn.fileno(), ctypes.byref(uid), ctypes.byref(gid)) != 0:
        raise OSError(ctypes.get_errno(), "getpeereid failed")
    return int(uid.value)


def run_myvpn(action: str) -> tuple[int, str]:
    if not MYVPN_ROOT or not HOME:
        return 1, "MYVPN_ROOT/HOME not set"
    bin_path = os.path.join(MYVPN_ROOT, "bin", "myvpn")
    if not os.path.isfile(bin_path):
        return 1, f"missing {bin_path}"
    env = os.environ.copy()
    env["HOME"] = HOME
    env["USER"] = OWNER
    env["LOGNAME"] = OWNER
    env["MYVPN_QUIET"] = "1"
    # Menu/AppDelegate remounts NAS after up — nested auto-nas here made up take 30–45s.
    env["MYVPN_SKIP_AUTO_NAS"] = "1"
    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    t0 = time.monotonic()
    log(f"begin {action}")
    try:
        proc = subprocess.run(
            ["/bin/zsh", bin_path, action],
            env=env,
            capture_output=True,
            text=True,
            timeout=CMD_TIMEOUT,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        log(f"timeout {action} after {CMD_TIMEOUT}s")
        # Best-effort kill leftover zsh/sing-box start child
        return 1, f"timeout after {int(CMD_TIMEOUT)}s"
    out = (proc.stdout or "").strip()
    err = (proc.stderr or "").strip()
    detail = out or err or f"exit {proc.returncode}"
    log(f"end {action} rc={proc.returncode} {time.monotonic()-t0:.2f}s {detail[:120]}")
    return proc.returncode, detail


def handle(cmd: str) -> str:
    cmd = cmd.strip().lower()
    if cmd == "ping":
        return "ok ready"
    if cmd in ("proto", "version"):
        return f"ok proto={HELPER_PROTO}"
    if cmd in ("up", "down", "pin-endpoints"):
        with _lock:
            code, detail = run_myvpn(cmd)
        if code == 0:
            return f"ok {detail}"
        return f"err {detail}"
    return "err unknown command"


def serve() -> None:
    if os.geteuid() != 0:
        sys.stderr.write("myvpn_helperd must run as root\n")
        sys.exit(1)
    try:
        uid = owner_uid()
        gid = pwd.getpwnam(OWNER).pw_gid
    except KeyError as exc:
        log(f"bad owner: {exc}")
        sys.exit(1)

    if os.path.exists(SOCK_PATH):
        os.unlink(SOCK_PATH)

    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(SOCK_PATH)
    os.chown(SOCK_PATH, uid, gid)
    os.chmod(SOCK_PATH, 0o660)
    server.listen(5)
    log(f"listening {SOCK_PATH} owner={OWNER} root={MYVPN_ROOT} timeout={CMD_TIMEOUT}")

    def _stop(signum, frame):  # noqa: ANN001, ARG001
        try:
            server.close()
            if os.path.exists(SOCK_PATH):
                os.unlink(SOCK_PATH)
        finally:
            sys.exit(0)

    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)

    while True:
        conn, _ = server.accept()
        with conn:
            try:
                got_uid = peer_uid(conn)
                if got_uid != uid:
                    log(f"forbidden peer_uid={got_uid} want_uid={uid}")
                    conn.sendall(b"err forbidden\n")
                    continue
                data = b""
                while not data.endswith(b"\n") and len(data) < 256:
                    chunk = conn.recv(64)
                    if not chunk:
                        break
                    data += chunk
                resp = handle(data.decode("utf-8", errors="replace"))
                conn.sendall((resp + "\n").encode("utf-8"))
            except Exception as exc:  # noqa: BLE001
                log(f"request error: {exc}")
                try:
                    conn.sendall(f"err {exc}\n".encode("utf-8"))
                except OSError:
                    pass


if __name__ == "__main__":
    serve()
