#!/bin/zsh
# Relaunch menu bar UI only — never myvpn down / helper kill / NAS unmount.
set -euo pipefail
APP="${HOME}/Applications/myVPN.app"
MYVPN="${APP}/Contents/Resources/runtime/bin/myvpn"
[[ -d "${APP}" ]] || { print -r -- "missing ${APP}" >&2; exit 1; }

before="$("${MYVPN}" status 2>/dev/null || true)"
print -r -- "before:"
print -r -- "${before}"

# UI process only (bundle id / binary name myVPN — not sing-box, not helper).
/usr/bin/osascript -e 'tell application id "local.myvpn.mac" to quit' >/dev/null 2>&1 || true
# Failsafe if osascript misses accessory app.
/usr/bin/pkill -x myVPN >/dev/null 2>&1 || true
sleep 1

open -a "${APP}"
# Wait until menu bar process is back.
for _ in {1..30}; do
  pgrep -x myVPN >/dev/null && break
  sleep 0.2
done

sleep 2
after="$("${MYVPN}" status 2>/dev/null || true)"
print -r -- "after:"
print -r -- "${after}"

if print -r -- "${after}" | grep -q '^tun=1'; then
  print -r -- "ok: VPN still up (no down)"
else
  print -r -- "WARN: tun!=1 after relaunch — check helper / menu" >&2
  exit 2
fi
if print -r -- "${after}" | grep -q '^nas=1'; then
  print -r -- "ok: NAS still mounted"
else
  print -r -- "WARN: nas!=1 — workspace may be at risk" >&2
fi
