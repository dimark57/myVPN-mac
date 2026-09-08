#!/usr/bin/env python3
"""Safe probes for myvpn doctor — no private keys / PSK in output."""

from __future__ import annotations

import argparse
import json
import os
import re
import socket
import sys
import time
from pathlib import Path


def load_endpoints(config_path: Path) -> dict:
    raw = json.loads(config_path.read_text(encoding="utf-8"))
    out = {"endpoints": [], "tun_addr": None, "final": None, "system_wg": []}
    for ib in raw.get("inbounds") or []:
        if ib.get("type") == "tun":
            addrs = ib.get("address") or []
            out["tun_addr"] = addrs[0] if addrs else None
    route = raw.get("route") or {}
    out["final"] = route.get("final")
    for ep in raw.get("endpoints") or []:
        if ep.get("type") != "wireguard":
            continue
        peers = ep.get("peers") or []
        peer = peers[0] if peers else {}
        item = {
            "tag": ep.get("tag"),
            "system": bool(ep.get("system")),
            "local": (ep.get("address") or [None])[0],
            "peer_host": peer.get("address"),
            "peer_port": peer.get("port"),
            "keepalive": peer.get("persistent_keepalive_interval"),
            "allowed_ips": peer.get("allowed_ips") or [],
        }
        out["endpoints"].append(item)
        out["system_wg"].append(bool(ep.get("system")))
    return out


def udp_send(host: str, port: int, timeout: float = 0.2) -> dict:
    """Best-effort UDP send to WG port. Do not wait for reply (WG rarely answers stubs)."""
    t0 = time.monotonic()
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.settimeout(timeout)
        sock.sendto(b"\x01" + b"\x00" * 147, (host, int(port)))
        sock.close()
        return {
            "ok": True,
            "replied": False,
            "ms": int((time.monotonic() - t0) * 1000),
            "error": "",
        }
    except OSError as e:
        return {
            "ok": False,
            "replied": False,
            "ms": int((time.monotonic() - t0) * 1000),
            "error": str(e),
        }


def scan_log(path: Path, limit: int = 400) -> dict:
    if not path.is_file():
        return {"exists": False, "signals": [], "tail": []}
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError as e:
        return {"exists": True, "signals": [f"read_error:{e}"], "tail": []}
    tail = lines[-min(limit, len(lines)) :]
    patterns = [
        (r"\bFATAL\b", "fatal"),
        (r"\bERROR\b", "error"),
        (r"failed to", "failed"),
        (r"handshake", "handshake"),
        (r"connection refused", "refused"),
        (r"i/o timeout|deadline exceeded|timed out", "timeout"),
        (r"no route to host|network is unreachable", "unreach"),
        (r"broken pipe|connection reset", "reset"),
        (r"endpoint/wireguard\[macbook\]", "via_macbook"),
        (r"endpoint/wireguard\[home\]", "via_home"),
    ]
    counts: dict[str, int] = {}
    samples: dict[str, str] = {}
    for line in tail:
        for rx, name in patterns:
            if re.search(rx, line, re.I):
                counts[name] = counts.get(name, 0) + 1
                samples.setdefault(name, line[-180:])
    signals = [f"{k}={v}" for k, v in sorted(counts.items())]
    return {
        "exists": True,
        "signals": signals,
        "samples": samples,
        "tail": tail[-12:],
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", type=Path, required=True)
    ap.add_argument("--log", type=Path, default=None)
    ap.add_argument("--udp-probe", action="store_true")
    args = ap.parse_args()

    result: dict = {"config": None, "udp": {}, "log": None}
    if args.config.is_file():
        result["config"] = load_endpoints(args.config)
    else:
        result["config"] = {"error": f"missing {args.config}"}

    if args.udp_probe and isinstance(result["config"], dict):
        for ep in result["config"].get("endpoints") or []:
            host, port = ep.get("peer_host"), ep.get("peer_port")
            if host and port:
                result["udp"][ep["tag"]] = udp_send(host, port)

    if args.log:
        result["log"] = scan_log(args.log)

    json.dump(result, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
