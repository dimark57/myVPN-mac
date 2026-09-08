# Shared paths for myvpn. Expects MYVPN_ROOT set by bin/myvpn before source.
# Topology (LAN/NAS/DNS) comes from ~/.config/myvpn/settings.json — see lib/settings.py.

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
: "${MYVPN_SETTINGS_JSON:=${MYVPN_HOME}/settings.json}"
: "${MYVPN_LAUNCH_LABEL:=local.myvpn.mac.login}"
: "${MYVPN_PUBLIC_IP_URL:=https://ifconfig.me}"
: "${MYVPN_TUN_DNS:=172.19.0.1}"
: "${MYVPN_DNS_SERVICES:=Wi-Fi}"
: "${MYVPN_NAS_KEYCHAIN_SERVICE:=local.myvpn.mac.nas}"

# Optional env overrides; prefer settings.json via lib/settings.py at render time.
: "${MYVPN_NAS_HOST:=}"
: "${MYVPN_NAS_SHARE:=Nas}"
: "${MYVPN_NAS_MOUNT:=/Volumes/Nas}"
: "${MYVPN_NAS_USER:=NAS}"

MYVPN_LIB="${MYVPN_ROOT}/lib"
MYVPN_SHARE="${MYVPN_ROOT}/share"

# Load NAS_* from settings.json when present (no secrets).
if [[ -f "${MYVPN_SETTINGS_JSON}" ]]; then
  eval "$(
    /usr/bin/python3 - "${MYVPN_SETTINGS_JSON}" <<'PY'
import json, sys
p = sys.argv[1]
try:
    d = json.load(open(p, encoding="utf-8"))
except Exception:
    raise SystemExit(0)
def esc(s):
    return str(s).replace("'", "'\\''")
for k, env in (
    ("nas_host", "MYVPN_NAS_HOST"),
    ("nas_share", "MYVPN_NAS_SHARE"),
    ("nas_mount", "MYVPN_NAS_MOUNT"),
    ("nas_user", "MYVPN_NAS_USER"),
):
    v = d.get(k)
    if v:
        print(f"export {env}='{esc(v)}'")
PY
  )" 2>/dev/null || true
fi

if [[ -z "${MYVPN_SING_BOX:-}" ]]; then
  if [[ -x /opt/homebrew/bin/sing-box ]]; then
    MYVPN_SING_BOX=/opt/homebrew/bin/sing-box
  elif [[ -x /usr/local/bin/sing-box ]]; then
    MYVPN_SING_BOX=/usr/local/bin/sing-box
  else
    MYVPN_SING_BOX=sing-box
  fi
fi
