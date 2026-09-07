#!/bin/zsh
# Build myVPN.app, embed local runtime + helper into Resources, install to ~/Applications.
set -euo pipefail
ROOT="${0:A:h}"
REPO="$(cd "${ROOT}/../.." && pwd)"
DERIVED="${HOME}/Library/Developer/Xcode/DerivedData/myVPN-agent"
DEST="${HOME}/Applications/myVPN.app"
LOCAL_RUNTIME="${HOME}/.local/share/myvpn"

cd "${ROOT}"
/usr/bin/python3 "${ROOT}/generate-xcodeproj.py"
xcodebuild -project MyVPN.xcodeproj -scheme myVPN -configuration Release \
  -derivedDataPath "${DERIVED}" -destination 'platform=macOS,arch=arm64' build

rm -rf "${DEST}"
mkdir -p "${HOME}/Applications"
cp -R "${DERIVED}/Build/Products/Release/myVPN.app" "${DEST}"

# Embed CLI runtime inside the app (local disk only — never depend on /Volumes/Nas at runtime).
RES="${DEST}/Contents/Resources"
mkdir -p "${RES}/runtime/bin" "${RES}/runtime/lib" "${RES}/runtime/share" "${RES}/helper"

if [[ -d "${LOCAL_RUNTIME}/bin" ]]; then
  SRC="${LOCAL_RUNTIME}"
elif [[ -d "${REPO}/bin" ]]; then
  SRC="${REPO}"
else
  print -r -- "no runtime source at ${LOCAL_RUNTIME} or ${REPO}" >&2
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

# Keep ~/.local/bin/myvpn for Alfred, pointing at local share (sync from embedded).
mkdir -p "${LOCAL_RUNTIME}"
/usr/bin/rsync -a --delete \
  "${RES}/runtime/bin" "${RES}/runtime/lib" "${RES}/runtime/share" \
  "${LOCAL_RUNTIME}/" 2>/dev/null || {
  mkdir -p "${LOCAL_RUNTIME}/bin" "${LOCAL_RUNTIME}/lib"
  /bin/cp -R "${RES}/runtime/bin/." "${LOCAL_RUNTIME}/bin/"
  /bin/cp -R "${RES}/runtime/lib/." "${LOCAL_RUNTIME}/lib/"
}
/bin/chmod +x "${LOCAL_RUNTIME}/bin/myvpn"
mkdir -p "${HOME}/.local/bin"
/bin/ln -sfn "${LOCAL_RUNTIME}/bin/myvpn" "${HOME}/.local/bin/myvpn"

# Remove legacy zsh LaunchAgent — login item is the app.
launchctl bootout "gui/$(id -u)/local.myvpn.mac.login" >/dev/null 2>&1 || true
rm -f "${HOME}/Library/LaunchAgents/local.myvpn.mac.login.plist"

print -r -- "installed ${DEST}"
print -r -- "runtime embedded → Contents/Resources/runtime"
print -r -- "Next: open app → Настройки → Установить помощник (один пароль)"
print -r -- "Then: Автоподнятие после перезагрузки"
