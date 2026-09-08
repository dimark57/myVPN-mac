#!/usr/bin/env python3
"""Render sing-box JSON from local WG profiles + local rule-set .srs (no secrets logged).

Uses: parse_conf.py, settings.py (lan_cidrs, dns_*, home AllowedIPs from conf).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from parse_conf import parse_conf  # noqa: E402
from settings import guess_gw, load_settings  # noqa: E402


def _home_cidrs(hm_peer: dict) -> list[str]:
    """Split routes from home AllowedIPs — never use 0.0.0.0/0 for home outbound."""
    out: list[str] = []
    for cidr in hm_peer.get("allowed_ips") or []:
        c = cidr.strip()
        if not c or c == "0.0.0.0/0" or c.startswith("::"):
            continue
        out.append(c)
    return out


def _peer_lan_gw(addresses: list[str]) -> str:
    addr0 = (addresses or [""])[0]
    ip = addr0.split("/")[0]
    parts = ip.split(".")
    if len(parts) == 4:
        return f"{parts[0]}.{parts[1]}.{parts[2]}.1"
    return ""


def build_config(macbook, home, geosite_srs, geoip_srs, settings: dict | None = None):
    settings = settings or load_settings()
    mb_peer = macbook["peer"]
    hm_peer = home["peer"]
    home_cidrs = _home_cidrs(hm_peer)
    lan_cidrs = [c for c in (settings.get("lan_cidrs") or []) if c]

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

    hm_allowed = home_cidrs if home_cidrs else ["0.0.0.0/0"]
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
            "allowed_ips": hm_allowed,
            "persistent_keepalive_interval": hm_peer.get("persistent_keepalive_interval", 25),
        }],
    }
    if "mtu" in home:
        hm_ep["mtu"] = home["mtu"]
    if "pre_shared_key" in hm_peer:
        hm_ep["peers"][0]["pre_shared_key"] = hm_peer["pre_shared_key"]

    endpoint_cidrs = [f"{mb_peer['address']}/32", f"{hm_peer['address']}/32"]
    route_exclude = list(endpoint_cidrs) + lan_cidrs

    dns_servers = [
        {"type": "udp", "tag": "dns-remote", "server": "1.1.1.1", "server_port": 53, "detour": "macbook"},
        {"type": "udp", "tag": "dns-direct", "server": "8.8.8.8", "server_port": 53},
    ]
    dns_rules: list[dict] = []
    dns_home = (settings.get("dns_home_server") or "").strip()
    dns_suffixes = [s for s in (settings.get("dns_suffixes") or []) if s]
    if dns_home:
        dns_servers.insert(0, {
            "type": "udp",
            "tag": "dns-home",
            "server": dns_home,
            "server_port": 53,
            "detour": "home",
        })
        if dns_suffixes:
            dns_rules.append({"domain_suffix": dns_suffixes, "server": "dns-home"})
    dns_rules.append({"rule_set": "geosite-ru", "server": "dns-direct"})

    route_rules: list[dict] = [
        {"action": "sniff"},
        {"protocol": "dns", "action": "hijack-dns"},
        {"ip_cidr": endpoint_cidrs, "outbound": "direct"},
    ]
    if lan_cidrs:
        route_rules.append({"ip_cidr": lan_cidrs, "outbound": "direct"})
    if home_cidrs:
        route_rules.append({"ip_cidr": home_cidrs, "outbound": "home"})
    route_rules.extend([
        {"rule_set": "geosite-ru", "outbound": "direct"},
        {"rule_set": "geoip-ru", "outbound": "direct"},
    ])

    return {
        "log": {"level": "info", "timestamp": True},
        "dns": {
            "servers": dns_servers,
            "rules": dns_rules,
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
            "route_exclude_address": route_exclude,
        }],
        "endpoints": [mb_ep, hm_ep],
        "outbounds": [{"type": "direct", "tag": "direct"}],
        "route": {
            "auto_detect_interface": True,
            "default_domain_resolver": {"server": "dns-direct", "strategy": "ipv4_only"},
            "rules": route_rules,
            "final": "macbook",
            "rule_set": [
                {"type": "local", "tag": "geosite-ru", "format": "binary", "path": str(geosite_srs)},
                {"type": "local", "tag": "geoip-ru", "format": "binary", "path": str(geoip_srs)},
            ],
        },
    }


def write_probes(macbook, home, settings: dict, out_dir: Path) -> None:
    home_cidrs = _home_cidrs(home["peer"])
    home_ping = (settings.get("home_ping") or "").strip()
    if not home_ping and home_cidrs:
        home_ping = guess_gw(home_cidrs[0])
    mac_ping = (settings.get("macbook_ping") or "").strip() or _peer_lan_gw(macbook.get("address") or [])
    probes = {
        "home_ping": home_ping,
        "macbook_ping": mac_ping,
        "nas_host": (settings.get("nas_host") or "").strip(),
        "nas_mount": (settings.get("nas_mount") or "/Volumes/Nas").strip() or "/Volumes/Nas",
    }
    (out_dir / "probes.json").write_text(json.dumps(probes, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--macbook", type=Path, required=True)
    ap.add_argument("--home", type=Path, required=True)
    ap.add_argument("--geosite", type=Path, required=True)
    ap.add_argument("--geoip", type=Path, required=True)
    ap.add_argument("--settings", type=Path, default=None)
    ap.add_argument("-o", "--output", type=Path, required=True)
    args = ap.parse_args()
    for p in (args.macbook, args.home, args.geosite, args.geoip):
        if not p.exists():
            print(f"missing: {p}", file=sys.stderr)
            return 1
    settings = load_settings(args.settings)
    try:
        macbook = parse_conf(args.macbook)
        home = parse_conf(args.home)
        cfg = build_config(macbook, home, args.geosite, args.geoip, settings)
    except Exception as e:
        print(str(e), file=sys.stderr)
        return 1
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(cfg, indent=2) + "\n", encoding="utf-8")
    args.output.chmod(0o600)
    write_probes(macbook, home, settings, args.output.parent)
    print(f"wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
