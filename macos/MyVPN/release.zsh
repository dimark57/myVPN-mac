#!/bin/zsh
# Build myVPN.app.zip and publish GitHub Release (dimark57/myVPN-mac).
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

print -r -- "Building myVPN ${VERSION}…"
"${APP_DIR}/install-app.zsh"

DEST="${HOME}/Applications/myVPN.app"
STAGE="${TMPDIR:-/tmp}/myvpn-release-$$"
mkdir -p "${STAGE}"
/bin/cp -R "${DEST}" "${STAGE}/myVPN.app"
ZIP="${STAGE}/myVPN.app.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "${STAGE}/myVPN.app" "${ZIP}"

TAG="v${VERSION}"
print -r -- "Publishing ${TAG} → GitHub…"
gh release create "${TAG}" "${ZIP}" \
  --repo dimark57/myVPN-mac \
  --title "myVPN ${VERSION}" \
  --notes "Menu-bar split-tunnel client. Download myVPN.app.zip → ~/Applications → open. First launch: install helper, import WireGuard profiles." \
  --latest

print -r -- "OK ${TAG} asset myVPN.app.zip"
/bin/rm -rf "${STAGE}"
