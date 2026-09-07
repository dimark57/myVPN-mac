#!/bin/zsh
# Static regression: Login Item must wait for helper socket (no live down/up).
# Evidence from boot: app didFinishLaunching before helper "listening" → old code skipped auto-up.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

check() {
  local label="$1" file="$2" pattern="$3"
  if rg -q -- "$pattern" "$file"; then
    print -r -- "ok  $label"
  else
    print -r -- "FAIL $label — missing /$pattern/ in $file" >&2
    fail=1
  fi
}

HELPER="$ROOT/macos/MyVPN/MyVPN/MyVPNHelper.swift"
APP="$ROOT/macos/MyVPN/MyVPN/AppDelegate.swift"
PATCH="$ROOT/macos/MyVPN/patches/autoload-nas-ux/files/AppDelegate.swift"

check "waitUntilAvailable API" "$HELPER" 'func waitUntilAvailable'
check "auto-up does not require socket upfront" "$APP" 'Do not require helper socket yet'
check "auto-up calls waitUntilAvailable" "$APP" 'waitUntilAvailable\(timeout:'
check "auto-up logs helper wait" "$APP" 'auto-up: start helperReady='
check "patch AppDelegate mirrors wait" "$PATCH" 'waitUntilAvailable\(timeout:'

# Pure logic: delayed "socket ready" must succeed within timeout (no VPN I/O).
swift -e '
import Foundation
func waitUntil(available: () -> Bool, timeout: TimeInterval, poll: TimeInterval) -> Bool {
    if available() { return true }
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        Thread.sleep(forTimeInterval: poll)
        if available() { return true }
    }
    return available()
}
var ready = false
DispatchQueue.global().asyncAfter(deadline: .now() + 0.35) { ready = true }
precondition(waitUntil(available: { ready }, timeout: 2, poll: 0.05), "late ready must succeed")
precondition(!waitUntil(available: { false }, timeout: 0.2, poll: 0.05), "never ready must fail")
print("ok  waitUntil delay simulation")
'

print -r -- "ok  suite is static-only (no VPN I/O)"

exit $fail
