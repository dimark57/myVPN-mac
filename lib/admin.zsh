# Admin helper: AppleScript heredoc + ensure_ascii=False.
# When already root (privileged helper), run the command directly — no password dialog.

myvpn_run_admin() {
  local cmd="$1"
  if [[ "$(/usr/bin/id -u)" == "0" ]]; then
    /bin/zsh -c "$cmd"
    return $?
  fi
  /usr/bin/osascript <<EOF
do shell script $(/usr/bin/python3 -c 'import json,sys; print(json.dumps(sys.argv[1], ensure_ascii=False))' "$cmd") with administrator privileges
EOF
}

myvpn_notify() {
  # Menu bar uses UNUserNotificationCenter — skip osascript when invoked from app.
  [[ -n "${MYVPN_QUIET:-}" || -n "${MYVPN_NO_NOTIFY:-}" ]] && return 0
  /usr/bin/osascript <<EOF
display notification $(/usr/bin/python3 -c 'import json,sys; print(json.dumps(sys.argv[1], ensure_ascii=False))' "$1") with title "myVPN"
EOF
}
