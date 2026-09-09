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

# --- UI_CMD coverage 0.5.15 ---
/usr/bin/grep -q 'func uiCmd' "${ROOT}/macos/MyVPN/MyVPN/AppDelegate.swift" && pass "uiCmd helper" || bad "uiCmd helper"
/usr/bin/grep -q 'send-report github-issues' "${ROOT}/macos/MyVPN/MyVPN/AppDelegate.swift" && pass "UI_CMD send-report" || bad "UI_CMD send-report"
/usr/bin/grep -qE 'UI_CMD autostart|uiCmd\("autostart' "${ROOT}/macos/MyVPN/MyVPN/ConnectionSettingsWindowController.swift" && pass "UI_CMD autostart" || bad "UI_CMD autostart"
/usr/bin/grep -qE 'UI_CMD auto-nas|uiCmd\("auto-nas' "${ROOT}/macos/MyVPN/MyVPN/ConnectionSettingsWindowController.swift" && pass "UI_CMD auto-nas" || bad "UI_CMD auto-nas"
/usr/bin/grep -q 'uiCmd("quit")' "${ROOT}/macos/MyVPN/MyVPN/AppDelegate.swift" && pass "UI_CMD quit" || bad "UI_CMD quit"

# --- Remount 0.5.14 ---
/usr/bin/grep -q '\-\-remount' "${ROOT}/lib/nas.zsh" && pass "nas --remount" || bad "nas --remount"
/usr/bin/grep -q 'myvpn_nas_graceful_unmount\|nas unmount' "${ROOT}/lib/nas.zsh" && pass "nas graceful unmount" || bad "nas graceful unmount"
/usr/bin/grep -q 'remount: true\|remount: Bool' "${ROOT}/macos/MyVPN/MyVPN/MyVPNCLI.swift" && pass "CLI remount param" || bad "CLI remount param"
/usr/bin/grep -q 'UI_CMD mount-nas remount=\|mount-nas remount=' "${ROOT}/macos/MyVPN/MyVPN/AppDelegate.swift" && pass "UI remount flag" || bad "UI remount flag"

# --- ship.zsh / release NO_BUMP (cd macos-gh-app) ---
[[ -x "${ROOT}/macos/MyVPN/ship.zsh" ]] && pass "ship.zsh executable" || bad "ship.zsh executable"
/usr/bin/grep -q 'MYVPN_RELEASE_NO_BUMP' "${ROOT}/macos/MyVPN/ship.zsh" && pass "ship uses NO_BUMP" || bad "ship uses NO_BUMP"
/usr/bin/grep -q 'MYVPN_RELEASE_NO_BUMP' "${ROOT}/macos/MyVPN/release.zsh" && pass "release respects NO_BUMP" || bad "release respects NO_BUMP"
/usr/bin/grep -q 'macos-gh-app' "${ROOT}/AGENTS.md" && pass "AGENTS macos-gh-app" || bad "AGENTS macos-gh-app"

# --- doctor soft checks 0.5.16 (NAS root = WARN not FAIL; autostart off = INFO) ---
/usr/bin/grep -q 'dev/NAS' "${ROOT}/lib/doctor.zsh" && pass "runtime_local soft WARN text" || bad "runtime_local soft WARN text"
/usr/bin/grep -q '_doc_check "runtime_local" "2"' "${ROOT}/lib/doctor.zsh" && pass "runtime_local WARN code" || bad "runtime_local WARN code"
/usr/bin/grep -q '_doc_check "autostart" "3"' "${ROOT}/lib/doctor.zsh" && pass "autostart off INFO" || bad "autostart off INFO"

# --- Info.plist 0.5.16 ---
ver="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${ROOT}/macos/MyVPN/MyVPN/Info.plist")"
[[ "$ver" == "0.5.16" ]] && pass "version $ver" || bad "version want 0.5.16 got $ver"


# --- helper protocol 2 (app + daemon) ---
/usr/bin/grep -q 'HELPER_PROTO = 2' "${ROOT}/macos/MyVPN/helper/myvpn_helperd.py" && pass "helper HELPER_PROTO=2" || bad "helper HELPER_PROTO=2"
/usr/bin/grep -q 'requiredProtocol = 2' "${ROOT}/macos/MyVPN/MyVPN/MyVPNHelper.swift" && pass "app requiredProtocol=2" || bad "app requiredProtocol=2"
/usr/bin/grep -q 'promptHelperUpgradeIfNeeded' "${ROOT}/macos/MyVPN/MyVPN/AppDelegate.swift" && pass "helper upgrade prompt" || bad "helper upgrade prompt"

# --- Swift FDIR modules exist ---
for f in DesiredStateStore HealCircuitBreaker FlightRecorder IncidentStore AutoDoctorPipeline WakeRecover SingleInstance; do
  [[ -f "${ROOT}/macos/MyVPN/MyVPN/${f}.swift" ]] && pass "swift $f" || bad "missing $f.swift"
done

# --- Fast up 0.5.13 ---
/usr/bin/grep -q 'MYVPN_SKIP_AUTO_NAS' "${ROOT}/macos/MyVPN/helper/myvpn_helperd.py" && pass "helper SKIP_AUTO_NAS" || bad "helper SKIP_AUTO_NAS"
/usr/bin/grep -q 'MYVPN_QUIET' "${ROOT}/bin/myvpn" && pass "bin/myvpn QUIET skip auto-nas" || bad "bin/myvpn QUIET skip auto-nas"
/usr/bin/grep -q 'myvpn_cmd_mount_nas --safe' "${ROOT}/lib/nas.zsh" && pass "after_up --safe only" || bad "after_up --safe only"
/usr/bin/grep -q 'UI_MOUNT skip=already_mounted' "${ROOT}/macos/MyVPN/MyVPN/AppDelegate.swift" && pass "UI skip mount if live" || bad "UI skip mount if live"
/usr/bin/grep -q 'timeout: 50' "${ROOT}/macos/MyVPN/MyVPN/AppDelegate.swift" && pass "UI up watchdog 50s" || bad "UI up watchdog 50s"

# --- Live menu status 0.5.12 ---
/usr/bin/grep -q 'nasInMountTable\|nasMounted(at:' "${ROOT}/macos/MyVPN/MyVPN/StatusSnapshot.swift" && pass "NAS mount-table probe" || bad "NAS mount-table probe"
/usr/bin/grep -q 'UI_MOUNT soft=1' "${ROOT}/macos/MyVPN/MyVPN/AppDelegate.swift" && pass "UI_MOUNT soft timeout" || bad "UI_MOUNT soft timeout"
/usr/bin/grep -q 'Rebuild even while busy' "${ROOT}/macos/MyVPN/MyVPN/AppDelegate.swift" && pass "menu rebuild while busy" || bad "menu rebuild while busy"

# --- Cooldown / egress 0.5.11 ---
/usr/bin/grep -q 'cooldown_bypass=new_primary' "${ROOT}/macos/MyVPN/MyVPN/AutoDoctor.swift" && pass "cooldown bypass new_primary" || bad "cooldown bypass new_primary"
/usr/bin/grep -q 'last_primary=' "${ROOT}/macos/MyVPN/MyVPN/AutoDoctor.swift" && pass "cooldown last_primary in reason" || bad "cooldown last_primary in reason"
/usr/bin/grep -q 'EGRESS_PROBE empty keep_cached' "${ROOT}/macos/MyVPN/MyVPN/AppDelegate.swift" && pass "EGRESS_PROBE keep_cached" || bad "EGRESS_PROBE keep_cached"
/usr/bin/grep -q 'AUTO_DOCTOR ok=1 soft=1' "${ROOT}/macos/MyVPN/MyVPN/AutoDoctorPipeline.swift" && pass "AUTO_DOCTOR soft timeout" || bad "AUTO_DOCTOR soft timeout"

# --- Soft-success 0.5.10 ---
/usr/bin/grep -q 'isSoftHealOK' "${ROOT}/macos/MyVPN/MyVPN/AutoDoctor.swift" && pass "AutoDoctor isSoftHealOK" || bad "AutoDoctor isSoftHealOK"
/usr/bin/grep -q 'soft=1' "${ROOT}/macos/MyVPN/MyVPN/AutoDoctorPipeline.swift" && pass "pipeline AUTO_HEAL soft" || bad "pipeline AUTO_HEAL soft"
/usr/bin/grep -q 'isSoftHealOK' "${ROOT}/macos/MyVPN/MyVPN/WakeRecover.swift" && pass "WakeRecover uses isSoftHealOK" || bad "WakeRecover uses isSoftHealOK"

# --- Observability 0.5.9 ---
/usr/bin/grep -q 'UI_CMD' "${ROOT}/macos/MyVPN/MyVPN/AppDelegate.swift" && pass "UI_CMD in AppDelegate" || bad "UI_CMD in AppDelegate"
/usr/bin/grep -q 'forbidden peer_uid=' "${ROOT}/macos/MyVPN/helper/myvpn_helperd.py" && pass "helper forbidden log" || bad "helper forbidden log"
/usr/bin/grep -q 'helper_proto' "${ROOT}/lib/doctor.zsh" && pass "doctor helper_proto" || bad "doctor helper_proto"
/usr/bin/grep -q 'checksumMismatch\|expectedSHA256\|sha256' "${ROOT}/macos/MyVPN/MyVPN/UpdateChecker.swift" && pass "UpdateChecker checksum" || bad "UpdateChecker checksum"
/usr/bin/grep -q 'myVPN.app.zip.sha256' "${ROOT}/macos/MyVPN/release.zsh" && pass "release sha256 asset" || bad "release sha256 asset"
/usr/bin/grep -q 'proto' "${ROOT}/lib/helper_client.py" && pass "helper_client proto" || bad "helper_client proto"

# --- Single-instance 0.5.8 ---
SI="${ROOT}/macos/MyVPN/MyVPN/SingleInstance.swift"
/usr/bin/grep -q 'claimOrYield' "${SI}" && pass "SingleInstance claimOrYield" || bad "SingleInstance claimOrYield"
/usr/bin/grep -q 'UI_LAUNCH' "${SI}" && pass "SingleInstance UI_LAUNCH" || bad "SingleInstance UI_LAUNCH"
/usr/bin/grep -q 'claimOrYield' "${ROOT}/macos/MyVPN/MyVPN/AppDelegate.swift" && pass "AppDelegate single-instance guard" || bad "AppDelegate single-instance guard"
/usr/bin/grep -q 'terminatePeers' "${ROOT}/macos/MyVPN/MyVPN/UpdateChecker.swift" && pass "UpdateChecker terminatePeers" || bad "UpdateChecker terminatePeers"
/usr/bin/grep -q 'UI_UPDATE' "${ROOT}/macos/MyVPN/MyVPN/UpdateChecker.swift" && pass "UpdateChecker UI_UPDATE" || bad "UpdateChecker UI_UPDATE"
/usr/bin/grep -q 'Does NOT open' "${ROOT}/macos/MyVPN/build-app.zsh" && pass "build-app no-open" || bad "build-app no-open"
/usr/bin/grep -q 'Does NOT open' "${ROOT}/macos/MyVPN/release.zsh" && pass "release no-open" || bad "release no-open"

# --- WakeRecover 0.5.6: always remount when channel live ---
WR="${ROOT}/macos/MyVPN/MyVPN/WakeRecover.swift"
/usr/bin/grep -q 'WAKE_NAS skip=no_channel' "${WR}" && pass "WakeRecover skip=no_channel" || bad "WakeRecover skip=no_channel"
/usr/bin/grep -q 'soft=1\|softOK' "${WR}" && pass "WakeRecover soft-success" || bad "WakeRecover soft-success"
/usr/bin/grep -q 'HealKind.restart' "${WR}" && pass "WakeRecover heal=restart-only" || bad "WakeRecover heal=restart-only"
/usr/bin/grep -q 'skip=desired_off' "${ROOT}/macos/MyVPN/MyVPN/DropLogger.swift" && pass "CONFIRM skip=desired_off" || bad "CONFIRM skip=desired_off"

/usr/bin/grep -q 'performWakeHeal\|SLEEP_WAKE_STALE' "${WR}" && pass "WakeRecover SLEEP_WAKE_STALE" || bad "WakeRecover SLEEP_WAKE_STALE"
heal_line="$(/usr/bin/grep -n 'performWakeHeal\|WAKE_HEAL primary' "${WR}" | /usr/bin/head -1 | /usr/bin/cut -d: -f1)"
nas_line="$(/usr/bin/grep -n 'WAKE_NAS mount-nas' "${WR}" | /usr/bin/head -1 | /usr/bin/cut -d: -f1)"
if [[ -n "$heal_line" && -n "$nas_line" && "$heal_line" -lt "$nas_line" ]]; then
  pass "WakeRecover heal-before-NAS order ($heal_line < $nas_line)"
else
  bad "WakeRecover heal-before-NAS order heal=$heal_line nas=$nas_line"
fi
# Must NOT gate mount on !snap.nas only
if /usr/bin/grep -q 'if wantNAS, !snap.nas' "${WR}"; then
  bad "WakeRecover still skips when nas=1"
else
  pass "WakeRecover does not skip on nas=1"
/usr/bin/grep -q 'remount_stale_ok' "${WR}" && pass "WakeRecover remount_stale_ok" || bad "WakeRecover remount_stale_ok"
fi

# --- HEAL_NAS logged (not silent try?) ---
/usr/bin/grep -q 'HEAL_NAS' "${ROOT}/macos/MyVPN/MyVPN/AutoDoctor.swift" && pass "HEAL_NAS log" || bad "HEAL_NAS log"

# --- helper accepts pin-endpoints ---
/usr/bin/grep -q 'pin-endpoints' "${ROOT}/macos/MyVPN/helper/myvpn_helperd.py" && pass "helper pin-endpoints" || bad "helper pin-endpoints"

# --- INTENTIONAL_OFF in doctor ---
/usr/bin/grep -q 'INTENTIONAL_OFF' "${ROOT}/lib/doctor.zsh" && pass "doctor INTENTIONAL_OFF" || bad "doctor INTENTIONAL_OFF"

# --- UI timeouts ---
AD="${ROOT}/macos/MyVPN/MyVPN/AppDelegate.swift"
/usr/bin/grep -q 'timeout: 25' "${AD}" && pass "doctor UI timeout 25" || bad "doctor UI timeout 25"
/usr/bin/grep -q 'timeout: 35' "${AD}" && pass "up/down UI timeout 35" || bad "up/down UI timeout 35"

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
