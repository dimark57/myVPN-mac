# SMB NAS mount via Keychain (password never logged).
# After VPN flaps macOS smbfs often leaves a half-open mount; force remount on up.

myvpn_keychain_password() {
  /usr/bin/security find-generic-password -s "${MYVPN_NAS_KEYCHAIN_SERVICE}" -a "${MYVPN_NAS_USER}" -w 2>/dev/null
}

myvpn_keychain_ensure() {
  if myvpn_keychain_password >/dev/null 2>&1; then
    return 0
  fi
  if [[ -n "${MYVPN_NAS_PASSWORD:-}" ]]; then
    /usr/bin/security delete-generic-password -s "${MYVPN_NAS_KEYCHAIN_SERVICE}" -a "${MYVPN_NAS_USER}" >/dev/null 2>&1 || true
    /usr/bin/security add-generic-password \
      -s "${MYVPN_NAS_KEYCHAIN_SERVICE}" \
      -a "${MYVPN_NAS_USER}" \
      -w "${MYVPN_NAS_PASSWORD}" \
      -T /usr/bin/security -T /bin/zsh -T /usr/bin/osascript >/dev/null
    return $?
  fi
  print -r -- "Keychain empty for ${MYVPN_NAS_KEYCHAIN_SERVICE}/${MYVPN_NAS_USER}. Run: MYVPN_NAS_PASSWORD='…' myvpn install-autostart" >&2
  return 1
}

myvpn_nas_urlencode() {
  /usr/bin/python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

myvpn_nas_is_mounted() {
  [[ -d "${MYVPN_NAS_MOUNT}/Project" || -d "${MYVPN_NAS_MOUNT}/data" ]]
}

# Timed probe — avoids Finder/CLI hang on stale smbfs (ENOTCONN).
# 0 = alive, 1 = dead/missing, 2 = timeout (treat as stale).
# 5s: 2s false-positive when Cursor/Spotlight sit on /Volumes/Nas.
myvpn_nas_is_alive() {
  /usr/bin/python3 -c '
import os, signal, sys
path = sys.argv[1]

def boom(_s, _f):
    raise TimeoutError()

signal.signal(signal.SIGALRM, boom)
signal.alarm(5)
try:
    for name in ("Project", "data"):
        p = os.path.join(path, name)
        if os.path.isdir(p):
            os.listdir(p)
            sys.exit(0)
    sys.exit(1)
except TimeoutError:
    sys.exit(2)
except OSError:
    sys.exit(1)
' "${MYVPN_NAS_MOUNT}"
}

myvpn_nas_in_mount_table() {
  /sbin/mount | /usr/bin/grep -q " on ${MYVPN_NAS_MOUNT} "
}

myvpn_nas_clear_stale_mountpoint() {
  # Empty /Volumes/Nas left behind breaks both Finder and mount_smbfs.
  if [[ -d "${MYVPN_NAS_MOUNT}" ]] && ! myvpn_nas_is_mounted; then
    if myvpn_nas_in_mount_table; then
      /sbin/umount "${MYVPN_NAS_MOUNT}" >/dev/null 2>&1 || true
    fi
    /bin/rmdir "${MYVPN_NAS_MOUNT}" >/dev/null 2>&1 || true
  fi
}

# Force-drop half-open SMB (VPN reconnect). Prefer diskutil for Finder mounts.
myvpn_nas_force_unmount() {
  if myvpn_nas_in_mount_table || [[ -d "${MYVPN_NAS_MOUNT}" ]]; then
    /usr/sbin/diskutil unmount force "${MYVPN_NAS_MOUNT}" >/dev/null 2>&1 \
      || /sbin/umount -f "${MYVPN_NAS_MOUNT}" >/dev/null 2>&1 \
      || true
  fi
  /bin/rmdir "${MYVPN_NAS_MOUNT}" >/dev/null 2>&1 || true
}

myvpn_nas_wait_host() {
  local tries=0
  if /sbin/ping -c 1 -W 1500 "${MYVPN_NAS_HOST}" >/dev/null 2>&1; then
    return 0
  fi
  while (( tries < 15 )); do
    /bin/sleep 2
    (( tries++ ))
    /sbin/ping -c 1 -W 1500 "${MYVPN_NAS_HOST}" >/dev/null 2>&1 && return 0
  done
  return 1
}

# True if any process holds open files on the NAS mount (Cursor/IDE deadlock risk).
myvpn_nas_volume_busy() {
  [[ -d "${MYVPN_NAS_MOUNT}" ]] || return 1
  /usr/sbin/lsof "${MYVPN_NAS_MOUNT}" 2>/dev/null | /usr/bin/awk 'NR>1{found=1; exit} END{exit !found}'
}

myvpn_cmd_mount_nas() {
  local pw pw_enc tries=0 err force=0 safe=0
  local arg
  for arg in "$@"; do
    case "$arg" in
      --force|-f) force=1 ;;
      --safe|-s) safe=1 ;;
    esac
  done

  if (( force == 0 )) && myvpn_nas_is_mounted; then
    if myvpn_nas_is_alive; then
      print -r -- "nas already mounted at ${MYVPN_NAS_MOUNT}"
      return 0
    fi
    print -r -- "nas mount stale at ${MYVPN_NAS_MOUNT} — remounting"
    force=1
  fi

  if (( force )) && (( safe )) && myvpn_nas_is_mounted && myvpn_nas_volume_busy; then
    print -r -- "NAS_BUSY: ${MYVPN_NAS_MOUNT} has open files — skip force unmount (doc-10)" >&2
    return 2
  fi

  if (( force )); then
    myvpn_nas_force_unmount
  fi

  if ! myvpn_nas_wait_host; then
    print -r -- "NAS ${MYVPN_NAS_HOST} unreachable (home down?)" >&2
    return 1
  fi
  myvpn_keychain_ensure || return 1
  pw="$(myvpn_keychain_password)" || return 1
  if [[ -z "$pw" ]]; then
    print -r -- "Keychain password empty for ${MYVPN_NAS_KEYCHAIN_SERVICE}" >&2
    return 1
  fi
  pw_enc="$(myvpn_nas_urlencode "$pw")"
  myvpn_nas_clear_stale_mountpoint

  # osascript uses our Keychain password (Finder open does not see local.myvpn.mac.nas).
  if /usr/bin/osascript -e "mount volume \"smb://${MYVPN_NAS_USER}:${pw_enc}@${MYVPN_NAS_HOST}/${MYVPN_NAS_SHARE}\"" >/dev/null 2>&1; then
    tries=0
    while (( tries < 20 )); do
      if myvpn_nas_is_mounted && myvpn_nas_is_alive; then
        print -r -- "nas mounted ${MYVPN_NAS_MOUNT}"
        return 0
      fi
      /bin/sleep 1
      (( tries++ ))
    done
  fi

  myvpn_nas_clear_stale_mountpoint
  /bin/mkdir -p "${MYVPN_NAS_MOUNT}" 2>/dev/null || true
  err="$(/sbin/mount_smbfs "//${MYVPN_NAS_USER}:${pw_enc}@${MYVPN_NAS_HOST}/${MYVPN_NAS_SHARE}" "${MYVPN_NAS_MOUNT}" 2>&1)" || {
    err="${err//${pw}/***}"
    err="${err//${pw_enc}/***}"
    print -r -- "mount-nas failed${err:+: ${err}} (check Keychain ${MYVPN_NAS_KEYCHAIN_SERVICE}/${MYVPN_NAS_USER})" >&2
    return 1
  }
  if myvpn_nas_is_mounted; then
    print -r -- "nas mounted ${MYVPN_NAS_MOUNT}"
    return 0
  fi
  print -r -- "mount-nas failed: mounted but ${MYVPN_NAS_MOUNT}/Project missing" >&2
  return 1
}

myvpn_auto_nas_flag() {
  print -r -- "${MYVPN_HOME}/auto-mount-nas"
}

myvpn_auto_nas_enabled() {
  [[ -f "$(myvpn_auto_nas_flag)" ]]
}

# Trigger after VPN came up (not when already running). Does not unmount on down.
myvpn_after_up_remount_nas() {
  if ! myvpn_auto_nas_enabled; then
    return 0
  fi
  print -r -- "auto-nas: remount after vpn up"
  # --safe only (no blind --force): alive mount = instant no-op; stale remounts unless BUSY.
  myvpn_cmd_mount_nas --safe || true
}
