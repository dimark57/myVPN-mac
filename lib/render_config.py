#!/usr/bin/env python3
"""Render sing-box JSON from named channels + manual routes (settings.json).

Uses: parse_conf.py, channels.py, settings.py (NAS/DNS scalars).
Routing is NOT taken from WG AllowedIPs — only from routes[].
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from channels import (  # noqa: E402
    default_channel_id,
    load_topology,
    wg_dir,
)
from parse_conf import parse_conf  # noqa: E402
from settings import guess_gw, load_settings  # noqa: E402


def _peer_lan_gw(addresses: list[str]) -> str:
    addr0 = (addresses or [""])[0]
    ip = addr0.split("/")[0]
    parts = ip.split(".")
    if len(parts) == 4:
        return f"{parts[0]}.{parts[1]}.{parts[2]}.1"
    return ""


def _endpoint_from_conf(tag: str, conf: dict) -> dict:
    peer = conf["peer"]
    ep = {
        "type": "wireguard",
        "tag": tag,
        "system": False,
        "address": conf["address"],
        "private_key": conf["private_key"],
        "peers": [{
            # WG layer catch-all; sing-box route rules pick the outbound.
            "address": peer["address"],
            "port": peer["port"],
            "public_key": peer["public_key"],
            "allowed_ips": ["0.0.0.0/0"],
            "persistent_keepalive_interval": peer.get("persistent_keepalive_interval", 25),
        }],
    }
    if "mtu" in conf:
        ep["mtu"] = conf["mtu"]
    if "pre_shared_key" in peer:
        ep["peers"][0]["pre_shared_key"] = peer["pre_shared_key"]
    return ep


def build_config(
    channel_confs: dict[str, dict],
    topo: dict,
    geosite_srs: Path,
    geoip_srs: Path,
    settings: dict | None = None,
) -> dict:
    settings = settings or {}
    channels = topo.get("channels") or []
    routes = topo.get("routes") or []
    final_tag = default_channel_id(topo)
    if final_tag not in channel_confs:
        raise ValueError(f"default channel '{final_tag}' conf missing")

    endpoints = []
    endpoint_cidrs: list[str] = []
    for ch in channels:
        cid = ch["id"]
        if cid not in channel_confs:
            raise ValueError(f"missing conf for channel '{cid}' ({ch.get('file')})")
        conf = channel_confs[cid]
        endpoints.append(_endpoint_from_conf(cid, conf))
        endpoint_cidrs.append(f"{conf['peer']['address']}/32")

    # Exclude WG endpoints + direct CIDR routes from TUN hijack
    route_exclude = list(endpoint_cidrs)
    for r in routes:
        if r.get("type") == "cidr" and r.get("via") == "direct":
            route_exclude.extend(r.get("match") or [])

    dns_via = (topo.get("dns_via") or final_tag).strip()
    if dns_via not in channel_confs and dns_via != "direct":
        dns_via = final_tag

    dns_servers = [
        {"type": "udp", "tag": "dns-remote", "server": "1.1.1.1", "server_port": 53, "detour": final_tag},
        {"type": "udp", "tag": "dns-direct", "server": "8.8.8.8", "server_port": 53},
    ]
    dns_rules: list[dict] = []
    dns_home = (settings.get("dns_home_server") or "").strip()
    dns_suffixes = [s for s in (settings.get("dns_suffixes") or []) if s]
    if dns_home and dns_via in channel_confs:
        dns_servers.insert(0, {
            "type": "udp",
            "tag": "dns-home",
            "server": dns_home,
            "server_port": 53,
            "detour": dns_via,
        })
        if dns_suffixes:
            dns_rules.append({"domain_suffix": dns_suffixes, "server": "dns-home"})

    # DNS for RU rule_set rows that go direct
    if any(r.get("type") == "rule_set" and r.get("match") == "geosite-ru" and r.get("via") == "direct" for r in routes):
        dns_rules.append({"rule_set": "geosite-ru", "server": "dns-direct"})

    known = set(channel_confs) | {"direct"}
    route_rules: list[dict] = [
        {"action": "sniff"},
        {"protocol": "dns", "action": "hijack-dns"},
        {"ip_cidr": endpoint_cidrs, "outbound": "direct"},
    ]
    for r in routes:
        via = r.get("via") or "direct"
        if via not in known:
            raise ValueError(f"route via unknown channel '{via}'")
        if r.get("type") == "cidr":
            cidrs = r.get("match") or []
            if cidrs:
                route_rules.append({"ip_cidr": cidrs, "outbound": via})
        elif r.get("type") == "rule_set":
            tag = r.get("match")
            if tag:
                route_rules.append({"rule_set": tag, "outbound": via})

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
        "endpoints": endpoints,
        "outbounds": [{"type": "direct", "tag": "direct"}],
        "route": {
            "auto_detect_interface": True,
            "default_domain_resolver": {"server": "dns-direct", "strategy": "ipv4_only"},
            "rules": route_rules,
            "final": final_tag,
            "rule_set": [
                {"type": "local", "tag": "geosite-ru", "format": "binary", "path": str(geosite_srs)},
                {"type": "local", "tag": "geoip-ru", "format": "binary", "path": str(geoip_srs)},
            ],
        },
    }


def write_probes(channel_confs: dict[str, dict], topo: dict, settings: dict, out_dir: Path) -> None:
    peers: dict[str, dict] = {}
    for ch in topo.get("channels") or []:
        cid = ch["id"]
        conf = channel_confs.get(cid) or {}
        ping = (ch.get("ping") or "").strip()
        if not ping:
            # Guess .1 from first CIDR route targeting this channel
            for r in topo.get("routes") or []:
                if r.get("type") == "cidr" and r.get("via") == cid and r.get("match"):
                    ping = guess_gw(r["match"][0])
                    if ping:
                        break
        if not ping:
            ping = _peer_lan_gw(conf.get("address") or [])
        peers[cid] = {
            "name": ch.get("name") or cid,
            "ping": ping,
            "is_default": bool(ch.get("is_default")),
        }

    final_tag = default_channel_id(topo)
    probes = {
        "default": final_tag,
        "peers": peers,
        # Legacy keys for StatusSnapshot / doctor until fully dynamic
        "macbook_ping": (peers.get("macbook") or peers.get(final_tag) or {}).get("ping", ""),
        "home_ping": (peers.get("home") or next(
            (p.get("ping") for i, p in peers.items() if i != final_tag),
            "",
        )),
        "nas_host": (settings.get("nas_host") or "").strip(),
        "nas_mount": (settings.get("nas_mount") or "/Volumes/Nas").strip() or "/Volumes/Nas",
    }
    (out_dir / "probes.json").write_text(json.dumps(probes, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--wg-dir", type=Path, default=None)
    ap.add_argument("--macbook", type=Path, default=None, help="legacy; ignored if channels in settings")
    ap.add_argument("--home", type=Path, default=None, help="legacy; ignored if channels in settings")
    ap.add_argument("--geosite", type=Path, required=True)
    ap.add_argument("--geoip", type=Path, required=True)
    ap.add_argument("--settings", type=Path, default=None)
    ap.add_argument("-o", "--output", type=Path, required=True)
    args = ap.parse_args()

    for p in (args.geosite, args.geoip):
        if not p.exists():
            print(f"missing: {p}", file=sys.stderr)
            return 1

    settings = load_settings(args.settings)
    topo = load_topology(args.settings, args.wg_dir or wg_dir())
    # Persist migration so UI sees channels/routes
    try:
        from settings import save_settings  # local
        # merge topo keys into full settings save
        merged = dict(settings)
        for k in ("channels", "routes", "dns_via", "lan_cidrs", "macbook_ping", "home_ping"):
            if k in topo:
                merged[k] = topo[k]
        # save_settings only knows DEFAULTS — write raw
        path = args.settings or Path(
            __import__("os").environ.get("MYVPN_HOME")
            or str(Path.home() / ".config" / "myvpn")
        ) / "settings.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        # Keep unknown keys from original file
        raw = {}
        if path.is_file():
            try:
                raw = json.loads(path.read_text(encoding="utf-8"))
            except Exception:
                raw = {}
        if not isinstance(raw, dict):
            raw = {}
        raw.update({k: merged[k] for k in merged if k in (
            "lan_cidrs", "nas_host", "nas_share", "nas_mount", "nas_user",
            "dns_home_server", "dns_suffixes", "home_ping", "macbook_ping",
            "channels", "routes", "dns_via",
        )})
        path.write_text(json.dumps(raw, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        path.chmod(0o600)
    except Exception as e:
        print(f"warn: could not persist topology: {e}", file=sys.stderr)

    wdir = args.wg_dir or wg_dir()
    channel_confs: dict[str, dict] = {}
    try:
        for ch in topo["channels"]:
            conf_path = wdir / ch["file"]
            if not conf_path.is_file():
                print(f"missing: {conf_path}", file=sys.stderr)
                return 1
            channel_confs[ch["id"]] = parse_conf(conf_path)
        cfg = build_config(channel_confs, topo, args.geosite, args.geoip, settings)
    except Exception as e:
        print(str(e), file=sys.stderr)
        return 1

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(cfg, indent=2) + "\n", encoding="utf-8")
    args.output.chmod(0o600)
    write_probes(channel_confs, topo, settings, args.output.parent)
    print(f"wrote {args.output} channels={len(channel_confs)} routes={len(topo.get('routes') or [])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
