# Interpretive connectivity report. Uses: env.zsh, process.zsh, nas.zsh, doctor_probe.py
# Report: ~/.cache/myvpn-doctor/latest.txt + state.json (для diff)

myvpn_doctor_report_dir() {
  print -r -- "${MYVPN_DOCTOR_REPORT_DIR:-${HOME}/.cache/myvpn-doctor}"
}

myvpn_cmd_doctor() {
  local report_dir report_file latest state_file prev_state
  local -a CHECK_LINES=() VERDICT_LINES=() ACTION_LINES=() EVIDENCE=()
  local -i FAIL_COUNT=0 WARN_COUNT=0
  local ping_w="${MYVPN_PING_WAIT:-1000}"
  local DIG="/usr/bin/dig"
  local CURL="/usr/bin/curl"
  local PING="/sbin/ping"
  local NS="/usr/sbin/networksetup"
  local IFCONFIG="/sbin/ifconfig"
  local NC="/usr/sbin/scutil"
  local ROUTE="/sbin/route"
  local primary="" confidence="medium"

  report_dir="$(myvpn_doctor_report_dir)"
  /bin/mkdir -p "${report_dir}"
  report_file="${report_dir}/report-$(/bin/date +%Y%m%d-%H%M%S).txt"
  latest="${report_dir}/latest.txt"
  state_file="${report_dir}/state.json"
  prev_state="${report_dir}/state.prev.json"
  if [[ -f "${state_file}" ]]; then
    /bin/cp -f "${state_file}" "${prev_state}" 2>/dev/null || true
  fi

  _doc_log() {
    local line="[$(/bin/date '+%H:%M:%S')] $*"
    print -r -- "$line" | /usr/bin/tee -a "${report_file}"
  }

  _doc_check() {
    # name ok detail — ok: 1=PASS 0=FAIL 2=WARN 3=INFO
    local name="$1" ok="$2" detail="$3" mark="PASS"
    case "$ok" in
      1) mark="PASS" ;;
      2) mark="WARN"; (( WARN_COUNT++ )) || true ;;
      3) mark="INFO" ;;
      *) mark="FAIL"; (( FAIL_COUNT++ )) || true ;;
    esac
    CHECK_LINES+=("${mark}  ${name}  ${detail}")
    _doc_log "${mark}  ${name}  ${detail}"
  }

  _doc_ping() {
    "${PING}" -c 1 -W "${ping_w}" "$1" >/dev/null 2>&1
  }

  _doc_evidence() { EVIDENCE+=("$1") }
  _doc_action() { ACTION_LINES+=("$1") }

  _doc_log "=== myvpn doctor ==="
  _doc_log "root=${MYVPN_ROOT}"
  _doc_log "report → ${report_file}"
  _doc_log ""

  # --- binaries / runtime ---
  local sb_ok=0
  if [[ -x "${MYVPN_SING_BOX}" ]] || command -v "${MYVPN_SING_BOX}" >/dev/null 2>&1; then
    sb_ok=1
  fi
  _doc_check "sing-box" "$sb_ok" "${MYVPN_SING_BOX}"

  local root_local=0
  case "${MYVPN_ROOT}" in
    "${HOME}/.local/share/myvpn"|"${HOME}/Applications/myVPN.app/Contents/Resources/runtime"|"/Applications/myVPN.app/Contents/Resources/runtime")
      root_local=1
      ;;
    *)
      # Any path under $HOME or /Applications that is not /Volumes/*
      if [[ "${MYVPN_ROOT}" != /Volumes/* ]]; then
        root_local=1
      fi
      ;;
  esac
  _doc_check "runtime_local" "$root_local" "${MYVPN_ROOT} (must not be NAS)"

  if myvpn_helper_available; then
    _doc_check "helper" "1" "socket $(myvpn_helper_sock)"
  else
    _doc_check "helper" "0" "no socket $(myvpn_helper_sock)"
    _doc_evidence "helper socket missing"
  fi

  if myvpn_autostart_enabled 2>/dev/null; then
    _doc_check "autostart" "1" "flag/Login Item"
  else
    _doc_check "autostart" "2" "off"
  fi

  if myvpn_auto_nas_enabled; then
    _doc_check "auto_nas" "1" "remount after up"
  else
    _doc_check "auto_nas" "2" "off"
  fi

  # --- config endpoints (safe) ---
  local probe_json="" mb_host="" mb_port="" hm_host="" hm_port="" mb_system=0 hm_system=0
  local mb_local="" hm_local="" route_final=""
  local udp_mb_ok="" udp_hm_ok="" log_signals=""
  if [[ -f "${MYVPN_CONFIG_JSON}" ]]; then
    probe_json="$(/usr/bin/python3 "${MYVPN_LIB}/doctor_probe.py" \
      --config "${MYVPN_CONFIG_JSON}" \
      --log "${MYVPN_LOG_FILE}" \
      --udp-probe 2>/dev/null || true)"
  fi
  if [[ -n "${probe_json}" ]]; then
    eval "$(
      /usr/bin/python3 -c '
import json,sys,shlex
d=json.load(sys.stdin)
c=d.get("config") or {}
def q(s): return shlex.quote("" if s is None else str(s))
print("route_final="+q(c.get("final")))
for ep in c.get("endpoints") or []:
    tag=ep.get("tag")
    if tag=="macbook":
        print("mb_host="+q(ep.get("peer_host")))
        print("mb_port="+q(ep.get("peer_port")))
        print("mb_local="+q(ep.get("local")))
        print("mb_system="+("1" if ep.get("system") else "0"))
    elif tag=="home":
        print("hm_host="+q(ep.get("peer_host")))
        print("hm_port="+q(ep.get("peer_port")))
        print("hm_local="+q(ep.get("local")))
        print("hm_system="+("1" if ep.get("system") else "0"))
udp=d.get("udp") or {}
for tag,u in udp.items():
    pref="udp_mb" if tag=="macbook" else ("udp_hm" if tag=="home" else None)
    if not pref: continue
    print(f"{pref}_ok="+("1" if u.get("ok") else "0"))
    print(f"{pref}_ms="+q(u.get("ms")))
    print(f"{pref}_err="+q(u.get("error")))
lg=d.get("log") or {}
print("log_signals="+q(",".join(lg.get("signals") or [])))
' <<<"${probe_json}"
    )"
    _doc_check "cfg_macbook_ep" "$([[ -n "$mb_host" ]] && echo 1 || echo 0)" \
      "${mb_host:-?}:${mb_port:-?} local=${mb_local:-?} system=${mb_system} (userspace WG — OS ifconfig без 10.8.x ожидаемо)"
    _doc_check "cfg_home_ep" "$([[ -n "$hm_host" ]] && echo 1 || echo 0)" \
      "${hm_host:-?}:${hm_port:-?} local=${hm_local:-?} system=${hm_system}"
    _doc_check "cfg_route_final" "$([[ "$route_final" == "macbook" ]] && echo 1 || echo 2)" \
      "final=${route_final:-empty}"
  else
    _doc_check "cfg_parse" "0" "не удалось разобрать ${MYVPN_CONFIG_JSON}"
  fi

  # --- VPN / peers ---
  local tun=0 macbook_icmp=0 home=0 nas_fast=0 pub="" pid=""
  local mb_ep_icmp=0 hm_ep_icmp=0
  local egress_via_macbook=0 egress_unknown=0
  myvpn_is_running && tun=1
  if [[ -f "${MYVPN_PID_FILE}" ]]; then
    pid="$(/bin/cat "${MYVPN_PID_FILE}" 2>/dev/null || true)"
  fi
  _doc_ping 10.8.0.1 && macbook_icmp=1
  _doc_ping 10.13.13.1 && home=1
  [[ -n "$mb_host" ]] && _doc_ping "$mb_host" && mb_ep_icmp=1
  [[ -n "$hm_host" ]] && _doc_ping "$hm_host" && hm_ep_icmp=1
  if [[ -d "${MYVPN_NAS_MOUNT}/Project" ]]; then
    nas_fast=1
  elif [[ -d "${MYVPN_NAS_MOUNT}" ]] && myvpn_nas_in_mount_table; then
    nas_fast=1
  fi
  pub="$(myvpn_public_ip)"

  _doc_check "tun" "$tun" "pid=${pid:-none} (sing-box)"
  # ICMP to 10.8.0.1 is soft: many WG peers filter ICMP; not a hard fail alone.
  if (( macbook_icmp )); then
    _doc_check "ping_macbook_gw" "1" "10.8.0.1"
  else
    _doc_check "ping_macbook_gw" "2" "10.8.0.1 no reply (часто ICMP filter — смотри egress)"
  fi
  _doc_check "ping_home_gw" "$home" "10.13.13.1"
  _doc_check "ping_macbook_endpoint" "$mb_ep_icmp" "${mb_host:-unknown} (VPS ICMP)"
  _doc_check "ping_home_endpoint" "$hm_ep_icmp" "${hm_host:-unknown} (home WAN ICMP)"

  if [[ -n "$pub" && -n "$mb_host" && "$pub" == "$mb_host" ]]; then
    egress_via_macbook=1
    _doc_check "egress_ip" "1" "${pub} == macbook endpoint → default egress через macbook OK"
    _doc_evidence "public IP matches macbook endpoint ${mb_host}"
  elif [[ -n "$pub" ]]; then
    egress_unknown=1
    _doc_check "egress_ip" "2" "${pub} (не равен endpoint ${mb_host:-?}) — RU/direct или другой путь"
  else
    _doc_check "egress_ip" "$([[ "$tun" == "1" ]] && echo 0 || echo 2)" "empty (ifconfig.me)"
    (( tun )) && _doc_evidence "no public IP while tun=1"
  fi

  if [[ -n "${udp_mb_ok:-}" ]]; then
    _doc_check "udp_macbook_51820" "$([[ "$udp_mb_ok" == "1" ]] && echo 1 || echo 0)" \
      "send ${mb_host}:${mb_port} ok=${udp_mb_ok} ms=${udp_mb_ms:-?} ${udp_mb_err:-}"
  fi
  if [[ -n "${udp_hm_ok:-}" ]]; then
    _doc_check "udp_home_51820" "$([[ "$udp_hm_ok" == "1" ]] && echo 1 || echo 0)" \
      "send ${hm_host}:${hm_port} ok=${udp_hm_ok} ms=${udp_hm_ms:-?} ${udp_hm_err:-}"
  fi

  # WG.app conflict
  local wg_app=0 wg_line
  while IFS= read -r wg_line; do
    [[ "$wg_line" == *com.wireguard.macos* ]] || continue
    [[ "$wg_line" == *"(Connected)"* ]] || continue
    wg_app=1
    _doc_log "info  wg_app  Connected: ${wg_line}"
  done < <("${NC}" --nc list 2>/dev/null)
  if (( wg_app )); then
    if (( tun )); then
      _doc_check "wg_app_conflict" "0" "WireGuard.app Connected + myvpn tun — конфликт"
      _doc_evidence "WireGuard.app Connected while sing-box up"
    else
      _doc_check "wg_app_conflict" "2" "WireGuard.app Connected (myvpn down — ок временно)"
    fi
  else
    _doc_check "wg_app_conflict" "1" "нет Connected WG.app"
  fi

  # OS addresses: with system=false expect NO 10.8/10.13 on ifconfig
  local has_mb_addr=0 has_hm_addr=0 has_tun_addr=0
  "${IFCONFIG}" 2>/dev/null | /usr/bin/grep -Fq "inet 10.8.0." && has_mb_addr=1
  "${IFCONFIG}" 2>/dev/null | /usr/bin/grep -Fq "inet 10.13.13." && has_hm_addr=1
  "${IFCONFIG}" 2>/dev/null | /usr/bin/grep -Fq "inet 172.19.0." && has_tun_addr=1
  if (( mb_system == 0 )); then
    if (( has_mb_addr )); then
      _doc_check "os_addr_macbook" "2" "10.8.0.x на OS при system=false — странно (legacy/WG.app?)"
    else
      _doc_check "os_addr_macbook" "3" "нет 10.8.0.x на OS — норма для userspace WG"
    fi
  else
    _doc_check "os_addr_macbook" "$has_mb_addr" "system=true → ждали 10.8.0.x"
  fi
  if (( hm_system == 0 )); then
    if (( has_hm_addr )); then
      _doc_check "os_addr_home" "2" "10.13.13.x на OS при system=false — странно"
    else
      _doc_check "os_addr_home" "3" "нет 10.13.13.x на OS — норма для userspace WG"
    fi
  else
    _doc_check "os_addr_home" "$has_hm_addr" "system=true → ждали 10.13.13.x"
  fi
  if (( tun )); then
    _doc_check "os_tun" "$has_tun_addr" "172.19.0.x на iface"
  else
    _doc_check "os_tun" "3" "tun down — skip"
  fi

  # Routes for endpoints / LAN
  local r_mb r_hm r_nas r_def
  r_mb="$("${ROUTE}" -n get "${mb_host:-127.0.0.1}" 2>/dev/null | /usr/bin/awk '/interface:/{print $2; exit}')"
  r_hm="$("${ROUTE}" -n get "${hm_host:-127.0.0.1}" 2>/dev/null | /usr/bin/awk '/interface:/{print $2; exit}')"
  r_nas="$("${ROUTE}" -n get "${MYVPN_NAS_HOST}" 2>/dev/null | /usr/bin/awk '/interface:/{print $2; exit}')"
  r_def="$("${ROUTE}" -n get default 2>/dev/null | /usr/bin/awk '/interface:/{print $2; exit}')"
  _doc_check "route_mb_ep" "3" "${mb_host:-?} → if=${r_mb:-?} (должен быть физ. NIC / direct)"
  _doc_check "route_hm_ep" "3" "${hm_host:-?} → if=${r_hm:-?} (должен быть физ. NIC / direct)"
  _doc_check "route_nas" "3" "${MYVPN_NAS_HOST} → if=${r_nas:-?}"
  _doc_check "route_default" "3" "default → if=${r_def:-?}"
  # OS route via utun for WG endpoints can flap handshake after sleep (sing-box direct may still work).
  if [[ "$r_mb" == utun* ]]; then
    _doc_check "route_mb_via_tun" "2" "${mb_host} via ${r_mb} — риск hairpin/handshake flap"
    _doc_evidence "macbook endpoint OS-route via ${r_mb}"
  fi
  if [[ "$r_hm" == utun* ]]; then
    _doc_check "route_hm_via_tun" "2" "${hm_host} via ${r_hm} — риск hairpin/handshake flap"
    _doc_evidence "home endpoint OS-route via ${r_hm}"
  fi

  # --- DNS ---
  local dns_first dns_ok=0
  dns_first="$("${NS}" -getdnsservers Wi-Fi 2>/dev/null | /usr/bin/head -1 | tr -d '\n')"
  if (( tun )); then
    [[ "$dns_first" == "${MYVPN_TUN_DNS}" ]] && dns_ok=1
    _doc_check "dns_system" "$dns_ok" "Wi-Fi DNS=${dns_first:-empty} (ждали ${MYVPN_TUN_DNS})"
    (( dns_ok == 0 )) && _doc_evidence "Wi-Fi DNS stale/not TUN"
  else
    if [[ "$dns_first" == "${MYVPN_TUN_DNS}" ]]; then
      _doc_check "dns_system" "2" "Wi-Fi всё ещё ${MYVPN_TUN_DNS} при tun=0"
      _doc_evidence "stale TUN DNS while down"
    else
      _doc_check "dns_system" "1" "Wi-Fi DNS=${dns_first:-DHCP/Empty}"
    fi
  fi

  local dns_backlog dns_ocode dns_remote
  dns_backlog="$("${DIG}" +short +time=2 +tries=1 backlog.digials.com A 2>/dev/null | /usr/bin/head -1 | tr -d '\n')"
  dns_ocode="$("${DIG}" +short +time=2 +tries=1 ocode.digials.com A 2>/dev/null | /usr/bin/head -1 | tr -d '\n')"
  # Non-RU resolve via TUN hijack → should use dns-remote (macbook→1.1.1.1)
  dns_remote="$("${DIG}" +short +time=2 +tries=1 cloudflare.com A 2>/dev/null | /usr/bin/head -1 | tr -d '\n')"
  if (( home )); then
    _doc_check "dns_backlog" "$([[ "$dns_backlog" == "10.57.0.100" ]] && echo 1 || echo 0)" "got ${dns_backlog:-empty}"
    _doc_check "dns_ocode" "$([[ "$dns_ocode" == "10.57.0.100" ]] && echo 1 || echo 0)" "got ${dns_ocode:-empty}"
  else
    _doc_check "dns_hub" "2" "home down — digials skip (backlog=${dns_backlog:-empty})"
  fi
  if (( tun )); then
    if [[ -n "$dns_remote" ]]; then
      _doc_check "dns_remote_sample" "1" "cloudflare.com → ${dns_remote}"
    else
      _doc_check "dns_remote_sample" "0" "cloudflare.com empty (dns-remote/macbook?)"
      _doc_evidence "remote DNS via TUN failed"
    fi
  fi

  # --- Hub HTTP ---
  local hub_code="000"
  if (( home )); then
    hub_code="$("${CURL}" -4 -sS -o /dev/null -w '%{http_code}' --max-time 6 https://backlog.digials.com/ 2>/dev/null || echo 000)"
    _doc_check "hub_http" "$([[ "$hub_code" == "200" ]] && echo 1 || echo 0)" "HTTP ${hub_code}"
    [[ "$hub_code" != "200" ]] && _doc_evidence "hub HTTP ${hub_code}"
  else
    _doc_check "hub_http" "2" "skip (home=0)"
  fi

  # --- NAS ---
  local nas_host=0 nas_alive_rc=1 nas_key=0
  _doc_ping "${MYVPN_NAS_HOST}" && nas_host=1
  _doc_check "ping_nas" "$nas_host" "${MYVPN_NAS_HOST}"

  if myvpn_keychain_password >/dev/null 2>&1; then
    nas_key=1
  fi
  _doc_check "nas_keychain" "$nas_key" "${MYVPN_NAS_KEYCHAIN_SERVICE}/${MYVPN_NAS_USER}"

  if (( nas_fast )); then
    myvpn_nas_is_alive
    nas_alive_rc=$?
    case "$nas_alive_rc" in
      0) _doc_check "nas_alive" "1" "${MYVPN_NAS_MOUNT} listdir ok" ;;
      2)
        _doc_check "nas_alive" "0" "stale mount (timeout)"
        _doc_evidence "NAS mount stale"
        ;;
      *)
        _doc_check "nas_alive" "0" "mount present but not alive"
        _doc_evidence "NAS mount dead"
        ;;
    esac
  else
    if (( home == 0 )); then
      _doc_check "nas_mount" "2" "не смонтирован (ожидаемо: home=0)"
    elif (( nas_host == 0 )); then
      _doc_check "nas_mount" "0" "host unreachable при home=1"
      _doc_evidence "NAS host down while home up"
    else
      _doc_check "nas_mount" "0" "host ok, mount missing"
      _doc_evidence "NAS not mounted"
    fi
  fi

  # --- rules / config ---
  local gs_ok=0 gi_ok=0 gs_mtime gi_mtime
  if [[ -f "${MYVPN_GEOSITE_SRS}" ]]; then
    gs_ok=1
    gs_mtime="$(/usr/bin/stat -f '%Sm' -t '%d.%m.%Y, %H:%M' "${MYVPN_GEOSITE_SRS}" 2>/dev/null || true)"
  fi
  if [[ -f "${MYVPN_GEOIP_SRS}" ]]; then
    gi_ok=1
    gi_mtime="$(/usr/bin/stat -f '%Sm' -t '%d.%m.%Y, %H:%M' "${MYVPN_GEOIP_SRS}" 2>/dev/null || true)"
  fi
  _doc_check "geosite-ru" "$gs_ok" "${gs_mtime:-missing}"
  _doc_check "geoip-ru" "$gi_ok" "${gi_mtime:-missing}"

  if [[ -f "${MYVPN_CONFIG_JSON}" ]]; then
    if "${MYVPN_SING_BOX}" check -c "${MYVPN_CONFIG_JSON}" >/dev/null 2>&1; then
      _doc_check "config_check" "1" "sing-box check ok"
    else
      _doc_check "config_check" "0" "sing-box check failed"
      _doc_evidence "sing-box check failed"
    fi
  else
    _doc_check "config_check" "0" "no config json"
  fi

  if [[ -n "${log_signals}" ]]; then
    _doc_check "log_signals" "3" "${log_signals}"
  fi

  # --- log tails ---
  if [[ -f "${MYVPN_LOG_FILE}" ]]; then
    _doc_log ""
    _doc_log "--- sing-box.log (last 12) ---"
    /usr/bin/tail -n 12 "${MYVPN_LOG_FILE}" 2>/dev/null | /usr/bin/tee -a "${report_file}" || true
  fi
  if [[ -f "${HOME}/Library/Logs/myvpn-menubar.log" ]]; then
    _doc_log "--- menubar.log (last 8) ---"
    /usr/bin/tail -n 8 "${HOME}/Library/Logs/myvpn-menubar.log" 2>/dev/null | /usr/bin/tee -a "${report_file}" || true
  fi

  # --- INTERPRETATION ---
  # Priority: conflict > tun down > egress down > home down > dns > nas > icmp-only false alarm
  if (( wg_app && tun )); then
    primary="CONFLICT_WG_APP"
    confidence="high"
    VERDICT_LINES+=("WireGuard.app и myvpn (sing-box) одновременно — типичный источник «отвалов» и битых маршрутов.")
    _doc_action "выключи туннели в WireGuard.app, оставь только myVPN"
  elif (( tun == 0 )); then
    primary="TUN_DOWN"
    confidence="high"
    VERDICT_LINES+=("sing-box не запущен (tun=0). Split-tunnel целиком выключен.")
    _doc_action "myvpn up  (или On в меню)"
    _doc_evidence "tun=0"
  elif (( tun == 1 && egress_via_macbook == 0 && ${#pub} == 0 )); then
    primary="MACBOOK_EGRESS_DOWN"
    confidence="high"
    VERDICT_LINES+=("TUN жив, но публичный IP пуст — default path (final=macbook) не даёт egress.")
    VERDICT_LINES+=("Скорее мёртв handshake/endpoint macbook (${mb_host:-?}:51820), не home.")
    _doc_action "проверь доступность ${mb_host}:51820/UDP с другой сети; myvpn down && myvpn up"
    (( mb_ep_icmp == 0 )) && _doc_action "VPS ${mb_host} не пингуется — endpoint/WAN/firewall"
  elif (( tun == 1 && home == 0 && egress_via_macbook == 1 )); then
    primary="HOME_DOWN_MACBOOK_OK"
    confidence="high"
    VERDICT_LINES+=("Интернет (macbook) жив, home мёртв — «отвал» ощущается как NAS/Hub/внутренние сервисы.")
    _doc_action "чинить home peer / endpoint ${hm_host}"
    (( hm_ep_icmp == 0 )) && _doc_action "home WAN ${hm_host} не пингуется"
  elif (( tun == 1 && home == 0 )); then
    primary="HOME_PEER_DOWN"
    confidence="high"
    VERDICT_LINES+=("home peer мёртв (нет 10.13.13.1) → NAS/Hub/digials тоже лягут.")
    VERDICT_LINES+=("macbook egress тоже не подтверждён (ip≠endpoint или пуст).")
    _doc_action "проверь home endpoint ${hm_host}:51820; sleep/wake → myvpn down && up"
    (( hm_ep_icmp == 0 )) && _doc_action "home WAN ${hm_host} не пингуется"
  elif (( tun == 1 && home == 1 && nas_fast == 0 && nas_host == 1 )); then
    primary="NAS_MOUNT_ONLY"
    confidence="high"
    VERDICT_LINES+=("home ок, NAS host ок, но том не смонтирован / stale.")
    _doc_action "myvpn mount-nas --force"
  elif (( tun == 1 && home == 1 && nas_fast == 1 && nas_alive_rc == 2 )); then
    primary="NAS_STALE"
    confidence="high"
    VERDICT_LINES+=("SMB half-open после VPN flap — классика.")
    _doc_action "myvpn mount-nas --force"
  elif (( tun == 1 && dns_ok == 0 )); then
    primary="DNS_STALE"
    confidence="high"
    VERDICT_LINES+=("Wi-Fi DNS не указывает на TUN ${MYVPN_TUN_DNS} — digials/RU резолв поедет мимо hijack.")
    _doc_action "myvpn flush-dns"
  elif (( tun == 1 && egress_via_macbook == 1 && home == 1 && nas_fast == 1 && macbook_icmp == 0 )); then
    primary="HEALTHY_ICMP_FALSE_ALARM"
    confidence="high"
    VERDICT_LINES+=("Система здорова. ping 10.8.0.1=0 при ip==endpoint — ICMP до WG-peer отфильтрован, это НЕ падение macbook.")
    VERDICT_LINES+=("Раньше doctor помечал это как FAIL — ложный сигнал.")
    _doc_action "если «интернет отвалился» при таком отчёте — смотри приложение/сайт (RU direct), не peer"
    if [[ "$r_mb" == utun* || "$r_hm" == utun* ]]; then
      primary="HEALTHY_BUT_ENDPOINT_VIA_TUN"
      confidence="medium"
      VERDICT_LINES+=("НО: OS route на WG endpoint идёт через utun — кандидат на handshake-отвалы после sleep.")
      _doc_action "при дропе после sleep смотри DIFF primary → HOME/MACBOOK_*"
    fi
  elif (( tun == 1 && egress_via_macbook == 1 && home == 1 )); then
    primary="HEALTHY"
    confidence="high"
    VERDICT_LINES+=("Оба канала работают: egress через macbook + home/NAS ок.")
    if [[ "$r_mb" == utun* || "$r_hm" == utun* ]]; then
      primary="HEALTHY_BUT_ENDPOINT_VIA_TUN"
      confidence="medium"
      VERDICT_LINES+=("НО: OS route на WG endpoint идёт через utun — кандидат на периодические handshake-отвалы после sleep/roam.")
      VERDICT_LINES+=("В WG.app это лечили PreUp route /32 на LAN gateway; в sing-box — route rule direct + auto_detect.")
      _doc_action "при следующем дропе сравни DIFF; если primary → HOME/MACBOOK_* после sleep — копать endpoint routing"
    fi
  elif (( tun == 1 && egress_via_macbook == 0 && home == 1 && ${#pub} > 0 )); then
    primary="EGRESS_NOT_VIA_MACBOOK"
    confidence="medium"
    VERDICT_LINES+=("home ок, публичный IP=${pub} ≠ macbook endpoint ${mb_host}.")
    VERDICT_LINES+=("Либо трафик ifconfig.me ушёл direct/RU, либо macbook peer деградировал частично.")
    _doc_action "повтори doctor; проверь udp/ping endpoint ${mb_host}; dig cloudflare.com"
  else
    primary="MIXED"
    confidence="low"
    VERDICT_LINES+=("Смешанная картина — смотри CHECKS + DIFF + evidence.")
  fi

  # log-based boost
  if [[ "${log_signals}" == *fatal=* || "${log_signals}" == *error=* ]]; then
    VERDICT_LINES+=("В хвосте sing-box.log есть error/fatal (${log_signals}).")
    confidence="medium"
  fi

  # save state + DIFF vs previous
  /usr/bin/python3 -c '
import json,sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({
  "ts": __import__("datetime").datetime.now().isoformat(timespec="seconds"),
  "tun": int(sys.argv[2]),
  "macbook_icmp": int(sys.argv[3]),
  "home": int(sys.argv[4]),
  "nas": int(sys.argv[5]),
  "pub": sys.argv[6],
  "dns": sys.argv[7],
  "hub": sys.argv[8],
  "mb_ep_icmp": int(sys.argv[9]),
  "hm_ep_icmp": int(sys.argv[10]),
  "egress_via_macbook": int(sys.argv[11]),
  "primary": sys.argv[12],
}, ensure_ascii=False, indent=2)+"\n")
' "${state_file}" "${tun}" "${macbook_icmp}" "${home}" "${nas_fast}" \
    "${pub}" "${dns_first}" "${hub_code}" "${mb_ep_icmp}" "${hm_ep_icmp}" \
    "${egress_via_macbook}" "${primary}" 2>/dev/null || true

  local diff_txt=""
  if [[ -f "${prev_state}" && -f "${state_file}" ]]; then
    diff_txt="$(/usr/bin/python3 -c '
import json,sys
from pathlib import Path
prev=json.loads(Path(sys.argv[1]).read_text())
cur=json.loads(Path(sys.argv[2]).read_text())
keys=["tun","macbook_icmp","home","nas","pub","dns","hub","mb_ep_icmp","hm_ep_icmp","egress_via_macbook","primary"]
lines=[]
for k in keys:
    a,b=prev.get(k),cur.get(k)
    if a!=b:
        lines.append(f"{k}: {a} → {b}")
print("\n".join(lines) if lines else "(no change vs previous doctor)")
' "${prev_state}" "${state_file}" 2>/dev/null || print -r -- "(diff unavailable)")"
  else
    diff_txt="(нет предыдущего state — следующий запуск даст diff)"
  fi

  local overall="PASS"
  if (( FAIL_COUNT > 0 )); then
    overall="FAIL"
  elif (( WARN_COUNT > 0 )); then
    overall="WARN"
  fi
  # Healthy false-alarm should not stay FAIL just from soft warns alone — overall already WARN/PASS
  if [[ "$primary" == "HEALTHY" || "$primary" == "HEALTHY_ICMP_FALSE_ALARM" || "$primary" == "HEALTHY_BUT_ENDPOINT_VIA_TUN" ]]; then
    if [[ "$primary" == "HEALTHY_BUT_ENDPOINT_VIA_TUN" ]]; then
      overall="WARN"
    else
      overall="PASS"
    fi
  fi

  {
    print -r -- ""
    print -r -- "=== VERDICT ==="
    print -r -- "PRIMARY: ${primary}"
    print -r -- "CONFIDENCE: ${confidence}"
    print -r -- "OVERALL: ${overall}  (fail=${FAIL_COUNT} warn=${WARN_COUNT})"
    print -r -- "snapshot: tun=${tun} home=${home} nas=${nas_fast} egress_macbook=${egress_via_macbook} icmp_mb_gw=${macbook_icmp} ip=${pub}"
    print -r -- ""
    print -r -- "Interpretation:"
    local line
    for line in "${VERDICT_LINES[@]}"; do
      print -r -- "  • ${line}"
    done
    if (( ${#EVIDENCE[@]} )); then
      print -r -- ""
      print -r -- "Evidence:"
      for line in "${EVIDENCE[@]}"; do
        print -r -- "  - ${line}"
      done
    fi
    if (( ${#ACTION_LINES[@]} )); then
      print -r -- ""
      print -r -- "Next:"
      for line in "${ACTION_LINES[@]}"; do
        print -r -- "  → ${line}"
      done
    fi
    print -r -- ""
    print -r -- "=== DIFF vs previous ==="
    print -r -- "${diff_txt}"
    print -r -- ""
    print -r -- "=== CHECKS ==="
    for line in "${CHECK_LINES[@]}"; do
      print -r -- "  ${line}"
    done
    print -r -- ""
    print -r -- "Как читать:"
    print -r -- "  HEALTHY* — сейчас каналы живы; смотри WARN про endpoint→utun."
    print -r -- "  HOME_PEER_DOWN / HOME_DOWN_MACBOOK_OK — «отвал NAS/Hub»."
    print -r -- "  MACBOOK_EGRESS_DOWN — «отвал интернета» при живом меню."
    print -r -- "  NAS_STALE / NAS_MOUNT_ONLY — только SMB."
    print -r -- "  CONFLICT_WG_APP — не мешай WG.app и myVPN."
    print -r -- "  DIFF — что изменилось с прошлого doctor (ключ к флапам)."
    print -r -- ""
    print -r -- "Full: ${report_file}"
    print -r -- "Latest: ${latest}"
    print -r -- "State: ${state_file}"
  } | /usr/bin/tee -a "${report_file}" | /usr/bin/tee "${latest}"

  # No osascript banners — app UNUserNotification / CLI stdout only.

  [[ "$overall" == "PASS" || "$overall" == "WARN" ]]
}
