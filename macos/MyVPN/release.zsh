#!/bin/zsh
# Package myVPN.app.zip (+ .sha256) and create GitHub Release assets.
# Prefer macos/MyVPN/ship.zsh for atomic bump→commit→tag→push (cd recipe macos-gh-app).
#
# Usage:
#   release.zsh <version>           # bumps plist (legacy; prefer ship.zsh)
#   MYVPN_RELEASE_NO_BUMP=1 release.zsh <version>   # package only (ship already bumped)
#
# Does NOT install to ~/Applications. Does NOT open stage / DerivedData.
# Does NOT git tag / push — ship.zsh owns that (avoids wrong-tip retag).
set -euo pipefail
ROOT="$(cd "${0:A:h}/../.." && pwd)"
APP_DIR="${ROOT}/macos/MyVPN"
VERSION="${1:-}"
PLIST="${APP_DIR}/MyVPN/Info.plist"
REPO="${MYVPN_GH_REPO:-dimark57/myVPN-mac}"
NO_BUMP="${MYVPN_RELEASE_NO_BUMP:-0}"
export TMPDIR="${TMPDIR:-/tmp}"

if [[ -z "${VERSION}" ]]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${PLIST}" 2>/dev/null || echo "0.0.0")"
fi
[[ "$VERSION" == v* ]] && VERSION="${VERSION#v}"

if [[ "$NO_BUMP" != "1" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${PLIST}"
  BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${PLIST}" 2>/dev/null || echo 0)"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((BUILD + 1))" "${PLIST}" || true
fi

STAGE="${TMPDIR}/myvpn-release-$$"
mkdir -p "${STAGE}"
trap '/bin/rm -rf "${STAGE}"' EXIT

print -r -- "Building myVPN ${VERSION} → ${STAGE} (no ~/Applications, no open)…"
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
NOTES="${MYVPN_RELEASE_NOTES:-}"
if [[ -z "$NOTES" ]]; then
  NOTES="$(cat <<EOF
## myVPN ${VERSION}

In-app: **Настройки → Update** (or auto).
EOF
)"
fi

print -r -- "Publishing ${TAG} → GitHub…"
if gh release view "${TAG}" --repo "${REPO}" >/dev/null 2>&1; then
  gh release upload "${TAG}" "${ZIP}" "${SHA}" --repo "${REPO}" --clobber
  # Tag retarget / orphan draft → always publish + latest for in-app Update (/releases/latest).
  gh release edit "${TAG}" --repo "${REPO}" --draft=false --latest >/dev/null
else
  # Tag must already exist (ship.zsh pushed it). --latest for UpdateChecker.
  gh release create "${TAG}" "${ZIP}" "${SHA}" \
    --repo "${REPO}" \
    --title "myVPN ${VERSION}" \
    --notes "${NOTES}" \
    --latest
fi

# Drafts are invisible to api.github.com/.../releases/latest (in-app Update).
if gh release view "${TAG}" --repo "${REPO}" --json isDraft -q .isDraft 2>/dev/null | /usr/bin/grep -qi true; then
  print -r -- "ship/release: ${TAG} was draft — publishing"
  gh release edit "${TAG}" --repo "${REPO}" --draft=false --latest >/dev/null
fi

print -r -- "OK ${TAG} assets myVPN.app.zip + myVPN.app.zip.sha256"
print -r -- "На этом Mac: Настройки → Update. Не копируй из stage / DerivedData."
