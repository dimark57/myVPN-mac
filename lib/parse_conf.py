#!/usr/bin/env python3
"""Parse WireGuard .conf (no secrets printed). AllowedIPs used by render for home split routes."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


SECTION_RE = re.compile(r"^\[(.+)\]\s*$")
KV_RE = re.compile(r"^([A-Za-z0-9]+)\s*=\s*(.*)$")


def parse_conf(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8")
    interface: dict[str, str] = {}
    peers: list[dict[str, str]] = []
    current: str | None = None
    peer: dict[str, str] | None = None

    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or line.startswith(";"):
            continue
        m = SECTION_RE.match(line)
        if m:
            name = m.group(1).lower()
            if name == "interface":
                current = "interface"
                peer = None
            elif name == "peer":
                current = "peer"
                peer = {}
                peers.append(peer)
            else:
                current = None
                peer = None
            continue
        km = KV_RE.match(line)
        if not km:
            continue
        key, value = km.group(1), km.group(2).strip()
        if current == "interface":
            interface[key] = value
        elif current == "peer" and peer is not None:
            peer[key] = value

    if not peers:
        raise ValueError(f"{path}: no [Peer] section")
    if "PrivateKey" not in interface:
        raise ValueError(f"{path}: missing PrivateKey")
    if "Address" not in interface:
        raise ValueError(f"{path}: missing Address")

    peer0 = peers[0]
    for req in ("PublicKey", "Endpoint"):
        if req not in peer0:
            raise ValueError(f"{path}: peer missing {req}")

    host, _, port_s = peer0["Endpoint"].rpartition(":")
    if not host or not port_s:
        raise ValueError(f"{path}: bad Endpoint")
    port = int(port_s)

    addresses = [a.strip() for a in interface["Address"].split(",") if a.strip()]
    norm_addrs: list[str] = []
    for a in addresses:
        if ":" in a:
            continue
        if "/" in a:
            ip, _, pfx = a.partition("/")
            norm_addrs.append(f"{ip}/{pfx}")
        else:
            norm_addrs.append(f"{a}/32")

    mtu = int(interface["MTU"]) if "MTU" in interface else None
    keepalive = int(peer0["PersistentKeepalive"]) if "PersistentKeepalive" in peer0 else 25

    allowed = []
    if "AllowedIPs" in peer0:
        for part in peer0["AllowedIPs"].split(","):
            part = part.strip()
            if part and ":" not in part.split("/")[0]:
                allowed.append(part)
    if not allowed:
        allowed = ["0.0.0.0/0"]

    out: dict[str, Any] = {
        "private_key": interface["PrivateKey"],
        "address": norm_addrs,
        "peer": {
            "address": host,
            "port": port,
            "public_key": peer0["PublicKey"],
            "allowed_ips": allowed,
            "persistent_keepalive_interval": keepalive,
        },
    }
    if "PresharedKey" in peer0 and peer0["PresharedKey"]:
        out["peer"]["pre_shared_key"] = peer0["PresharedKey"]
    if mtu is not None:
        out["mtu"] = mtu
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("conf", type=Path)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    try:
        data = parse_conf(args.conf)
    except Exception as e:
        print(str(e), file=sys.stderr)
        return 1
    if args.json:
        print(json.dumps(data))
    else:
        print(f"ok {args.conf.name} peer={data['peer']['address']}:{data['peer']['port']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
