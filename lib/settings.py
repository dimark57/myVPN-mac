#!/usr/bin/env python3
"""User routing/NAS settings (~/.config/myvpn/settings.json). No WG secrets."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Any

DEFAULTS: dict[str, Any] = {
    "lan_cidrs": [],
    "nas_host": "",
    "nas_share": "Nas",
    "nas_mount": "/Volumes/Nas",
    "nas_user": "NAS",
    "dns_home_server": "",
    "dns_suffixes": [],
    "home_ping": "",
    "macbook_ping": "",
}


def settings_path() -> Path:
    home = os.environ.get("MYVPN_HOME") or str(Path.home() / ".config" / "myvpn")
    return Path(home) / "settings.json"


def load_settings(path: Path | None = None) -> dict[str, Any]:
    p = path or settings_path()
    out = dict(DEFAULTS)
    if p.is_file():
        try:
            raw = json.loads(p.read_text(encoding="utf-8"))
            if isinstance(raw, dict):
                for k, v in raw.items():
                    if k in DEFAULTS:
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
    return out


def save_settings(data: dict[str, Any], path: Path | None = None) -> Path:
    p = path or settings_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    clean = {k: data.get(k, DEFAULTS[k]) for k in DEFAULTS}
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
