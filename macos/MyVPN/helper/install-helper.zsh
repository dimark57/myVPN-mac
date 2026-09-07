#!/bin/zsh
# Install/uninstall privileged helper. Must run as root.
set -euo pipefail

# Root under osascript often inherits a cwd on /Volumes/Nas → "Operation not permitted".
cd / || true

ACTION="${1:-install}"
APP_PATH="${2:-}"
OWNER="${3:-}"
OWNER_HOME="${4:-}"

LABEL="local.myvpn.mac.helper"
SUPPORT="/Library/Application Support/myVPN"
PLIST_DST="/Library/LaunchDaemons/${LABEL}.plist"
SOCK="/var/run/myvpn-helper.sock"

if [[ "$(/usr/bin/id -u)" != "0" ]]; then
  print -r -- "install-helper must run as root" >&2
  exit 1
fi

unload_daemon() {
  /bin/launchctl bootout "system/${LABEL}" >/dev/null 2>&1 || true
  /bin/launchctl unload "${PLIST_DST}" >/dev/null 2>&1 || true
}

if [[ "${ACTION}" == "uninstall" ]]; then
  unload_daemon
  /bin/rm -f "${PLIST_DST}" "${SOCK}"
  /bin/rm -rf "${SUPPORT}"
  print -r -- "helper uninstalled"
  exit 0
fi

if [[ -z "${APP_PATH}" || -z "${OWNER}" || -z "${OWNER_HOME}" ]]; then
  print -r -- "usage: install-helper.zsh install /path/myVPN.app user /Users/user" >&2
  exit 1
fi

RUNTIME="${APP_PATH}/Contents/Resources/runtime"
HELPER_SRC="${APP_PATH}/Contents/Resources/helper/myvpn_helperd.py"
if [[ ! -d "${RUNTIME}/bin" || ! -f "${HELPER_SRC}" ]]; then
  print -r -- "app missing Resources/runtime or helper — reinstall myVPN.app" >&2
  exit 1
fi

/bin/mkdir -p "${SUPPORT}"
/bin/cp -f "${HELPER_SRC}" "${SUPPORT}/myvpn_helperd.py"
/bin/chmod 755 "${SUPPORT}/myvpn_helperd.py"

/bin/cat > "${PLIST_DST}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/python3</string>
    <string>${SUPPORT}/myvpn_helperd.py</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key>
    <string>${OWNER_HOME}</string>
    <key>MYVPN_OWNER</key>
    <string>${OWNER}</string>
    <key>MYVPN_ROOT</key>
    <string>${RUNTIME}</string>
    <key>MYVPN_HELPER_SOCK</key>
    <string>${SOCK}</string>
    <key>MYVPN_HELPER_LOG</key>
    <string>/var/log/myvpn-helper.log</string>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>StandardOutPath</key>
  <string>/var/log/myvpn-helper.out.log</string>
  <key>StandardErrorPath</key>
  <string>/var/log/myvpn-helper.err.log</string>
</dict>
</plist>
EOF
/bin/chmod 644 "${PLIST_DST}"

unload_daemon
/bin/launchctl bootstrap system "${PLIST_DST}" 2>/dev/null || /bin/launchctl load -w "${PLIST_DST}"
/bin/sleep 1
if [[ -S "${SOCK}" ]]; then
  print -r -- "helper installed (socket ${SOCK})"
else
  print -r -- "helper launched but socket not ready — check /var/log/myvpn-helper.err.log" >&2
  exit 1
fi
