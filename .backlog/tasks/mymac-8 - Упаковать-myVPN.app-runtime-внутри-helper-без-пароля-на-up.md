---
id: MYMAC-8
title: 'Упаковать myVPN.app: runtime внутри + helper без пароля на up'
status: Done
assignee:
  - '@DEV'
created_date: '2026-09-07 16:06'
updated_date: '2026-09-07 17:32'
labels: []
milestone: m-0
dependencies: []
references:
  - .backlog/docs/specs/doc-4 - Menu-bar-myVPN.md
  - .backlog/docs/specs/doc-5 - Network-Extension-myVPN.md
documentation:
  - >-
    doc-5 — Network Extension myVPN (цель без admin; v0 = privileged helper до
    Developer ID)
priority: high
type: feature
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Упаковать ядро в приложение и убрать admin на каждый up без полного NE (нет Developer ID).
Helper LaunchDaemon + socket; menu bar — единственный login item.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Runtime CLI внутри myVPN.app/Contents/Resources (не /Volumes/Nas и не обязательный ~/.local/share для UI)
- [x] #2 Автозапуск = SMAppService login item myVPN.app; старый LaunchAgent zsh снят
- [x] #3 Privileged helper: после одной установки On/Off без admin-пароля
- [x] #4 В фоновых объектах — myVPN, не отдельный bash/python login-boot
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. admin.zsh: при uid=0 без osascript.
2. Helper LaunchDaemon + socket; install/uninstall из app.
3. Bundle runtime в Resources; CLI пути из бандла.
4. SMAppService login item; снять local.myvpn.mac.login.
5. install-app.zsh + rebuild.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Собрано: runtime в ~/Applications/myVPN.app/Contents/Resources/runtime; helper LaunchDaemon local.myvpn.mac.helper; legacy LaunchAgent zsh снят. Helper установлен на этой машине (socket ok, ping ready). Нужен ручной QA: On/Off без пароля, Login Item myVPN, auto-NAS.

QA close 2026-09-07: verified runtime libs in ~/Applications/myVPN.app; helper socket ready; sfltool shows myVPN login item; no ~/Library/LaunchAgents myvpn; AC #1–#4 checked.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Runtime в app, Login Item myVPN.app, helper без пароля на On/Off, нет zsh LaunchAgent. QA: helper=1, status tun/macbook/home/nas=1 на машине владельца.
<!-- SECTION:FINAL_SUMMARY:END -->
