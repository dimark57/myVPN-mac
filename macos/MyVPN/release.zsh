#!/bin/zsh
# Build myVPN.app.zip (+ .sha256) and publish GitHub Release (dimark57/myVPN-mac).
# Does NOT install to ~/Applications — users update via Releases / in-app Update.
# Does NOT open stage / DerivedData myVPN.app (dual NSStatusItem — closed in 0.5.8).
# Usage: macos/MyVPN/release.zsh [version]
set -euo pipefail
ROOT="$(cd "${0:A:h}/../.." && pwd)"
APP_DIR="${ROOT}/macos/MyVPN"
VERSION="${1:-}"
PLIST="${APP_DIR}/MyVPN/Info.plist"

if [[ -z "${VERSION}" ]]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${PLIST}" 2>/dev/null || echo "0.0.0")"
fi

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
## myVPN ${VERSION} — cooldown vs DROP clarity

In-app: **Настройки → Update** (or auto).

### Fix
- Failed public-IP probe no longer clears cached IP → fewer false «нет интернета» DROPs (\`EGRESS_PROBE empty keep_cached\`)
- Cooldown skip logs: \`last_primary\` / \`last_kind\` / \`new=\`
- New DROP with **different** PRIMARY can bypass restart cooldown (\`HEAL_GATE cooldown_bypass=new_primary\`)
- \`AUTO_DOCTOR\` timeout + L0 green → \`ok=1 soft=1\` (no false ✕)
EOF
)" \
  --latest

print -r -- "OK ${TAG} assets myVPN.app.zip + myVPN.app.zip.sha256"
print -r -- "На этом Mac: Настройки → Update. Не копируй из stage / DerivedData."
