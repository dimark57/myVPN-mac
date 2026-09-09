#!/bin/zsh
# Build myVPN.app.zip (+ .sha256) and publish GitHub Release (dimark57/myVPN-mac).
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
SHA="${STAGE}/myVPN.app.zip.sha256"
(
  cd "${STAGE}"
  /usr/bin/shasum -a 256 "myVPN.app.zip" | /usr/bin/awk '{print $1"  myVPN.app.zip"}' > "myVPN.app.zip.sha256"
)
print -r -- "sha256 $(/usr/bin/awk '{print $1}' "${SHA}")"

TAG="v${VERSION}"
print -r -- "Publishing ${TAG} → GitHub…"
gh release create "${TAG}" "${ZIP}" "${SHA}" \
  --repo dimark57/myVPN-mac \
  --title "myVPN ${VERSION}" \
  --notes "$(cat <<EOF
## myVPN ${VERSION} — auto-heal soft-success

In-app: **Настройки → Update → Проверить обновление**.

### Fix
- Pipeline \`AUTO_HEAL\`: helper timeout / verify lag while L0 green → \`ok=1 soft=1\` (no false ✕ / Safe Mode tick)
- Shared \`AutoDoctor.isSoftHealOK\` (wake path uses the same)

### Note
Checksum asset \`myVPN.app.zip.sha256\` included (0.5.9+).
EOF
)" \
  --latest

print -r -- "OK ${TAG} assets myVPN.app.zip + myVPN.app.zip.sha256"
print -r -- "На этом Mac: Настройки → Update. Не копируй из stage / DerivedData."
