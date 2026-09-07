#!/usr/bin/env python3
"""Start/stop sing-box detached (survives osascript admin shell exit)."""
from __future__ import annotations

import argparse
import os
import signal
import subprocess
import sys
import time
from pathlib import Path


def _wait_gone(pid: int, timeout: float) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return True
        time.sleep(0.05)
    return False


def start(sing_box: str, config: str, workdir: str, pid_file: str, log_file: str) -> int:
    Path(workdir).mkdir(parents=True, exist_ok=True)
    pf = Path(pid_file)
    if pf.exists():
        try:
            old = int(pf.read_text().strip())
            os.kill(old, signal.SIGTERM)
            if not _wait_gone(old, 0.4):
                os.kill(old, signal.SIGKILL)
                _wait_gone(old, 0.3)
        except (ValueError, ProcessLookupError, PermissionError, OSError):
            pass
        pf.unlink(missing_ok=True)

    log = open(log_file, "a", buffering=1)
    proc = subprocess.Popen(
        [sing_box, "run", "-c", config, "-D", workdir],
        stdout=log,
        stderr=log,
        stdin=subprocess.DEVNULL,
        start_new_session=True,
        cwd=workdir,
    )
    pf.write_text(str(proc.pid) + "\n")
    try:
        os.chmod(pid_file, 0o644)
        os.chmod(log_file, 0o644)
    except OSError:
        pass

    # Poll briefly instead of fixed 1.5s sleep.
    deadline = time.monotonic() + 0.6
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            print(f"sing-box exited early code={proc.returncode}", file=sys.stderr)
            return 1
        try:
            os.kill(proc.pid, 0)
            time.sleep(0.05)
            if proc.poll() is None:
                print(proc.pid)
                return 0
        except OSError:
            print("sing-box not running after start", file=sys.stderr)
            return 1
        time.sleep(0.05)

    if proc.poll() is not None:
        print(f"sing-box exited early code={proc.returncode}", file=sys.stderr)
        return 1
    print(proc.pid)
    return 0


def stop(pid_file: str) -> int:
    pf = Path(pid_file)
    if not pf.exists():
        return 0
    try:
        pid = int(pf.read_text().strip())
    except ValueError:
        pf.unlink(missing_ok=True)
        return 0
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pf.unlink(missing_ok=True)
        return 0
    except PermissionError as e:
        print(str(e), file=sys.stderr)
        return 1
    if not _wait_gone(pid, 0.5):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        _wait_gone(pid, 0.3)
    pf.unlink(missing_ok=True)
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("start")
    s.add_argument("--sing-box", required=True)
    s.add_argument("--config", required=True)
    s.add_argument("--workdir", required=True)
    s.add_argument("--pid-file", required=True)
    s.add_argument("--log-file", required=True)
    sub.add_parser("stop").add_argument("--pid-file", required=True)
    args = ap.parse_args()
    if args.cmd == "start":
        return start(args.sing_box, args.config, args.workdir, args.pid_file, args.log_file)
    return stop(args.pid_file)


if __name__ == "__main__":
    raise SystemExit(main())
