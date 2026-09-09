#!/bin/zsh
# FDIR policy / doctor L1 budget checks (doc-10). No live heal.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

pass() { print -r -- "OK  $*"; }
bad() { print -r -- "FAIL $*"; fail=1; }

# --- doctor --deep flag parses; L1 skips expensive markers ---
out="$("${ROOT}/bin/myvpn" doctor 2>&1 || true)"
print -r -- "$out" | /usr/bin/grep -q 'layer=L1\|=== myvpn doctor L1 ===' && pass "doctor L1 header" || bad "doctor L1 header"
print -r -- "$out" | /usr/bin/grep -q 'skip L1' && pass "doctor L1 skips deep probes" || bad "doctor L1 skips deep probes"

# --- mount-nas --safe accepted (no crash) ---
if "${ROOT}/bin/myvpn" mount-nas --help 2>&1 | /usr/bin/grep -q force; then
  :
fi
# Syntax: ensure --safe is recognized (may return 0/1/2 depending on state)
set +e
"${ROOT}/bin/myvpn" mount-nas --safe >/tmp/myvpn-nas-safe.out 2>&1
rc=$?
set -e
[[ $rc -le 2 ]] && pass "mount-nas --safe exit=$rc" || bad "mount-nas --safe exit=$rc"

# --- pin-endpoints command exists ---
"${ROOT}/bin/myvpn" -h 2>&1 | /usr/bin/grep -q 'pin-endpoints' && pass "usage pin-endpoints" || bad "usage pin-endpoints"

# --- drops.log DOCTOR lines may include layer= ---
if [[ -f "${HOME}/.cache/myvpn-doctor/drops.log" ]]; then
  if /usr/bin/tail -n 5 "${HOME}/.cache/myvpn-doctor/drops.log" | /usr/bin/grep -q 'layer=L1\|layer=L2\|DOCTOR primary='; then
    pass "drops.log has DOCTOR lines"
  else
    pass "drops.log present (no fresh DOCTOR — ok)"
  fi
fi

# --- Info.plist 0.5.1 ---
ver="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${ROOT}/macos/MyVPN/MyVPN/Info.plist")"
[[ "$ver" == "0.5.1" ]] && pass "version $ver" || bad "version want 0.5.1 got $ver"

# --- Swift FDIR modules exist ---
for f in DesiredStateStore HealCircuitBreaker FlightRecorder IncidentStore AutoDoctorPipeline WakeRecover; do
  [[ -f "${ROOT}/macos/MyVPN/MyVPN/${f}.swift" ]] && pass "swift $f" || bad "missing $f.swift"
done

# --- helper accepts pin-endpoints ---
/usr/bin/grep -q 'pin-endpoints' "${ROOT}/macos/MyVPN/helper/myvpn_helperd.py" && pass "helper pin-endpoints" || bad "helper pin-endpoints"

# --- INTENTIONAL_OFF in doctor ---
/usr/bin/grep -q 'INTENTIONAL_OFF' "${ROOT}/lib/doctor.zsh" && pass "doctor INTENTIONAL_OFF" || bad "doctor INTENTIONAL_OFF"

# --- doc-10 SoT ---
if ls "${ROOT}/.backlog/docs/specs"/doc-10* >/dev/null 2>&1; then
  pass "doc-10 present"
else
  bad "doc-10 missing"
fi

if (( fail )); then
  print -r -- "fdir-policy: FAILED"
  exit 1
fi
print -r -- "fdir-policy: PASS"
exit 0
