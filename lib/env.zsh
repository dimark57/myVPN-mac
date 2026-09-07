# Shared paths for myvpn. Expects MYVPN_ROOT set by bin/myvpn before source.

: "${MYVPN_ROOT:?MYVPN_ROOT not set}"
: "${MYVPN_HOME:=${HOME}/.config/myvpn}"
: "${MYVPN_WG_DIR:=${HOME}/.config/wireguard}"
: "${MYVPN_MACBOOK_CONF:=${MYVPN_WG_DIR}/macbook.conf}"
: "${MYVPN_HOME_CONF:=${MYVPN_WG_DIR}/home.conf}"
: "${MYVPN_CONFIG_JSON:=${MYVPN_HOME}/sing-box.json}"
: "${MYVPN_PID_FILE:=${MYVPN_HOME}/sing-box.pid}"
: "${MYVPN_LOG_FILE:=${MYVPN_HOME}/sing-box.log}"
: "${MYVPN_RULES_DIR:=${MYVPN_HOME}/rules}"
: "${MYVPN_GEOSITE_SRS:=${MYVPN_RULES_DIR}/geosite-ru.srs}"
: "${MYVPN_GEOIP_SRS:=${MYVPN_RULES_DIR}/geoip-ru.srs}"
: "${MYVPN_NAS_HOST:=10.57.0.100}"
: "${MYVPN_NAS_SHARE:=Nas}"
: "${MYVPN_NAS_MOUNT:=/Volumes/Nas}"
: "${MYVPN_NAS_USER:=NAS}"
: "${MYVPN_NAS_KEYCHAIN_SERVICE:=local.myvpn.mac.nas}"
: "${MYVPN_LAUNCH_LABEL:=local.myvpn.mac.login}"
: "${MYVPN_PUBLIC_IP_URL:=https://ifconfig.me}"
# System DNS must target TUN so queries enter hijack (LAN DHCP 192.168.3.1 bypasses TUN → Hub 403).
: "${MYVPN_TUN_DNS:=172.19.0.1}"
: "${MYVPN_DNS_SERVICES:=Wi-Fi}"

MYVPN_LIB="${MYVPN_ROOT}/lib"
MYVPN_SHARE="${MYVPN_ROOT}/share"

if [[ -z "${MYVPN_SING_BOX:-}" ]]; then
  if command -v sing-box >/dev/null 2>&1; then
    MYVPN_SING_BOX="$(command -v sing-box)"
  elif [[ -x /opt/homebrew/bin/sing-box ]]; then
    MYVPN_SING_BOX=/opt/homebrew/bin/sing-box
  else
    MYVPN_SING_BOX=sing-box
  fi
fi
