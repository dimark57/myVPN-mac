#!/usr/bin/env python3
"""Talk to local.myvpn.mac.helper over a Unix socket."""
from __future__ import annotations

import argparse
import os
import socket
import sys

SOCK_PATH = os.environ.get("MYVPN_HELPER_SOCK", "/var/run/myvpn-helper.sock")


def send_command(cmd: str, timeout: float = 180.0) -> int:
    if not os.path.exists(SOCK_PATH):
        print(f"helper socket missing: {SOCK_PATH}", file=sys.stderr)
        return 2
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    try:
        sock.connect(SOCK_PATH)
        sock.sendall((cmd.strip() + "\n").encode("utf-8"))
        data = b""
        while not data.endswith(b"\n"):
            chunk = sock.recv(4096)
            if not chunk:
                break
            data += chunk
    except OSError as exc:
        print(f"helper connect failed: {exc}", file=sys.stderr)
        return 2
    finally:
        sock.close()

    text = data.decode("utf-8", errors="replace").strip()
    if text.startswith("ok"):
        if len(text) > 2:
            print(text[2:].lstrip(" :"))
        return 0
    print(text or "helper error", file=sys.stderr)
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(description="myVPN privileged helper client")
    parser.add_argument("command", choices=("ping", "up", "down"))
    parser.add_argument("--timeout", type=float, default=180.0)
    args = parser.parse_args()
    return send_command(args.command, timeout=args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
