#!/bin/zsh
# Build myVPN.app into a stage directory (for release.zsh → GitHub Releases).
# Does NOT install to ~/Applications — user delivery is only via GitHub Releases.
#
# Usage: build-app.zsh <stage-dir>
#   stage-dir/myVPN.app will be created.
set -euo pipefail
ROOT="${0:A:h}"
REPO="$(cd "${ROOT}/../.." && pwd)"
DERIVED="${HOME}/Library/Developer/Xcode/DerivedData/myVPN-agent"
LOCAL_RUNTIME="${HOME}/.local/share/myvpn"
STAGE="${1:-}"

if [[ -z "${STAGE}" ]]; then
  print -r -- "usage: build-app.zsh <stage-dir>" >&2
  print -r -- "Builds myVPN.app into stage-dir for packaging. Does not install." >&2
  print -r -- "Users install only from GitHub Releases (see README / release.zsh)." >&2
  exit 2
fi

DEST="${STAGE}/myVPN.app"
mkdir -p "${STAGE}"

cd "${ROOT}"
/usr/bin/python3 "${ROOT}/generate-xcodeproj.py"
xcodebuild -project MyVPN.xcodeproj -scheme myVPN -configuration Release \
  -derivedDataPath "${DERIVED}" -destination 'platform=macOS,arch=arm64' build

rm -rf "${DEST}"
cp -R "${DERIVED}/Build/Products/Release/myVPN.app" "${DEST}"

# Embed CLI runtime inside the app (local disk only — never depend on /Volumes/Nas at runtime).
RES="${DEST}/Contents/Resources"
mkdir -p "${RES}/runtime/bin" "${RES}/runtime/lib" "${RES}/runtime/share" "${RES}/helper"

if [[ -x "${REPO}/bin/myvpn" && -f "${REPO}/lib/nas.zsh" && -f "${REPO}/lib/process.zsh" ]]; then
  SRC="${REPO}"
elif [[ -d "${LOCAL_RUNTIME}/bin" ]]; then
  SRC="${LOCAL_RUNTIME}"
else
  print -r -- "no runtime source at ${REPO} or ${LOCAL_RUNTIME}" >&2
  exit 1
fi

/usr/bin/rsync -a --delete \
  "${SRC}/bin/" "${RES}/runtime/bin/"
/usr/bin/rsync -a --delete \
  "${SRC}/lib/" "${RES}/runtime/lib/"
if [[ -d "${SRC}/share" ]]; then
  /usr/bin/rsync -a --delete "${SRC}/share/" "${RES}/runtime/share/" || true
fi
/bin/chmod +x "${RES}/runtime/bin/myvpn" 2>/dev/null || true

/bin/cp -f "${ROOT}/helper/myvpn_helperd.py" "${RES}/helper/"
/bin/cp -f "${ROOT}/helper/install-helper.zsh" "${RES}/helper/"
/bin/chmod +x "${RES}/helper/install-helper.zsh" "${RES}/helper/myvpn_helperd.py"

codesign --force --deep --sign - "${DEST}" >/dev/null 2>&1 || true

print -r -- "built ${DEST}"
print -r -- "runtime embedded → Contents/Resources/runtime"
