---
id: MYMAC-11
title: 'FDIR 0.5.20: независимый heal Connection и Shares'
status: QA
assignee:
  - '@DEV'
created_date: '2026-09-11 07:40'
updated_date: '2026-09-11 07:42'
labels: []
dependencies: []
references:
  - .backlog/docs/specs/doc-12 - FDIR-0.5.19-doctor-не-ломает-живое.md
documentation:
  - >-
    .backlog/docs/specs/doc-13 -
    FDIR-0.5.20-Connection-и-Shares-независимый-heal.md
priority: high
type: bug
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Постановщик: @CEO (чат: остаточный риск 0.5.19).

## Зачем
Heal home не должен валить живой интернет/SMB. Wake/--safe не должен umount при открытых файлах.

## As-is → To-be
**As-is:** HOME_* = restartAndMount; --safe сначала graceful unmount.
**To-be:** HOME_DOWN_MACBOOK_OK = mount only; HOME_PEER_DOWN = restart + follow-up; busy before unmount.

SoT: doc-13.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 HOME_DOWN_MACBOOK_OK → mount-nas --safe, never down→up
- [x] #2 HOME_PEER_DOWN → restart only; follow-up mount if nas=0
- [x] #3 SLEEP_WAKE_STALE healKind = restart (NAS = WakeRecover)
- [x] #4 --safe busy-check before any unmount; exit 2 = skip=busy not throw
- [x] #5 fdir-policy T23–T34 PASS
- [x] #6 dual-WG / render_config / NE not touched
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 doc-13 SoT; T28–T34 green
- [ ] #2 живой egress не рвётся ради HOME_DOWN_MACBOOK_OK
- [ ] #3 open files на NAS → нет auto umount
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Код: AutoDoctor healKind, pipeline follow-up HOME_PEER, nas.zsh busy-before-unmount, MyVPNCLI skip=busy. fdir-policy PASS (T23–T34). Версию/ship не бампал — 0.5.20 через cd/ship.zsh когда скажешь.
<!-- SECTION:NOTES:END -->
