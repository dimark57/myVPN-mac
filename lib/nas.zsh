# SMB NAS mount via Keychain (password never logged).
# After VPN flaps macOS smbfs often leaves a half-open mount; remount = unmount → mount.

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

myvpn_nas_in_mount_table() {
  /sbin/mount | /usr/bin/grep -q " on ${MYVPN_NAS_MOUNT} "
}

# Prefer mount table (no SMB hang). Path check is fallback only.
myvpn_nas_is_mounted() {
  myvpn_nas_in_mount_table && return 0
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

myvpn_nas_clear_stale_mountpoint() {
  # Empty /Volumes/Nas left behind breaks both Finder and mount_smbfs.
  if [[ -d "${MYVPN_NAS_MOUNT}" ]] && ! myvpn_nas_in_mount_table; then
    /bin/rmdir "${MYVPN_NAS_MOUNT}" >/dev/null 2>&1 || true
  fi
}

# macOS may leave /Volumes/Nas-1 when /Volumes/Nas cannot be created — blocks remount.
myvpn_nas_prune_empty_alt_volumes() {
  local base="${MYVPN_NAS_MOUNT##*/}" alt
  [[ -n "$base" ]] || return 0
  setopt local_options null_glob
  for alt in /Volumes/${base}-*; do
    [[ -e "$alt" ]] || continue
    /sbin/mount | /usr/bin/grep -q " on ${alt} " && continue
    /bin/rmdir "$alt" 2>/dev/null && print -r -- "nas pruned empty ${alt}"
  done
}

# Root helper creates /Volumes/* when user mkdir is denied (macOS 15+).
myvpn_nas_helper_prepare_mountpoint() {
  [[ "$(/usr/bin/id -u)" == "0" ]] && return 1
  myvpn_helper_available || return 1
  myvpn_via_helper nas-mkdir >/dev/null 2>&1
}

myvpn_nas_ensure_mountpoint() {
  [[ -d "${MYVPN_NAS_MOUNT}" ]] && return 0
  myvpn_nas_prune_empty_alt_volumes || true
  /bin/mkdir -p "${MYVPN_NAS_MOUNT}" 2>/dev/null && return 0
  myvpn_nas_helper_prepare_mountpoint || return 1
  [[ -d "${MYVPN_NAS_MOUNT}" ]]
}

# osascript mount volume can hang forever on stale SMB — cap wall time for auto-heal.
myvpn_nas_timed_osascript_mount() {
  local url="$1" secs="${2:-20}"
  /usr/bin/python3 -c '
import subprocess, sys
url, secs = sys.argv[1], int(sys.argv[2])
try:
    p = subprocess.Popen(
        ["/usr/bin/osascript", "-e", f"mount volume \"{url}\""],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        p.wait(timeout=secs)
        sys.exit(0 if p.returncode == 0 else 1)
    except subprocess.TimeoutExpired:
        p.kill()
        try:
            p.wait(timeout=5)
        except subprocess.TimeoutExpired:
            pass
        sys.exit(124)
except Exception:
    sys.exit(1)
' "${url}" "${secs}"
}

myvpn_nas_try_smbfs_mount() {
  local pw_enc="$1" pw_redact="$2" err
  myvpn_nas_ensure_mountpoint || return 1
  err="$(/sbin/mount_smbfs "//${MYVPN_NAS_USER}:${pw_enc}@${MYVPN_NAS_HOST}/${MYVPN_NAS_SHARE}" "${MYVPN_NAS_MOUNT}" 2>&1)" || {
    err="${err//${pw_redact}/***}"
    err="${err//${pw_enc}/***}"
    print -r -- "mount_smbfs failed${err:+: ${err}}" >&2
    return 1
  }
  myvpn_nas_in_mount_table || myvpn_nas_is_mounted
}

# Soft unmount first (Finder-friendly). Returns 0 if mount gone.
myvpn_nas_graceful_unmount() {
  myvpn_nas_in_mount_table || return 0
  /usr/sbin/diskutil unmount "${MYVPN_NAS_MOUNT}" >/dev/null 2>&1 \
    || /sbin/umount "${MYVPN_NAS_MOUNT}" >/dev/null 2>&1 \
    || return 1
  myvpn_nas_in_mount_table && return 1
  /bin/rmdir "${MYVPN_NAS_MOUNT}" >/dev/null 2>&1 || true
  return 0
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

# Unmount then (caller mounts). --safe: never force if volume busy.
# Without --safe (UI «Перемонтировать»): soft → then force.
myvpn_nas_unmount_for_remount() {
  local safe="${1:-0}"
  myvpn_nas_in_mount_table || [[ -d "${MYVPN_NAS_MOUNT}" ]] || return 0
  # doc-13 / 0.5.20: check busy BEFORE any unmount — graceful umount can still yank Cursor.
  if (( safe )) && myvpn_nas_in_mount_table && myvpn_nas_volume_busy; then
    print -r -- "NAS_BUSY: ${MYVPN_NAS_MOUNT} has open files — skip unmount (doc-13)" >&2
    return 2
  fi
  print -r -- "nas unmount ${MYVPN_NAS_MOUNT}"
  if myvpn_nas_graceful_unmount; then
    return 0
  fi
  if (( safe )) && myvpn_nas_volume_busy; then
    print -r -- "NAS_BUSY: ${MYVPN_NAS_MOUNT} has open files — skip force unmount (doc-10)" >&2
    return 2
  fi
  print -r -- "nas force-unmount ${MYVPN_NAS_MOUNT}"
  myvpn_nas_force_unmount
  return 0
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
# Timed: lsof on busy SMB can hang.
myvpn_nas_volume_busy() {
  myvpn_nas_in_mount_table || return 1
  /usr/bin/python3 -c '
import subprocess, sys
mount = sys.argv[1]
try:
    r = subprocess.run(["/usr/sbin/lsof", mount], capture_output=True, timeout=3)
except subprocess.TimeoutExpired:
    sys.exit(0)  # treat hang as busy
except Exception:
    sys.exit(1)
lines = (r.stdout or b"").decode().strip().splitlines()
sys.exit(0 if len(lines) > 1 else 1)
' "${MYVPN_NAS_MOUNT}"
}

myvpn_cmd_mount_nas() {
  local pw pw_enc tries=0 err force=0 safe=0 remount=0
  local arg
  for arg in "$@"; do
    case "$arg" in
      --force|-f) force=1 ;;
      --safe|-s) safe=1 ;;
      --remount|-r) remount=1 ;;
    esac
  done

  # UI «Перемонтировать»: always unmount → mount (not no-op / not BUSY abort).
  if (( remount )); then
    print -r -- "nas remount: unmount → mount at ${MYVPN_NAS_MOUNT}"
    myvpn_nas_unmount_for_remount 0 || return $?
  elif (( force == 0 )) && myvpn_nas_in_mount_table; then
    if myvpn_nas_is_alive; then
      print -r -- "nas already mounted at ${MYVPN_NAS_MOUNT}"
      return 0
    fi
    # Stale / half-open — cycle mount (auto path may pass --safe).
    print -r -- "nas mount stale at ${MYVPN_NAS_MOUNT} — remounting"
    myvpn_nas_unmount_for_remount "${safe}" || return $?
  elif (( force )); then
    myvpn_nas_unmount_for_remount "${safe}" || return $?
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
  myvpn_nas_ensure_mountpoint || true

  local smb_url="smb://${MYVPN_NAS_USER}:${pw_enc}@${MYVPN_NAS_HOST}/${MYVPN_NAS_SHARE}"

  # Prefer smbfs when mountpoint exists — no Finder hang (auto-heal / wake).
  if myvpn_nas_try_smbfs_mount "${pw_enc}" "${pw}"; then
    print -r -- "nas mounted ${MYVPN_NAS_MOUNT} (smbfs)"
    return 0
  fi

  # osascript uses Keychain password (Finder does not see local.myvpn.mac.nas).
  local osa_rc=0
  myvpn_nas_timed_osascript_mount "${smb_url}" 20 || osa_rc=$?
  if (( osa_rc == 124 )); then
    print -r -- "nas osascript mount timeout (20s) — retry smbfs" >&2
  elif (( osa_rc == 0 )); then
    tries=0
    while (( tries < 20 )); do
      if myvpn_nas_in_mount_table && myvpn_nas_is_alive; then
        print -r -- "nas mounted ${MYVPN_NAS_MOUNT}"
        return 0
      fi
      if myvpn_nas_in_mount_table && (( tries >= 3 )); then
        print -r -- "nas mounted ${MYVPN_NAS_MOUNT} (table)"
        return 0
      fi
      /bin/sleep 1
      (( tries++ ))
    done
  fi

  myvpn_nas_clear_stale_mountpoint
  if myvpn_nas_try_smbfs_mount "${pw_enc}" "${pw}"; then
    print -r -- "nas mounted ${MYVPN_NAS_MOUNT} (smbfs)"
    return 0
  fi
  print -r -- "mount-nas failed (check Keychain ${MYVPN_NAS_KEYCHAIN_SERVICE}/${MYVPN_NAS_USER}, NAS SMB)" >&2
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
  if myvpn_nas_is_mounted && myvpn_nas_is_alive; then
    return 0
  fi
  local extra=()
  if ! myvpn_nas_is_mounted; then
    extra=(--force)
  fi
  # --safe: BUSY → skip force unmount; --force when nas=0 clears stale + smbfs path.
  myvpn_cmd_mount_nas "${extra[@]}" --safe || true
}
