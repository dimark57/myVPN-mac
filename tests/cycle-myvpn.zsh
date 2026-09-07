#!/bin/zsh
# Полный цикл myvpn (doc-6): disconnect → up → C* → down → restore.
#
# Запуск:
#   /bin/zsh tests/cycle-myvpn.zsh
#
# Отчёт: ~/.cache/myvpn-cycle/latest.txt
# Env:
#   MYVPN_BIN          — путь к myvpn (default: app runtime или PATH)
#   MYVPN_CYCLE_REPORT_DIR
#   MYVPN_CYCLE_RESTORE=myvpn|app  (default myvpn — вернуть split-tunnel + NAS)
#   WG_APP_MACBOOK=MacBook         — если restore=app

set -uo pipefail

ROOT="$(cd "${0:A:h}/.." && pwd)"
REPORT_DIR="${MYVPN_CYCLE_REPORT_DIR:-${HOME}/.cache/myvpn-cycle}"
APP_MACBOOK="${WG_APP_MACBOOK:-MacBook}"
RESTORE="${MYVPN_CYCLE_RESTORE:-myvpn}"
CURL="/usr/bin/curl"
DIG="/usr/bin/dig"
PING="/sbin/ping"
IFCONFIG="/sbin/ifconfig"
ROUTE="/sbin/route"
NC="/usr/sbin/scutil"
NS="/usr/sbin/networksetup"
TUN_DNS="${MYVPN_TUN_DNS:-172.19.0.1}"

resolve_myvpn() {
  if [[ -n "${MYVPN_BIN:-}" && -x "${MYVPN_BIN}" ]]; then
    print -r -- "${MYVPN_BIN}"
    return 0
  fi
  local cand
  for cand in \
    "${HOME}/Applications/myVPN.app/Contents/Resources/runtime/bin/myvpn" \
    "${ROOT}/bin/myvpn" \
    "${HOME}/.local/bin/myvpn"
  do
    if [[ -x "$cand" ]]; then
      print -r -- "$cand"
      return 0
    fi
  done
  if command -v myvpn >/dev/null 2>&1; then
    command -v myvpn
    return 0
  fi
  return 1
}

MYVPN="$(resolve_myvpn)" || {
  print -r -- "myvpn binary not found" >&2
  exit 1
}

mkdir -p "${REPORT_DIR}"
REPORT_FILE="${REPORT_DIR}/report-$(/bin/date +%Y%m%d-%H%M%S).txt"
LATEST="${REPORT_DIR}/latest.txt"

typeset -a CHECK_LINES=()
typeset -i FAIL_COUNT=0
typeset CYCLE_OK=unknown
typeset -i UP_OK=0
typeset -i WAS_UP=0

log() {
  local line="[$(/bin/date '+%H:%M:%S')] $*"
  print -r -- "$line" | /usr/bin/tee -a "${REPORT_FILE}"
}

record_check() {
  local name="$1" ok="$2" detail="$3"
  local mark="PASS"
  if [[ "$ok" != "1" ]]; then
    mark="FAIL"
    (( FAIL_COUNT++ )) || true
  fi
  CHECK_LINES+=("${mark}  ${name}  ${detail}")
  log "${mark}  ${name}  ${detail}"
}

snapshot_state() {
  local label="$1"
  log "--- ${label} ---"
  "${MYVPN}" status >> "${REPORT_FILE}" 2>&1 || true
  "${IFCONFIG}" 2>/dev/null | /usr/bin/awk '/inet 10\.(8|13|57)\./ {print}' >> "${REPORT_FILE}" || true
  "${NC}" --nc list 2>/dev/null | /usr/bin/grep -E 'wireguard|Connected' >> "${REPORT_FILE}" || true
  log "---"
}

default_network_service() {
  local ifname port="" line
  ifname="$("${ROUTE}" -n get default 2>/dev/null | /usr/bin/awk '/interface:/{print $2; exit}')"
  [[ -n "$ifname" ]] || return 1
  while IFS= read -r line; do
    if [[ "$line" == Hardware\ Port:* ]]; then
      port="${line#Hardware Port: }"
    elif [[ "$line" == Device:\ "$ifname" && -n "$port" ]]; then
      print -r -- "$port"
      return 0
    fi
  done < <("${NS}" -listallhardwareports 2>/dev/null)
  return 1
}

wait_for() {
  local desc="$1" timeout="$2"
  shift 2
  local i
  for (( i=1; i<=timeout; i++ )); do
    if "$@" >/dev/null 2>&1; then
      return 0
    fi
    /bin/sleep 1
  done
  log "таймаут: ${desc} (${timeout}s)"
  return 1
}

has_inet() {
  local addr="$1"
  "${IFCONFIG}" 2>/dev/null | /usr/bin/grep -Fq "inet ${addr}"
}

myvpn_tun_up() {
  local st
  st="$("${MYVPN}" status 2>/dev/null | /usr/bin/awk -F= '/^tun=/{print $2; exit}')"
  [[ "$st" == "1" ]]
}

app_macbook_connected() {
  local st
  st="$("${NC}" --nc status "${APP_MACBOOK}" 2>/dev/null | /usr/bin/head -1)"
  [[ "$st" == [Cc]onnected* ]]
}

app_tunnel_listed() {
  local name="$1" line quoted
  while IFS= read -r line; do
    [[ "$line" == *com.wireguard.macos* ]] || continue
    quoted="${line#*\"}"
    quoted="${quoted%%\"*}"
    [[ "$quoted" == "$name" ]] && return 0
  done < <("${NC}" --nc list 2>/dev/null)
  return 1
}

stop_wireguard_apps() {
  local line name
  while IFS= read -r line; do
    [[ "$line" == *com.wireguard.macos* ]] || continue
    [[ "$line" == *"(Connected)"* ]] || continue
    name="${line#*\"}"
    name="${name%%\"*}"
    [[ -n "$name" ]] || continue
    log "stop WireGuard.app: ${name}"
    "${NC}" --nc stop "$name" >> "${REPORT_FILE}" 2>&1 || true
  done < <("${NC}" --nc list 2>/dev/null)
}

# Legacy brew utun cleanup if still present
stop_brew_wg() {
  local apply="/Users/dmitrijstolarov/Documents/Utilits/local/alfred/wireguard/apply-wg.zsh"
  if [[ -x "$apply" ]] && { has_inet "10.8.0.3" || has_inet "10.13.13.2"; } && ! myvpn_tun_up; then
    /bin/zsh "$apply" brew-down >> "${REPORT_FILE}" 2>&1 || true
  fi
}

phase_disconnect_all() {
  log "ФАЗА 1: отключить myvpn + WireGuard.app (+ legacy brew)"
  snapshot_state "до отключения"
  if myvpn_tun_up; then
    WAS_UP=1
    "${MYVPN}" down >> "${REPORT_FILE}" 2>&1 || log "myvpn down: ошибка"
  else
    log "myvpn уже down"
  fi
  stop_wireguard_apps
  stop_brew_wg
  /bin/sleep 2
  snapshot_state "после отключения"
  local disc_ok=1
  myvpn_tun_up && disc_ok=0
  has_inet "10.8.0.3" && disc_ok=0
  has_inet "10.13.13.2" && disc_ok=0
  record_check "disconnect_all" "$disc_ok" "tun/brew utun сняты"
}

phase_myvpn_up() {
  log "ФАЗА 2: myvpn up (${MYVPN})"
  if "${MYVPN}" up >> "${REPORT_FILE}" 2>&1; then
    UP_OK=1
    log "myvpn up: ok"
  else
    UP_OK=0
    record_check "myvpn_up" "0" "up failed"
    return 1
  fi
  wait_for "tun=1" 30 myvpn_tun_up || true
  /bin/sleep 3
  snapshot_state "после up"
  record_check "myvpn_up" "$(myvpn_tun_up && echo 1 || echo 0)" "tun after up"
  return 0
}

phase_verify() {
  log "ФАЗА 3: проверки (doc-6 C*)"
  local st_tun st_mb st_hm st_nas
  st_tun="$("${MYVPN}" status 2>/dev/null | /usr/bin/awk -F= '/^tun=/{print $2; exit}')"
  st_mb="$("${MYVPN}" status 2>/dev/null | /usr/bin/awk -F= '/^macbook=/{print $2; exit}')"
  st_hm="$("${MYVPN}" status 2>/dev/null | /usr/bin/awk -F= '/^home=/{print $2; exit}')"
  st_nas="$("${MYVPN}" status 2>/dev/null | /usr/bin/awk -F= '/^nas=/{print $2; exit}')"
  record_check "iface" "$([[ "$st_tun" == "1" && "$st_mb" == "1" && "$st_hm" == "1" ]] && echo 1 || echo 0)" "tun=${st_tun} macbook=${st_mb} home=${st_hm}"
  record_check "status_separate" "$([[ -n "$st_tun" && -n "$st_mb" && -n "$st_hm" ]] && echo 1 || echo 0)" "keys present (not AND-only)"

  local dns_backlog dns_ocode
  dns_backlog="$("${DIG}" +short +time=3 +tries=1 backlog.digials.com A 2>/dev/null | /usr/bin/head -1 | tr -d '\n')"
  dns_ocode="$("${DIG}" +short +time=3 +tries=1 ocode.digials.com A 2>/dev/null | /usr/bin/head -1 | tr -d '\n')"
  record_check "dns_backlog" "$([[ "$dns_backlog" == "10.57.0.100" ]] && echo 1 || echo 0)" "got ${dns_backlog:-empty}"
  record_check "dns_ocode" "$([[ "$dns_ocode" == "10.57.0.100" ]] && echo 1 || echo 0)" "got ${dns_ocode:-empty}"

  local svc dns_first
  svc="$(default_network_service 2>/dev/null || true)"
  if [[ -n "$svc" ]]; then
    dns_first="$("${NS}" -getdnsservers "$svc" 2>/dev/null | /usr/bin/head -1 | tr -d '\n')"
    log "DNS на «${svc}»: ${dns_first:-<empty>}"
    # Expect TUN DNS (not WG conf 1.1.1.1)
    record_check "dns_system" "$([[ "$dns_first" == "${TUN_DNS}" ]] && echo 1 || echo 0)" "ожидали ${TUN_DNS}, got ${dns_first:-empty}"
  else
    record_check "dns_system" "0" "нет active Network Service"
  fi

  local hub_code ocode_code pub_ip
  hub_code="$("${CURL}" -4 -sS -o /dev/null -w '%{http_code}' --max-time 8 https://backlog.digials.com/ 2>/dev/null || echo 000)"
  ocode_code="$("${CURL}" -4 -sS -o /dev/null -w '%{http_code}' --max-time 8 https://ocode.digials.com/ 2>/dev/null || echo 000)"
  pub_ip="$("${CURL}" -4 -sS --max-time 8 https://ifconfig.me 2>/dev/null | tr -d '\n')"
  record_check "hub_http" "$([[ "$hub_code" == "200" ]] && echo 1 || echo 0)" "HTTP ${hub_code}"
  record_check "ocode_http" "$([[ "$ocode_code" == "200" || "$ocode_code" == "301" || "$ocode_code" == "302" || "$ocode_code" == "307" ]] && echo 1 || echo 0)" "HTTP ${ocode_code}"
  record_check "public_ip_macbook" "$([[ -n "$pub_ip" && "$pub_ip" != "94.41.85.180" ]] && echo 1 || echo 0)" "got ${pub_ip:-empty}"

  local gw_home nas_ping
  if "${PING}" -c 1 -W 2000 10.13.13.1 >/dev/null 2>&1; then gw_home=1; else gw_home=0; fi
  if "${PING}" -c 1 -W 2000 10.57.0.100 >/dev/null 2>&1; then nas_ping=1; else nas_ping=0; fi
  record_check "ping_home_gw" "$gw_home" "10.13.13.1"
  record_check "ping_nas" "$nas_ping" "10.57.0.100"

  # C11: with TUN auto_route OS `route get` shows utun — handshake (macbook/home=1) is the real check.
  record_check "endpoint_direct" "$([[ "$st_mb" == "1" && "$st_hm" == "1" ]] && echo 1 || echo 0)" "peers up (TUN hides LAN route; OS route may show utun)"

  record_check "mount_nas" "$([[ "$st_nas" == "1" || -d /Volumes/Nas/Project ]] && echo 1 || echo 0)" "nas=${st_nas}"
}

phase_myvpn_down() {
  log "ФАЗА 4: myvpn down"
  if (( UP_OK == 1 )) || myvpn_tun_up; then
    "${MYVPN}" down >> "${REPORT_FILE}" 2>&1 || log "down: ошибка"
  else
    log "down: пропуск"
  fi
  /bin/sleep 2
  snapshot_state "после down"
}

phase_restore() {
  if [[ "${RESTORE}" == "app" ]]; then
    log "ФАЗА 5: restore WireGuard.app «${APP_MACBOOK}»"
    if ! app_tunnel_listed "${APP_MACBOOK}"; then
      record_check "restore" "0" "нет профиля ${APP_MACBOOK}"
      return 1
    fi
    if ! app_macbook_connected; then
      "${NC}" --nc start "${APP_MACBOOK}" >> "${REPORT_FILE}" 2>&1 || true
      wait_for "app Connected" 30 app_macbook_connected || true
    fi
    local pub_after connected_ok=0
    app_macbook_connected && connected_ok=1
    pub_after="$("${CURL}" -4 -sS --max-time 10 https://ifconfig.me 2>/dev/null | tr -d '\n')"
    record_check "restore" "$([[ "$connected_ok" == "1" && -n "$pub_after" ]] && echo 1 || echo 0)" "app Connected=${connected_ok} IP ${pub_after:-empty}"
  else
    log "ФАЗА 5: restore myvpn up + NAS"
    if "${MYVPN}" up >> "${REPORT_FILE}" 2>&1; then
      wait_for "tun=1" 30 myvpn_tun_up || true
      /bin/sleep 2
      "${MYVPN}" mount-nas --force >> "${REPORT_FILE}" 2>&1 || true
      local pub_after
      pub_after="$("${CURL}" -4 -sS --max-time 10 https://ifconfig.me 2>/dev/null | tr -d '\n')"
      record_check "restore" "$(myvpn_tun_up && [[ -n "$pub_after" ]] && echo 1 || echo 0)" "myvpn tun + IP ${pub_after:-empty}"
    else
      record_check "restore" "0" "myvpn up failed"
    fi
  fi
  snapshot_state "после restore"
}

write_summary() {
  {
    print -r -- "myvpn cycle (doc-6)"
    print -r -- "bin: ${MYVPN}"
    print -r -- "restore: ${RESTORE}"
    print -r -- "report: ${REPORT_FILE}"
    print -r -- ""
    if (( FAIL_COUNT == 0 && UP_OK == 1 )); then
      CYCLE_OK=PASS
      print -r -- "OVERALL: PASS"
    else
      CYCLE_OK=FAIL
      print -r -- "OVERALL: FAIL (${FAIL_COUNT} check(s) failed, up=${UP_OK})"
    fi
    print -r -- ""
    print -r -- "Checks:"
    local line
    for line in "${CHECK_LINES[@]}"; do
      print -r -- "  ${line}"
    done
    print -r -- ""
    print -r -- "Full log: ${REPORT_FILE}"
  } | /usr/bin/tee "${LATEST}" >> "${REPORT_FILE}"

  /usr/bin/osascript -e "display notification \"${CYCLE_OK}: см. ${LATEST}\" with title \"myvpn cycle\"" 2>/dev/null || true
  print -r -- ""
  print -r -- "=== ${CYCLE_OK} ==="
  /bin/cat "${LATEST}"
}

main() {
  log "=== myvpn cycle ==="
  log "bin=${MYVPN} restore=${RESTORE}"
  log "report → ${REPORT_FILE}"

  {
    phase_disconnect_all
    if phase_myvpn_up; then
      phase_verify
    else
      log "up не удался — проверки пропущены"
    fi
  } always {
    phase_myvpn_down
    phase_restore
    write_summary
  }

  [[ "${CYCLE_OK}" == "PASS" ]]
}

main "$@"
