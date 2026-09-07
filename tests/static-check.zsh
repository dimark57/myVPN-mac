#!/bin/zsh
# Static checks for myvpn (doc-6 subset). Exit ≠0 on failure.
set -uo pipefail
ROOT="$(cd "${0:A:h}/.." && pwd)"
fail=0
ok() { print -r -- "PASS $1"; }
bad() { print -r -- "FAIL $1 — $2" >&2; fail=1; }

if command -v rg >/dev/null 2>&1; then
  if rg -n --glob '!*.md' 'wg-quick|route -n monitor' "$ROOT/bin" "$ROOT/lib" >/dev/null 2>&1; then
    bad S4 "wg-quick or route monitor found in bin/lib"
  else
    ok S4
  fi
else
  bad tool "rg required"
fi

if rg -n 'MYVPN_DNS_SERVICES|myvpn_dns_apply_tun|myvpn_dns_clear' "$ROOT/lib/process.zsh" "$ROOT/lib/env.zsh" >/dev/null; then
  ok S3
else
  bad S3 "TUN DNS allowlist helpers missing"
fi

if git -C "$ROOT" ls-files '*.conf' 2>/dev/null | rg -q .; then
  bad S5 "tracked .conf files"
else
  ok S5
fi

# Password must come from Keychain / env at runtime — never a hardcoded secret string in lib.
if rg -n 'add-generic-password.*-w [^"$]' "$ROOT/lib" >/dev/null 2>&1; then
  bad S20 "hardcoded keychain password?"
else
  ok S20
fi

for f in nas.zsh parse_conf.py render_config.py update_rules.py process.zsh env.zsh admin.zsh; do
  if [[ -f "$ROOT/lib/$f" ]]; then
    ok "lib/$f"
  else
    bad "lib/$f" "missing"
  fi
done

for f in "doc-3 - Контракт-CLI-для-Alfred-gv.md" "doc-4 - Menu-bar-myVPN.md"; do
  if [[ -f "$ROOT/.backlog/docs/specs/$f" ]]; then
    ok "spec/$f"
  else
    bad "spec/$f" "missing"
  fi
done

if [[ -f "$ROOT/.gitignore" ]] && rg -q 'DerivedData' "$ROOT/.gitignore"; then
  ok gitignore-DerivedData
else
  bad gitignore "DerivedData not ignored"
fi

exit "$fail"
