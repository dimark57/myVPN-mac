#!/usr/bin/env python3
"""Download ru-routing-dat sources, resolve includes, compile sing-box rule-set .srs."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from threading import Lock

BASE = "https://raw.githubusercontent.com/GrimbirdUsers/ru-routing-dat/main"
GEOSITE_ROOT = "category-ru-whitelist"
GEOIP_FILE = "data-geoip/ru.txt"


def fetch(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": "myvpn-update-rules/0"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read().decode("utf-8", errors="replace")


_CACHE_LOCK = Lock()


def fetch_geosite_file(name: str, cache: dict[str, str]) -> str:
    with _CACHE_LOCK:
        hit = cache.get(name)
    if hit is not None:
        return hit
    text = fetch(f"{BASE}/data-geosite/{name}")
    with _CACHE_LOCK:
        cache[name] = text
    return text


def parse_geosite_lines(name, cache, visiting, domain_suffix, domain, pool):
    if name in visiting:
        return
    visiting.add(name)
    text = fetch_geosite_file(name, cache)
    includes = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("include:"):
            includes.append(line.split(":", 1)[1].strip())
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
    missing = [n for n in includes if n not in cache]
    if missing:
        list(pool.map(lambda n: fetch_geosite_file(n, cache), missing))
    for inc in includes:
        parse_geosite_lines(inc, cache, visiting, domain_suffix, domain, pool)
    visiting.discard(name)


def build_geosite_rules():
    cache, domain_suffix, domain = {}, set(), set()
    with ThreadPoolExecutor(max_workers=8) as pool:
        parse_geosite_lines(GEOSITE_ROOT, cache, set(), domain_suffix, domain, pool)
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
        with ThreadPoolExecutor(max_workers=2) as ex:
            f_gs = ex.submit(build_geosite_rules)
            f_gi = ex.submit(build_geoip_rules)
            gs, gi = f_gs.result(), f_gi.result()
        gs_json, gi_json = out / "geosite-ru.json", out / "geoip-ru.json"
        gs_json.write_text(json.dumps(gs), encoding="utf-8")
        gi_json.write_text(json.dumps(gi), encoding="utf-8")
        with ThreadPoolExecutor(max_workers=2) as ex:
            f1 = ex.submit(compile_srs, args.sing_box, gs_json, out / "geosite-ru.srs")
            f2 = ex.submit(compile_srs, args.sing_box, gi_json, out / "geoip-ru.srs")
            f1.result()
            f2.result()
        print(f"ok geosite_rules={sum(len(r.get('domain_suffix',[]))+len(r.get('domain',[])) for r in gs['rules'])} geoip_cidrs={len(gi['rules'][0]['ip_cidr'])} -> {out}")
    except Exception as e:
        print(str(e), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
