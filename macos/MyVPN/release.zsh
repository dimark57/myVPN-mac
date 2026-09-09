#!/bin/zsh
# Build myVPN.app.zip and publish GitHub Release (dimark57/myVPN-mac).
# Does NOT install to ~/Applications — users update via Releases / in-app Update.
# Does NOT open stage / DerivedData myVPN.app (dual NSStatusItem — closed in 0.5.8).
# Usage: macos/MyVPN/release.zsh [version]
# Example: macos/MyVPN/release.zsh 0.3.0
set -euo pipefail
ROOT="$(cd "${0:A:h}/../.." && pwd)"
APP_DIR="${ROOT}/macos/MyVPN"
VERSION="${1:-}"
PLIST="${APP_DIR}/MyVPN/Info.plist"

if [[ -z "${VERSION}" ]]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${PLIST}" 2>/dev/null || echo "0.0.0")"
fi

# Bump short version if passed
if [[ -n "${1:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${PLIST}"
  BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${PLIST}" 2>/dev/null || echo 0)"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((BUILD + 1))" "${PLIST}" || true
fi

STAGE="${TMPDIR:-/tmp}/myvpn-release-$$"
mkdir -p "${STAGE}"
trap '/bin/rm -rf "${STAGE}"' EXIT

print -r -- "Building myVPN ${VERSION} → stage (no ~/Applications install, no open)…"
"${APP_DIR}/build-app.zsh" "${STAGE}"

ZIP="${STAGE}/myVPN.app.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "${STAGE}/myVPN.app" "${ZIP}"

TAG="v${VERSION}"
print -r -- "Publishing ${TAG} → GitHub…"
gh release create "${TAG}" "${ZIP}" \
  --repo dimark57/myVPN-mac \
  --title "myVPN ${VERSION}" \
  --notes "$(cat <<EOF
## myVPN ${VERSION} — single-instance UI

In-app: **Настройки → Update → Проверить обновление**.

### Fix
- One menu-bar process for \`local.myvpn.mac\` (\`SingleInstance\`)
- Preferred path \`~/Applications/myVPN.app\` beats DerivedData/stage
- Update: terminate peer UIs before relaunch; VPN/helper untouched
- \`UI_LAUNCH\` / \`UI_UPDATE\` in \`drops.log\`

### Do not
- Open \`DerivedData/.../Release/myVPN.app\` while the menu bar app is running
EOF
)" \
  --latest

print -r -- "OK ${TAG} asset myVPN.app.zip"
print -r -- "На этом Mac: Настройки → Update (или дождись автообновления). Не копируй из stage / DerivedData."
