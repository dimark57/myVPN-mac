#!/bin/zsh
# REMOVED as install path — myVPN.app is delivered only via GitHub Releases.
#
# Was: build + copy to ~/Applications (caused Release drift).
# Now: use macos/MyVPN/release.zsh → GitHub → in-app Update / download zip.
# Packaging build: macos/MyVPN/build-app.zsh <stage-dir> (called by release.zsh).
set -euo pipefail
print -r -- "install-app.zsh отключён." >&2
print -r -- "" >&2
print -r -- "Установка только из GitHub Releases:" >&2
print -r -- "  https://github.com/dimark57/myVPN-mac/releases/latest" >&2
print -r -- "  → myVPN.app.zip → ~/Applications → открыть" >&2
print -r -- "  или: Настройки → Update / автообновление" >&2
print -r -- "" >&2
print -r -- "Сборка релиза (не локальный install):" >&2
print -r -- "  macos/MyVPN/release.zsh [version]" >&2
exit 1
