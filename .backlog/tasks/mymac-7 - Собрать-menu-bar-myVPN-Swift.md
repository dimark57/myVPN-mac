---
id: MYMAC-7
title: Собрать menu bar myVPN (Swift)
status: Done
assignee:
  - '@DEV'
created_date: '2026-09-07 15:02'
updated_date: '2026-09-07 17:32'
labels: []
milestone: m-0
dependencies: []
references:
  - .backlog/docs/specs/doc-4 - Menu-bar-myVPN.md
  - .backlog/docs/specs/doc-4 - Menu-bar-myVPN.md
documentation:
  - doc-4
- doc-4 — Menu bar myVPN
priority: high
type: feature
---
## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Реализовать Swift menu bar по подписанному doc-4: оболочка над ~/.local/bin/myvpn (status/up/down), иконка on/off, без своей маршрутизации и без NE.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Menu bar On/Off вызывает myvpn up/down
- [x] #2 Иконка on при tun=1 из myvpn status
- [x] #3 Quit не гасит ядро
- [x] #4 Секреты WG не читаются в Swift
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 Локально собирается в Xcode и управляет тем же CLI
<!-- DOD:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Создать macos/MyVPN Xcode project (LSUIElement, bundle local.myvpn.mac).
2. CLI-клиент: status/up/down/mount-nas/update-rules → ~/.local/bin/myvpn.
3. Menu: статус, Включить/Выключить, NAS, правила, Выход (без down).
4. Иконка SF Symbol по tun=; poll ~10s.
5. Сборка xcodebuild; README как открыть в Xcode.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Код в macos/MyVPN; xcodebuild Debug BUILD SUCCEEDED (DerivedData локально). Открыть MyVPN.xcodeproj → Run. Ждёт ручной прогон On/Off.

DoD close 2026-09-07: xcodebuild + install-app → ~/Applications/myVPN.app; On/Off через helper.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Menu bar v0.2: CLI wrapper + install. Дальше MYMAC-8 (helper/bundle).
<!-- SECTION:FINAL_SUMMARY:END -->
