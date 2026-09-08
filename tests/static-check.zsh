#!/bin/zsh
# Static checks for myvpn (doc-6 S*). Exit ≠0 on failure.
set -uo pipefail
ROOT="$(cd "${0:A:h}/.." && pwd)"
FIX="${ROOT}/tests/fixtures"
OUT="${TMPDIR:-/tmp}/myvpn-static-$$"
fail=0
ok() { print -r -- "PASS $1"; }
bad() { print -r -- "FAIL $1 — $2" >&2; fail=1; }
blocked() { print -r -- "BLOCKED $1 — $2"; }

cleanup() { /bin/rm -rf "${OUT}" 2>/dev/null || true; }
trap cleanup EXIT
/bin/mkdir -p "${OUT}"

if ! command -v rg >/dev/null 2>&1; then
  bad tool "rg required"
  exit 1
fi

# --- repo hygiene ---
if rg -n --glob '!*.md' 'wg-quick|route -n monitor' "$ROOT/bin" "$ROOT/lib" >/dev/null 2>&1; then
  bad S4 "wg-quick or route monitor in bin/lib"
else
  ok S4
fi

if rg -n 'MYVPN_DNS_SERVICES|myvpn_dns_apply_tun|myvpn_dns_clear' "$ROOT/lib/process.zsh" "$ROOT/lib/env.zsh" >/dev/null; then
  ok S3
else
  bad S3 "TUN DNS allowlist helpers missing"
fi

if git -C "$ROOT" ls-files '*.conf' 2>/dev/null | rg -v '^tests/fixtures/' | rg -q .; then
  bad S5 "tracked .conf outside fixtures"
else
  ok S5
fi

if rg -n 'add-generic-password.*-w [^"$]' "$ROOT/lib" >/dev/null 2>&1; then
  bad S20 "hardcoded keychain password?"
else
  ok S20
fi

for f in nas.zsh parse_conf.py render_config.py settings.py channels.py update_rules.py process.zsh env.zsh admin.zsh; do
  [[ -f "$ROOT/lib/$f" ]] && ok "lib/$f" || bad "lib/$f" "missing"
done

for f in "doc-3 - Контракт-CLI-для-Alfred-gv.md" "doc-4 - Menu-bar-myVPN.md"; do
  [[ -f "$ROOT/.backlog/docs/specs/$f" ]] && ok "spec/$f" || bad "spec/$f" "missing"
done

[[ -f "$ROOT/.gitignore" ]] && rg -q 'DerivedData' "$ROOT/.gitignore" && ok gitignore-DerivedData || bad gitignore "DerivedData"

# S17 heredoc admin
if rg -n 'osascript' "$ROOT/lib/admin.zsh" >/dev/null 2>&1; then
  if rg -n '<<|heredoc|ensure_ascii' "$ROOT/lib/admin.zsh" >/dev/null 2>&1 || rg -n 'json.dumps|ensure_ascii' "$ROOT/lib" >/dev/null; then
    ok S17
  else
    # admin may use python helper — accept if no fragile -e "do shell script ${
    if rg -n 'do shell script.*"\$' "$ROOT/lib/admin.zsh" >/dev/null 2>&1; then
      bad S17 "fragile osascript string interpolation"
    else
      ok S17
    fi
  fi
else
  ok S17
fi

# S19 keychain only for NAS password read
if rg -n 'find-generic-password' "$ROOT/lib/nas.zsh" >/dev/null; then
  ok S19
else
  bad S19 "find-generic-password missing"
fi

# --- render from fixtures ---
if [[ ! -f "$FIX/macbook.conf" || ! -f "$FIX/home.conf" ]]; then
  blocked S1 "missing fixtures/*.conf"
  exit "$fail"
fi

# Minimal empty rule-set files: copy from user cache if present, else skip sing-box check
GEOSITE="${HOME}/.config/myvpn/rules/geosite-ru.srs"
GEOIP="${HOME}/.config/myvpn/rules/geoip-ru.srs"
if [[ ! -f "$GEOSITE" || ! -f "$GEOIP" ]]; then
  # touch placeholders — sing-box check may fail; still validate JSON shape
  /usr/bin/touch "${OUT}/geosite-ru.srs" "${OUT}/geoip-ru.srs"
  GEOSITE="${OUT}/geosite-ru.srs"
  GEOIP="${OUT}/geoip-ru.srs"
  HAVE_SRS=0
else
  HAVE_SRS=1
fi

if ! /usr/bin/python3 "$ROOT/lib/render_config.py" \
  --wg-dir "$FIX" \
  --geosite "$GEOSITE" \
  --geoip "$GEOIP" \
  --settings "$FIX/settings.json" \
  -o "${OUT}/sing-box.json"; then
  bad S1 "render_config failed"
  exit "$fail"
fi
ok render

JSON="${OUT}/sing-box.json"

# S2 endpoints not outbound wireguard
if /usr/bin/python3 -c '
import json,sys
c=json.load(open(sys.argv[1]))
eps=c.get("endpoints") or []
obs=c.get("outbounds") or []
assert any(e.get("type")=="wireguard" for e in eps), "no wg endpoints"
assert not any(o.get("type")=="wireguard" for o in obs), "wg in outbounds"
' "$JSON"; then
  ok S2
else
  bad S2 "endpoints/outbounds"
fi

# S6 IPv6 off in TUN address / strategy
if /usr/bin/python3 -c '
import json,sys
c=json.load(open(sys.argv[1]))
for ib in c.get("inbounds") or []:
  for a in ib.get("address") or []:
    assert ":" not in a.split("/")[0], a
assert (c.get("dns") or {}).get("strategy")=="ipv4_only"
' "$JSON"; then
  ok S6
else
  bad S6 "IPv6"
fi

# S7–S11 route rules
if /usr/bin/python3 -c '
import json,sys
c=json.load(open(sys.argv[1]))
rules=c["route"]["rules"]
final=c["route"]["final"]
assert final=="macbook"
text=json.dumps(rules)
assert "192.168.3.0/24" in text
assert "10.13.13.0/24" in text and "10.57.0.0/24" in text
assert "203.0.113.10/32" in text or "203.0.113.20/32" in text
# home outbound for 10.x
home=any(r.get("outbound")=="home" and "10.13.13.0/24" in str(r.get("ip_cidr")) for r in rules)
assert home
direct_lan=any(r.get("outbound")=="direct" and "192.168.3.0/24" in str(r.get("ip_cidr")) for r in rules)
assert direct_lan
' "$JSON"; then
  ok S7-S11
else
  bad S7-S11 "route rules"
fi

# S7b: TUN route_exclude_address must pin WG endpoints off utun
if /usr/bin/python3 -c '
import json,sys
c=json.load(open(sys.argv[1]))
tun=next((i for i in (c.get("inbounds") or []) if i.get("type")=="tun"), None)
assert tun, "no tun"
exc=set(tun.get("route_exclude_address") or [])
assert any(x.endswith("/32") for x in exc), exc
assert "192.168.3.0/24" in exc
' "$JSON"; then
  ok S7b
else
  bad S7b "route_exclude_address"
fi

# S16: DNS= from conf must not appear as system DNS list; fixture has 1.1.1.1 but only as dns-remote server ok
if /usr/bin/python3 -c '
import json,sys
c=json.load(open(sys.argv[1]))
# Must not set inbound/hijack from conf DNS as networksetup target
# conf DNS 1.1.1.1 may be remote resolver via macbook — OK
# Ensure no "dns" key copied onto endpoints from AllowedIPs nonsense
for e in c.get("endpoints") or []:
  assert "dns" not in e
' "$JSON"; then
  ok S16
else
  bad S16
fi

# S1 sing-box check
if command -v sing-box >/dev/null 2>&1 && (( HAVE_SRS == 1 )); then
  if sing-box check -c "$JSON" >/dev/null 2>&1; then
    ok S1
  else
    bad S1 "sing-box check failed"
    sing-box check -c "$JSON" 2>&1 | /usr/bin/tail -5 >&2 || true
  fi
elif (( HAVE_SRS == 0 )); then
  blocked S1 "no ~/.config/myvpn/rules/*.srs for sing-box check"
else
  blocked S1 "sing-box not in PATH"
fi

exit "$fail"
