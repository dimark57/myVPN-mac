#!/usr/bin/env python3
"""User settings (~/.config/myvpn/settings.json). No WG secrets.

Scalars: NAS/DNS. Topology: channels[] + routes[] (see channels.py).
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Any

SCALAR_DEFAULTS: dict[str, Any] = {
    "lan_cidrs": [],
    "nas_host": "",
    "nas_share": "Nas",
    "nas_mount": "/Volumes/Nas",
    "nas_user": "NAS",
    "dns_home_server": "",
    "dns_suffixes": [],
    "home_ping": "",
    "macbook_ping": "",
    "dns_via": "",
}

# Back-compat alias
DEFAULTS = SCALAR_DEFAULTS


def settings_path() -> Path:
    home = os.environ.get("MYVPN_HOME") or str(Path.home() / ".config" / "myvpn")
    return Path(home) / "settings.json"


def load_settings(path: Path | None = None) -> dict[str, Any]:
    p = path or settings_path()
    out = dict(SCALAR_DEFAULTS)
    raw: dict[str, Any] = {}
    if p.is_file():
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                raw = data
                for k, v in data.items():
                    if k in SCALAR_DEFAULTS:
                        out[k] = v
        except (OSError, json.JSONDecodeError):
            pass
    # Env overrides (install / tests)
    if os.environ.get("MYVPN_LAN_CIDRS"):
        out["lan_cidrs"] = [x.strip() for x in os.environ["MYVPN_LAN_CIDRS"].split(",") if x.strip()]
    if os.environ.get("MYVPN_DNS_SUFFIXES"):
        out["dns_suffixes"] = [x.strip() for x in os.environ["MYVPN_DNS_SUFFIXES"].split(",") if x.strip()]
    if os.environ.get("MYVPN_DNS_HOME"):
        out["dns_home_server"] = os.environ["MYVPN_DNS_HOME"].strip()
    if os.environ.get("MYVPN_NAS_HOST"):
        out["nas_host"] = os.environ["MYVPN_NAS_HOST"].strip()
    if os.environ.get("MYVPN_NAS_SHARE"):
        out["nas_share"] = os.environ["MYVPN_NAS_SHARE"].strip()
    if os.environ.get("MYVPN_HOME_PING"):
        out["home_ping"] = os.environ["MYVPN_HOME_PING"].strip()
    if os.environ.get("MYVPN_MACBOOK_PING"):
        out["macbook_ping"] = os.environ["MYVPN_MACBOOK_PING"].strip()
    # Pass through topology if present (render / UI)
    for k in ("channels", "routes", "dns_via"):
        if k in raw:
            out[k] = raw[k]
    return out


def save_settings(data: dict[str, Any], path: Path | None = None) -> Path:
    p = path or settings_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    existing: dict[str, Any] = {}
    if p.is_file():
        try:
            existing = json.loads(p.read_text(encoding="utf-8"))
            if not isinstance(existing, dict):
                existing = {}
        except (OSError, json.JSONDecodeError):
            existing = {}
    clean = dict(existing)
    for k in SCALAR_DEFAULTS:
        if k in data:
            clean[k] = data[k]
    for k in ("channels", "routes", "dns_via"):
        if k in data:
            clean[k] = data[k]
    p.write_text(json.dumps(clean, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    p.chmod(0o600)
    return p


def guess_gw(cidr: str) -> str:
    """Best-effort .1 in the network for ping probes."""
    ip, _, pfx = cidr.partition("/")
    parts = ip.split(".")
    if len(parts) != 4:
        return ""
    try:
        int(pfx or "24")
    except ValueError:
        return ""
    return f"{parts[0]}.{parts[1]}.{parts[2]}.1"


def main() -> int:
    ap = argparse.ArgumentParser(description="myVPN settings.json")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--path", type=Path)
    args = ap.parse_args()
    data = load_settings(args.path)
    if args.json:
        print(json.dumps(data, ensure_ascii=False))
    else:
        print(settings_path())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
