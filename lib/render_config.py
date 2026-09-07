#!/usr/bin/env python3
"""Render sing-box JSON from local WG profiles + local rule-set .srs (no secrets logged)."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from parse_conf import parse_conf  # noqa: E402


def build_config(macbook, home, geosite_srs, geoip_srs):
    mb_peer = macbook["peer"]
    hm_peer = home["peer"]

    mb_ep = {
        "type": "wireguard",
        "tag": "macbook",
        "system": False,
        "address": macbook["address"],
        "private_key": macbook["private_key"],
        "peers": [{
            "address": mb_peer["address"],
            "port": mb_peer["port"],
            "public_key": mb_peer["public_key"],
            "allowed_ips": ["0.0.0.0/0"],
            "persistent_keepalive_interval": mb_peer.get("persistent_keepalive_interval", 25),
        }],
    }
    if "mtu" in macbook:
        mb_ep["mtu"] = macbook["mtu"]
    if "pre_shared_key" in mb_peer:
        mb_ep["peers"][0]["pre_shared_key"] = mb_peer["pre_shared_key"]

    hm_ep = {
        "type": "wireguard",
        "tag": "home",
        "system": False,
        "address": home["address"],
        "private_key": home["private_key"],
        "peers": [{
            "address": hm_peer["address"],
            "port": hm_peer["port"],
            "public_key": hm_peer["public_key"],
            "allowed_ips": ["10.13.13.0/24", "10.57.0.0/24"],
            "persistent_keepalive_interval": hm_peer.get("persistent_keepalive_interval", 25),
        }],
    }
    if "mtu" in home:
        hm_ep["mtu"] = home["mtu"]
    if "pre_shared_key" in hm_peer:
        hm_ep["peers"][0]["pre_shared_key"] = hm_peer["pre_shared_key"]

    endpoint_cidrs = [f"{mb_peer['address']}/32", f"{hm_peer['address']}/32"]

    return {
        "log": {"level": "info", "timestamp": True},
        # RU DNS: explicit UDP without detour (system/default dial).
        # - type:local loops: up() sets Wi-Fi DNS to TUN 172.19.0.1
        # - detour:direct fatals on sing-box 1.14: "empty direct outbound makes no sense"
        "dns": {
            "servers": [
                {"type": "udp", "tag": "dns-home", "server": "10.57.0.100", "server_port": 53, "detour": "home"},
                {"type": "udp", "tag": "dns-remote", "server": "1.1.1.1", "server_port": 53, "detour": "macbook"},
                {"type": "udp", "tag": "dns-direct", "server": "8.8.8.8", "server_port": 53},
            ],
            "rules": [
                {"domain_suffix": ["digials.com", "digials.ru"], "server": "dns-home"},
                {"rule_set": "geosite-ru", "server": "dns-direct"},
            ],
            "final": "dns-remote",
            "strategy": "ipv4_only",
        },
        "inbounds": [{
            "type": "tun",
            "tag": "tun-in",
            "address": ["172.19.0.1/30"],
            "mtu": 1280,
            "auto_route": True,
            "strict_route": False,
            "stack": "system",
        }],
        "endpoints": [mb_ep, hm_ep],
        "outbounds": [{"type": "direct", "tag": "direct"}],
        "route": {
            "auto_detect_interface": True,
            "default_domain_resolver": {"server": "dns-direct", "strategy": "ipv4_only"},
            "rules": [
                {"action": "sniff"},
                {"protocol": "dns", "action": "hijack-dns"},
                {"ip_cidr": endpoint_cidrs, "outbound": "direct"},
                {"ip_cidr": ["192.168.3.0/24"], "outbound": "direct"},
                {"ip_cidr": ["10.13.13.0/24", "10.57.0.0/24"], "outbound": "home"},
                {"rule_set": "geosite-ru", "outbound": "direct"},
                {"rule_set": "geoip-ru", "outbound": "direct"},
            ],
            "final": "macbook",
            "rule_set": [
                {"type": "local", "tag": "geosite-ru", "format": "binary", "path": str(geosite_srs)},
                {"type": "local", "tag": "geoip-ru", "format": "binary", "path": str(geoip_srs)},
            ],
        },
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--macbook", type=Path, required=True)
    ap.add_argument("--home", type=Path, required=True)
    ap.add_argument("--geosite", type=Path, required=True)
    ap.add_argument("--geoip", type=Path, required=True)
    ap.add_argument("-o", "--output", type=Path, required=True)
    args = ap.parse_args()
    for p in (args.macbook, args.home, args.geosite, args.geoip):
        if not p.exists():
            print(f"missing: {p}", file=sys.stderr)
            return 1
    try:
        cfg = build_config(parse_conf(args.macbook), parse_conf(args.home), args.geosite, args.geoip)
    except Exception as e:
        print(str(e), file=sys.stderr)
        return 1
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(cfg, indent=2) + "\n", encoding="utf-8")
    args.output.chmod(0o600)
    print(f"wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
