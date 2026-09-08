---
id: DRAFT-2
title: Auto-doctor + auto-heal при отвале каналов
status: Draft
assignee:
  - '@MYMAC'
created_date: '2026-09-08 08:22'
labels: []
dependencies: []
documentation:
  - doc-4
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Постановщик: @CEO

## Зачем
Диагностика сейчас только по запросу. При отвале (как сегодняшний MACBOOK_EGRESS_DOWN) человек узнаёт из нотификации DropLogger и сам жмёт «Диагностика» / down-up. Нужен след в журнале и автовосстановление.

## As-is → To-be
**As-is:** `DropLogger.observe` пишет DIFF в `drops.log`, нотификация «… Жми Диагностика». Doctor — только меню/⌘.
**To-be:** на значимый drop (1→0) app сам: (1) `myvpn doctor` → полный отчёт в `~/.cache/myvpn-doctor/`; (2) при FAIL-вердикте по каналам — один auto-heal (`down`→`up`) с cooldown; (3) результат в журнал + нотификация.

## MVP
Только путь DropLogger (живость каналов/tun/nas), не crash dump процесса.
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
- [ ] #1 На drop пишется полный doctor-отчёт без ручного клика
- [ ] #2 При FAIL каналов выполняется один auto-heal с cooldown; след в drops.log
- [ ] #3 doc-4 обновлён; ручной doctor без регресса
<!-- DOD:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1) Триггер на существующий drop в DropLogger/AppDelegate. 2) Фоновый doctor → report в кэш. 3) При PRIMARY FAIL — heal down/up + cooldown/флаг. 4) Логи AUTO_* + notify. 5) Правка doc-4.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Критерии:
- При 1→0 (tun/home/macbook/nas) app сам гоняет `myvpn doctor` и пишет полный отчёт в `~/.cache/myvpn-doctor/` (как ручная диагностика).
- После doctor (fail с PRIMARY вроде MACBOOK_EGRESS_DOWN / TUN_DOWN / HOME_*) — один авто-heal: down→up (или эквивалент CLI), без пароля если helper есть.
- Cooldown ≥5 мин между auto-heal; в drops.log / отчёте есть строки AUTO_DOCTOR / AUTO_HEAL + результат.
- Нотификация: «диагностика + попытка восстановления» вместо «Жми Диагностика».
- Ручная «Провести диагностику» не ломается.

```json
{
  "packet": "agent_packet",
  "title": "Auto-doctor + auto-heal при отвале каналов",
  "description": "Сейчас DropLogger только DIFF+notify «Жми Диагностика». Нужен автозапуск doctor в журнал и автоматическое восстановление (down/up) без человека.",
  "plan": "Расширить DropLogger/AppDelegate: на drop → doctor → при FAIL heal с cooldown; логировать в drops.log и doctor report; обновить doc-4.",
  "acceptance_criteria": [
    "attached chat",
    "passed Draft",
    "Research done",
    "Spec done",
    "Spec signed",
    "Build done",
    "QA done",
    "Delivery done"
  ],
  "definition_of_done": [
    "AC этапы закрыты",
    "verify-doc / спека menu bar отражает поведение",
    "ручной doctor и menu не регрессируют"
  ],
  "requester": "@CEO",
  "assignee": "@MYMAC",
  "out_of_scope": [
    "crash reporter / ExcUserFault при падении процесса myVPN.app",
    "авто-heal при CONFLICT_WG_APP",
    "бесконечный retry без backoff",
    "отправка Issues на GitHub без кнопки пользователя"
  ],
  "refs": [
    "/Volumes/Nas/Project/myVPN-mac/.backlog/docs/specs/doc-4 - Menu-bar-myVPN.md",
    "/Volumes/Nas/Project/myVPN-mac/macos/MyVPN/MyVPN/DropLogger.swift",
    "/Volumes/Nas/Project/myVPN-mac/lib/doctor.zsh",
    "/Users/dmitrijstolarov/.cache/myvpn-doctor/latest.txt"
  ],
  "dod_testcase": [
    {
      "id": "T1",
      "step": "Симулировать macbook 1→0 (или реальный отвал egress)",
      "where": "menu bar + ~/.cache/myvpn-doctor/",
      "pass": "появился новый report-*.txt с AUTO, drops.log содержит AUTO_DOCTOR"
    },
    {
      "id": "T2",
      "step": "После AUTO_DOCTOR FAIL дождаться heal",
      "where": "CLI status / ifconfig.me / notify",
      "pass": "down→up выполнен один раз; при успехе egress снова есть; повторный heal не чаще cooldown"
    },
    {
      "id": "T3",
      "step": "Ручная Провести диагностику",
      "where": "меню / Настройки→Диагностика",
      "pass": "как раньше, отчёт в latest.txt"
    }
  ]
}
```
<!-- SECTION:NOTES:END -->
