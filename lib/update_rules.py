#!/usr/bin/env python3
"""Download ru-routing-dat sources, resolve includes, compile sing-box rule-set .srs."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import urllib.request
from pathlib import Path

BASE = "https://raw.githubusercontent.com/GrimbirdUsers/ru-routing-dat/main"
GEOSITE_ROOT = "category-ru-whitelist"
GEOIP_FILE = "data-geoip/ru.txt"


def fetch(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": "myvpn-update-rules/0"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read().decode("utf-8", errors="replace")


def fetch_geosite_file(name: str, cache: dict[str, str]) -> str:
    if name in cache:
        return cache[name]
    text = fetch(f"{BASE}/data-geosite/{name}")
    cache[name] = text
    return text


def parse_geosite_lines(name, cache, visiting, domain_suffix, domain):
    if name in visiting:
        return
    visiting.add(name)
    text = fetch_geosite_file(name, cache)
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("include:"):
            parse_geosite_lines(line.split(":", 1)[1].strip(), cache, visiting, domain_suffix, domain)
            continue
        if ":" in line:
            kind, _, rest = line.partition(":")
            rest = rest.strip()
            if kind == "domain":
                domain_suffix.add(rest)
            elif kind == "full":
                domain.add(rest)
            elif kind in ("keyword", "regexp"):
                continue
            else:
                domain_suffix.add(line)
        else:
            domain_suffix.add(line)
    visiting.discard(name)


def build_geosite_rules():
    cache, domain_suffix, domain = {}, set(), set()
    parse_geosite_lines(GEOSITE_ROOT, cache, set(), domain_suffix, domain)
    rules = []
    if domain_suffix:
        rules.append({"domain_suffix": sorted(domain_suffix)})
    if domain:
        rules.append({"domain": sorted(domain)})
    if not rules:
        raise RuntimeError("geosite: empty after resolve")
    return {"version": 3, "rules": rules}


def build_geoip_rules():
    text = fetch(f"{BASE}/{GEOIP_FILE}")
    cidrs = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if ":" in line.split("/")[0]:
            continue
        cidrs.append(line)
    if not cidrs:
        raise RuntimeError("geoip: empty")
    return {"version": 3, "rules": [{"ip_cidr": cidrs}]}


def compile_srs(sing_box, src, dst):
    dst.parent.mkdir(parents=True, exist_ok=True)
    r = subprocess.run([sing_box, "rule-set", "compile", str(src), "-o", str(dst)], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(r.stderr or r.stdout or "compile failed")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out-dir", type=Path, required=True)
    ap.add_argument("--sing-box", default="sing-box")
    args = ap.parse_args()
    out = args.out_dir
    out.mkdir(parents=True, exist_ok=True)
    try:
        gs, gi = build_geosite_rules(), build_geoip_rules()
        gs_json, gi_json = out / "geosite-ru.json", out / "geoip-ru.json"
        gs_json.write_text(json.dumps(gs), encoding="utf-8")
        gi_json.write_text(json.dumps(gi), encoding="utf-8")
        compile_srs(args.sing_box, gs_json, out / "geosite-ru.srs")
        compile_srs(args.sing_box, gi_json, out / "geoip-ru.srs")
        print(f"ok geosite_rules={sum(len(r.get('domain_suffix',[]))+len(r.get('domain',[])) for r in gs['rules'])} geoip_cidrs={len(gi['rules'][0]['ip_cidr'])} -> {out}")
    except Exception as e:
        print(str(e), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
