---
id: MYMAC-6
title: Собрать CLI myvpn (sing-box ядро)
status: Done
assignee:
  - '@DEV'
created_date: '2026-09-07 13:39'
updated_date: '2026-09-07 14:30'
labels:
  - 'model:free'
milestone: m-0
dependencies: []
references:
  - /srv/nas/Project/myVPN-mac/.backlog/artifacts/MYMAC-6/test-report.md
documentation:
  - doc-2
  - doc-6
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Реализовать CLI по подписанным **doc-2 — Ядро sing-box и CLI myvpn** и **doc-6 — Тестирование CLI myvpn**.

Команды: up down status update-rules mount-nas install-autostart.
Не рвать текущий VPN из чата без cycle+restore.

Постановщик: CEO
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 attached chat
- [x] #2 passed Draft
- [x] #3 Research done
- [x] #4 Spec done
- [x] #5 Spec signed
- [x] #6 Build done
- [x] #7 QA done
- [x] #8 Delivery done
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 Статика S* зелёная; код в репо; live C* — через cycle человеком
<!-- DOD:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Scaffold bin/lib/share/tests
2. Parse WG conf → sing-box JSON (endpoints)
3. CLI process + admin
4. update-rules, mount-nas, LaunchAgent
5. Static checks; cycle script for human live test
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Критерии:
- CLI установлен в ~/.local/bin/myvpn
- Keychain NAS не в git
- Агент не делает up без cycle

Критерии:
- sing-box JSON из фикстур проходит check
- нет networksetup -setdnsservers в коде

Build (без live up из чата):
- sing-box 1.14 установлен
- CLI: bin/myvpn + lib/* + LaunchAgent
- ~/.local/bin/myvpn, update-rules → ~/.config/myvpn/rules
- tests/static-check.zsh OVERALL PASS
- tests/cycle-myvpn.zsh готов для человека (рвёт VPN → restore WireGuard.app)

Ждёт человека: /bin/zsh tests/cycle-myvpn.zsh и отчёт ~/.cache/myvpn-cycle/latest.txt

Live cycle OVERALL PASS (report-20260907-191710). Runtime ~/.local/share/myvpn; start_singbox detach; nas Keychain mount; Hub --resolve. Artifact: .backlog/artifacts/MYMAC-6/test-report.md

Hub/«Проекты»: macOS getaddrinfo шёл на 94… (LAN DHCP/DoH мимо hijack). Fix: DNS Wi-Fi/USB → TUN 172.19.0.1 на up, Empty на down; cycle checks getaddrinfo. Safari Web App «Проекты» ещё и с кривым start_url — брать myThings.app.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CLI myvpn (sing-box) собран, статика и live cycle PASS. Дальше — Alfred gv по doc-3 (Utilits).
<!-- SECTION:FINAL_SUMMARY:END -->
