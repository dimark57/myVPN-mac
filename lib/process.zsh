# Process lifecycle for sing-box.

myvpn_helper_sock() {
  print -r -- "${MYVPN_HELPER_SOCK:-/var/run/myvpn-helper.sock}"
}

myvpn_helper_available() {
  [[ -S "$(myvpn_helper_sock)" ]]
}

# Prefer privileged helper when not already root (avoids admin password dialog).
myvpn_via_helper() {
  /usr/bin/python3 "${MYVPN_LIB}/helper_client.py" "$1"
}

myvpn_is_running() {
  local pid
  [[ -f "${MYVPN_PID_FILE}" ]] || return 1
  pid="$(/bin/cat "${MYVPN_PID_FILE}" 2>/dev/null || true)"
  [[ -n "$pid" ]] || return 1
  if /bin/kill -0 "$pid" 2>/dev/null; then
    return 0
  fi
  /bin/ps -p "$pid" -o pid= >/dev/null 2>&1
}

myvpn_stop_app_tunnels() {
  local line name
  while IFS= read -r line; do
    [[ "$line" == *com.wireguard.macos* ]] || continue
    [[ "$line" == *"(Connected)"* ]] || continue
    name="${line#*\"}"
    name="${name%%\"*}"
    [[ -n "$name" ]] || continue
    /usr/sbin/scutil --nc stop "$name" >/dev/null 2>&1 || true
  done < <(/usr/sbin/scutil --nc list 2>/dev/null)
}

# Point physical NIC DNS at TUN so digials → CoreDNS via hijack (not LAN DHCP / DoH → 94… → Hub 403).
# Does NOT copy DNS= from WG conf. networksetup can hang on stale USB services — always timed.

myvpn_netsetup() {
  # argv after script: networksetup args…
  /usr/bin/python3 -c '
import subprocess, sys
try:
    subprocess.run(["/usr/sbin/networksetup", *sys.argv[1:]], timeout=2, check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
except subprocess.TimeoutExpired:
    pass
except Exception:
    pass
' "$@"
}

myvpn_dns_flush() {
  /usr/bin/python3 -c '
import subprocess
for args in (
    ["/usr/bin/dscacheutil", "-flushcache"],
    ["/usr/bin/killall", "-HUP", "mDNSResponder"],
):
    try:
        subprocess.run(args, timeout=2, check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass
'
}

myvpn_dns_apply_tun() {
  local s
  local -a services
  services=("${(@s:|:)MYVPN_DNS_SERVICES}")
  for s in "${services[@]}"; do
    [[ -n "$s" ]] || continue
    myvpn_netsetup -setdnsservers "$s" "${MYVPN_TUN_DNS}"
  done
  if [[ "$(/usr/bin/id -u)" == "0" ]]; then
    myvpn_dns_flush
  else
    myvpn_run_admin '/usr/bin/python3 -c "import subprocess
for a in ([\"/usr/bin/dscacheutil\",\"-flushcache\"],[\"/usr/bin/killall\",\"-HUP\",\"mDNSResponder\"]):
 subprocess.run(a,timeout=2,check=False,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)"' >/dev/null 2>&1 || true
  fi
}

myvpn_dns_clear() {
  local s
  local -a services
  services=("${(@s:|:)MYVPN_DNS_SERVICES}")
  for s in "${services[@]}"; do
    [[ -n "$s" ]] || continue
    myvpn_netsetup -setdnsservers "$s" Empty
  done
  if [[ "$(/usr/bin/id -u)" == "0" ]]; then
    myvpn_dns_flush
  else
    myvpn_run_admin '/usr/bin/python3 -c "import subprocess
for a in ([\"/usr/bin/dscacheutil\",\"-flushcache\"],[\"/usr/bin/killall\",\"-HUP\",\"mDNSResponder\"]):
 subprocess.run(a,timeout=2,check=False,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)"' >/dev/null 2>&1 || true
  fi
}

myvpn_ensure_dirs() {
  /bin/mkdir -p "${MYVPN_HOME}" "${MYVPN_RULES_DIR}"
}

myvpn_render() {
  /usr/bin/python3 "${MYVPN_LIB}/render_config.py" \
    --macbook "${MYVPN_MACBOOK_CONF}" \
    --home "${MYVPN_HOME_CONF}" \
    --geosite "${MYVPN_GEOSITE_SRS}" \
    --geoip "${MYVPN_GEOIP_SRS}" \
    -o "${MYVPN_CONFIG_JSON}"
}

# Skip render/check when inputs are older than existing JSON (hot up path).
# Also invalidate when render_config.py itself changed (DNS/route logic).
myvpn_config_fresh() {
  local out="${MYVPN_CONFIG_JSON}"
  [[ -f "${out}" ]] || return 1
  [[ "${out}" -nt "${MYVPN_MACBOOK_CONF}" ]] || return 1
  [[ "${out}" -nt "${MYVPN_HOME_CONF}" ]] || return 1
  [[ "${out}" -nt "${MYVPN_GEOSITE_SRS}" ]] || return 1
  [[ "${out}" -nt "${MYVPN_GEOIP_SRS}" ]] || return 1
  [[ "${out}" -nt "${MYVPN_LIB}/render_config.py" ]] || return 1
  return 0
}

myvpn_wait_running() {
  local i
  for (( i=1; i<=20; i++ )); do
    myvpn_is_running && return 0
    /bin/sleep 0.05
  done
  return 1
}

myvpn_cmd_up() {
  myvpn_ensure_dirs
  if myvpn_is_running; then
    print -r -- "already up (pid $(/bin/cat "${MYVPN_PID_FILE}"))"
    return 0
  fi
  if [[ ! -x "${MYVPN_SING_BOX}" ]] && ! command -v "${MYVPN_SING_BOX}" >/dev/null 2>&1; then
    print -r -- "sing-box not found" >&2
    return 1
  fi
  if [[ ! -f "${MYVPN_MACBOOK_CONF}" || ! -f "${MYVPN_HOME_CONF}" ]]; then
    print -r -- "missing ${MYVPN_MACBOOK_CONF} or ${MYVPN_HOME_CONF}" >&2
    return 1
  fi
  if [[ ! -f "${MYVPN_GEOSITE_SRS}" || ! -f "${MYVPN_GEOIP_SRS}" ]]; then
    print -r -- "rules missing — run: myvpn update-rules" >&2
    return 1
  fi

  myvpn_stop_app_tunnels
  if ! myvpn_config_fresh; then
    myvpn_render || return 1
    "${MYVPN_SING_BOX}" check -c "${MYVPN_CONFIG_JSON}" || return 1
  fi

  # Detached start via Python start_new_session (nohup breaks under osascript ioctl).
  local cmd
  cmd="/usr/bin/python3 '${MYVPN_LIB}/start_singbox.py' start --sing-box '${MYVPN_SING_BOX}' --config '${MYVPN_CONFIG_JSON}' --workdir '${MYVPN_HOME}' --pid-file '${MYVPN_PID_FILE}' --log-file '${MYVPN_LOG_FILE}'"
  if ! myvpn_run_admin "$cmd"; then
    print -r -- "failed to start sing-box (admin)" >&2
    return 1
  fi
  if ! myvpn_wait_running; then
    print -r -- "sing-box did not stay up — see ${MYVPN_LOG_FILE}" >&2
    return 1
  fi
  myvpn_dns_apply_tun
  print -r -- "up pid=$(/bin/cat "${MYVPN_PID_FILE}")"
  if [[ -z "${MYVPN_QUIET:-}" ]]; then
    myvpn_notify "myvpn up"
  fi
}

# Flush system DNS cache (needs admin). Safe while sing-box already up.
myvpn_flush_dns() {
  myvpn_dns_apply_tun
  print -r -- "dns → ${MYVPN_TUN_DNS} (cache flushed)"
}

myvpn_cmd_down() {
  local cmd
  if ! myvpn_is_running; then
    /bin/rm -f "${MYVPN_PID_FILE}" 2>/dev/null || true
    print -r -- "already down"
    return 0
  fi
  cmd="/usr/bin/python3 '${MYVPN_LIB}/start_singbox.py' stop --pid-file '${MYVPN_PID_FILE}'"
  myvpn_run_admin "$cmd" || true
  /bin/rm -f "${MYVPN_PID_FILE}" 2>/dev/null || true
  myvpn_dns_clear
  print -r -- "down"
  if [[ -z "${MYVPN_QUIET:-}" ]]; then
    myvpn_notify "myvpn down"
  fi
}

myvpn_public_ip() {
  local t="${MYVPN_IP_TIMEOUT:-2}"
  /usr/bin/curl -4 -sS --max-time "${t}" "${MYVPN_PUBLIC_IP_URL}" 2>/dev/null | tr -d '\n' || true
}

myvpn_cmd_status() {
  local tun=0 macbook=0 home=0 nas=0 pub=""
  local ping_w="${MYVPN_PING_WAIT:-400}"
  if myvpn_is_running; then
    tun=1
  fi
  if /sbin/ping -c 1 -W "${ping_w}" 10.13.13.1 >/dev/null 2>&1; then
    home=1
  fi
  if /sbin/ping -c 1 -W "${ping_w}" 10.8.0.1 >/dev/null 2>&1; then
    macbook=1
  fi
  # Fast path: presence of mount point without blocking ls on stale SMB.
  if [[ -d "${MYVPN_NAS_MOUNT}/Project" ]]; then
    nas=1
  elif [[ -d "${MYVPN_NAS_MOUNT}" ]] && /sbin/mount | /usr/bin/grep -q " on ${MYVPN_NAS_MOUNT} "; then
    nas=1
  fi
  if [[ -z "${MYVPN_STATUS_SKIP_IP:-}" ]]; then
    pub="$(myvpn_public_ip)"
  fi
  print -r -- "tun=${tun}"
  print -r -- "macbook=${macbook}"
  print -r -- "home=${home}"
  print -r -- "nas=${nas}"
  if [[ -n "$pub" ]]; then
    print -r -- "ip=${pub}"
  else
    print -r -- "ip="
  fi
  if (( tun == 1 )); then
    return 0
  fi
  return 1
}
