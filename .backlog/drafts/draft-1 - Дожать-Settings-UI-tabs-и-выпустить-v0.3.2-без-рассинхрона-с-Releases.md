---
id: DRAFT-1
title: Дожать Settings UI (tabs) и выпустить v0.3.2 без рассинхрона с Releases
status: Draft
assignee:
  - DEV
created_date: '2026-09-08 07:35'
labels: []
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Context
После v0.3.1 в working tree остался WIP: меню «Настройки…» без submenu, вкладки System Helper / Channels / Routes / Shares / Update; правки README, doc-4, doc-8, AppDelegate, ConnectionSettingsWindowController. Не закоммичено, не в Release. Локальный app = v0.3.1; WIP в коде впереди.

## Goal
1. Довести/проверить Settings UI (сборка).
2. Commit + push.
3. macos/MyVPN/release.zsh 0.3.2 — local binary == release.
4. git status clean после релиза.

## Out of scope
Developer ID / NE / public visibility репо.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 attached chat
- [ ] #2 passed Draft
- [ ] #3 Research done
- [ ] #4 Spec done
- [ ] #5 Spec signed
- [ ] #6 Build done
- [ ] #7 QA done
- [ ] #8 Delivery done
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Release v0.3.2; clean tree; обновление только кнопкой
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
session-close 2026-09-08; до WIP: 8fc2385; Latest: v0.3.1; decision-1

Критерии:
- - [ ] Settings UI собирается; меню Настройки… / Справка согласованы
- [ ] Dirty files в origin/main
- [ ] GitHub Release v0.3.2; sha local == release
- [ ] README/doc-8: Настройки → Update
<!-- SECTION:NOTES:END -->
