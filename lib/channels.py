#!/usr/bin/env python3
"""Named WireGuard channels + manual route table (settings.json).

World practice (Clash / sing-box / Surge): proxies are named independently of
routing rules. WireGuard.app couples AllowedIPs to the tunnel — we do not:
AllowedIPs in .conf are ignored for routing; routes[] decide outbound.

Legacy: macbook.conf + home.conf + lan_cidrs / home AllowedIPs → migrated once.
"""

from __future__ import annotations

import json
import os
import re
import uuid
from pathlib import Path
from typing import Any

from parse_conf import parse_conf

ID_RE = re.compile(r"^[a-z][a-z0-9_-]{0,31}$")

# Kept for migration / doctor aliases when user has not customized.
LEGACY_DEFAULT_ID = "macbook"
LEGACY_HOME_ID = "home"


def wg_dir() -> Path:
    return Path(os.environ.get("MYVPN_WG_DIR") or (Path.home() / ".config" / "wireguard"))


def settings_path() -> Path:
    home = os.environ.get("MYVPN_HOME") or str(Path.home() / ".config" / "myvpn")
    return Path(home) / "settings.json"


def slugify(name: str, existing: set[str] | None = None) -> str:
    base = re.sub(r"[^a-z0-9]+", "-", (name or "channel").lower()).strip("-")
    if not base or not base[0].isalpha():
        base = "ch-" + (base or "new")
    base = base[:32]
    existing = existing or set()
    if base not in existing and ID_RE.match(base):
        return base
    i = 2
    while True:
        cand = f"{base[:28]}-{i}"
        if cand not in existing and ID_RE.match(cand):
            return cand
        i += 1


def conf_template(address: str = "10.0.0.2/32") -> str:
    """Single WG template for every channel (user fills keys/endpoint)."""
    return (
        "[Interface]\n"
        "PrivateKey =\n"
        f"Address = {address}\n"
        "MTU = 1280\n"
        "\n"
        "[Peer]\n"
        "PublicKey =\n"
        "Endpoint = 203.0.113.10:51820\n"
        "AllowedIPs = 0.0.0.0/0\n"
        "PersistentKeepalive = 25\n"
    )


def default_channels() -> list[dict[str, Any]]:
    return [
        {
            "id": LEGACY_DEFAULT_ID,
            "name": "Egress",
            "file": f"{LEGACY_DEFAULT_ID}.conf",
            "is_default": True,
            "ping": "",
        },
        {
            "id": LEGACY_HOME_ID,
            "name": "Home",
            "file": f"{LEGACY_HOME_ID}.conf",
            "is_default": False,
            "ping": "",
        },
    ]


def default_routes() -> list[dict[str, Any]]:
    """Starter table — user edits; RU packs stay as optional rule_set rows."""
    return [
        {
            "id": str(uuid.uuid4())[:8],
            "type": "cidr",
            "match": ["192.168.0.0/16"],
            "via": "direct",
            "note": "LAN",
        },
        {
            "id": str(uuid.uuid4())[:8],
            "type": "rule_set",
            "match": "geosite-ru",
            "via": "direct",
            "note": "RU domains",
        },
        {
            "id": str(uuid.uuid4())[:8],
            "type": "rule_set",
            "match": "geoip-ru",
            "via": "direct",
            "note": "RU IP",
        },
    ]


def _home_cidrs_from_conf(path: Path) -> list[str]:
    if not path.is_file():
        return []
    try:
        peer = parse_conf(path)["peer"]
    except Exception:
        return []
    out: list[str] = []
    for cidr in peer.get("allowed_ips") or []:
        c = cidr.strip()
        if not c or c == "0.0.0.0/0" or c.startswith("::"):
            continue
        out.append(c)
    return out


def migrate_if_needed(raw: dict[str, Any], wg: Path | None = None) -> dict[str, Any]:
    """Ensure channels[] + routes[] exist; pull from legacy fields / confs."""
    out = dict(raw)
    wg = wg or wg_dir()
    channels = out.get("channels")
    if not isinstance(channels, list) or not channels:
        ch = default_channels()
        # Prefer existing ping fields
        if out.get("macbook_ping"):
            ch[0]["ping"] = str(out["macbook_ping"])
        if out.get("home_ping"):
            ch[1]["ping"] = str(out["home_ping"])
        # Drop missing legacy files from list if user only has custom names later
        out["channels"] = ch

    routes = out.get("routes")
    if not isinstance(routes, list) or not routes:
        routes = []
        lan = [c for c in (out.get("lan_cidrs") or []) if c]
        if lan:
            routes.append({
                "id": str(uuid.uuid4())[:8],
                "type": "cidr",
                "match": lan,
                "via": "direct",
                "note": "LAN",
            })
        home_file = wg / f"{LEGACY_HOME_ID}.conf"
        home_cidrs = _home_cidrs_from_conf(home_file)
        if home_cidrs:
            routes.append({
                "id": str(uuid.uuid4())[:8],
                "type": "cidr",
                "match": home_cidrs,
                "via": LEGACY_HOME_ID,
                "note": "Home (из AllowedIPs)",
            })
        # Always seed RU packs if empty migration
        have_gs = any(
            isinstance(r, dict) and r.get("type") == "rule_set" and r.get("match") == "geosite-ru"
            for r in routes
        )
        if not have_gs:
            routes.extend([
                {
                    "id": str(uuid.uuid4())[:8],
                    "type": "rule_set",
                    "match": "geosite-ru",
                    "via": "direct",
                    "note": "RU domains",
                },
                {
                    "id": str(uuid.uuid4())[:8],
                    "type": "rule_set",
                    "match": "geoip-ru",
                    "via": "direct",
                    "note": "RU IP",
                },
            ])
        if not routes:
            routes = default_routes()
        out["routes"] = routes

    # Normalize channels
    norm_ch: list[dict[str, Any]] = []
    seen: set[str] = set()
    for c in out["channels"]:
        if not isinstance(c, dict):
            continue
        cid = str(c.get("id") or "").strip()
        if not ID_RE.match(cid) or cid in seen:
            continue
        seen.add(cid)
        name = str(c.get("name") or cid).strip() or cid
        file = str(c.get("file") or f"{cid}.conf").strip()
        if not file.endswith(".conf"):
            file = f"{file}.conf"
        norm_ch.append({
            "id": cid,
            "name": name,
            "file": file,
            "is_default": bool(c.get("is_default")),
            "ping": str(c.get("ping") or "").strip(),
        })
    if not norm_ch:
        norm_ch = default_channels()
    # Exactly one default
    if not any(c["is_default"] for c in norm_ch):
        norm_ch[0]["is_default"] = True
    else:
        found = False
        for c in norm_ch:
            if c["is_default"] and not found:
                found = True
            elif c["is_default"]:
                c["is_default"] = False
    out["channels"] = norm_ch

    # Normalize routes
    norm_rt: list[dict[str, Any]] = []
    for r in out["routes"]:
        if not isinstance(r, dict):
            continue
        rtype = str(r.get("type") or "cidr")
        via = str(r.get("via") or "direct").strip() or "direct"
        note = str(r.get("note") or "").strip()
        rid = str(r.get("id") or str(uuid.uuid4())[:8])
        if rtype == "rule_set":
            match = r.get("match")
            if isinstance(match, list):
                match = match[0] if match else ""
            match = str(match or "").strip()
            if not match:
                continue
            norm_rt.append({"id": rid, "type": "rule_set", "match": match, "via": via, "note": note})
        else:
            match = r.get("match")
            if isinstance(match, str):
                match = [x.strip() for x in match.split(",") if x.strip()]
            elif not isinstance(match, list):
                match = []
            match = [str(x).strip() for x in match if str(x).strip()]
            if not match:
                continue
            norm_rt.append({"id": rid, "type": "cidr", "match": match, "via": via, "note": note})
    out["routes"] = norm_rt

    # Sync lan_cidrs for older readers
    lan = []
    for r in norm_rt:
        if r["type"] == "cidr" and r["via"] == "direct":
            lan.extend(r["match"])
    out["lan_cidrs"] = lan

    # Sync legacy ping keys
    for c in norm_ch:
        if c["id"] == LEGACY_DEFAULT_ID and c.get("ping"):
            out["macbook_ping"] = c["ping"]
        if c["id"] == LEGACY_HOME_ID and c.get("ping"):
            out["home_ping"] = c["ping"]

    if "dns_via" not in out or not out["dns_via"]:
        # Prefer home channel for DNS if present
        out["dns_via"] = LEGACY_HOME_ID if any(c["id"] == LEGACY_HOME_ID for c in norm_ch) else (
            next((c["id"] for c in norm_ch if not c["is_default"]), norm_ch[0]["id"])
        )

    return out


def load_topology(path: Path | None = None, wg: Path | None = None) -> dict[str, Any]:
    p = path or settings_path()
    raw: dict[str, Any] = {}
    if p.is_file():
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                raw = data
        except (OSError, json.JSONDecodeError):
            raw = {}
    return migrate_if_needed(raw, wg or wg_dir())


def default_channel_id(topo: dict[str, Any]) -> str:
    for c in topo.get("channels") or []:
        if c.get("is_default"):
            return c["id"]
    ch = topo.get("channels") or []
    return ch[0]["id"] if ch else LEGACY_DEFAULT_ID


def channel_by_id(topo: dict[str, Any], cid: str) -> dict[str, Any] | None:
    for c in topo.get("channels") or []:
        if c.get("id") == cid:
            return c
    return None
