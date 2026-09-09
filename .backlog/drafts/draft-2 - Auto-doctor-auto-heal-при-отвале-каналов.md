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
  - doc-9
  - doc-10
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Постановщик: @CEO

## Зачем
Диагностика сейчас только по запросу. При отвале (как сегодняшний MACBOOK_EGRESS_DOWN) человек узнаёт из нотификации DropLogger и сам жмёт «Диагностика» / down-up. Нужен след в журнале и автовосстановление. Каталог кодов/heal — **doc-9 — Автодоктор: таксономия отвалов и heal**.

## As-is → To-be
**As-is:** `DropLogger.observe` пишет DIFF в `drops.log`, нотификация «… Жми Диагностика». Doctor — только меню/⌘.
**To-be:** на значимый drop (1→0) app сам: (1) `myvpn doctor` → полный отчёт в `~/.cache/myvpn-doctor/`; (2) при FAIL-вердикте по каналам — один auto-heal (`down`→`up`) с cooldown; (3) результат в журнал + нотификация. В **Настройки → Диагностика** — две галочки + список кодов отвалов + хвост журнала (doc-9 §6).

## MVP
Только путь DropLogger (живость каналов/tun/nas), не crash dump процесса. Heal по матрице doc-9 §5.
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
- [ ] #4 Настройки→Диагностика: галочки автодиагностики и автовосстановления (persist on/off)
- [ ] #5 UI Диагностики: список кодов отвалов + хвост drops.log по doc-9
<!-- DOD:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1) Спека doc-9 (таксономия) — SoT кодов/heal. 2) Триггер drop → doctor → heal + cooldown. 3) Настройки→Диагностика: 2 галочки + таблица кодов + журнал. 4) Правка doc-4 (ссылка на doc-9). 5) Build/QA.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### FDIR rework → 0.5.0 (2026-09-09)

Delivery MVP auto-doctor/heal для релиза **0.5.0** — **переработка FDIR**, не патч 0.4.x.

- **SoT control plane:** [doc-10 — FDIR: DesiredState, L0/L1/L2, Safe Mode](../docs/specs/doc-10%20-%20FDIR-автодоктор-DesiredState-L1-L2.md) (DesiredState, INTENTIONAL_OFF, wall-clock CONFIRM/grace, Safe Mode, L0/L1/L2, verify, NAS busy, flight/incidents, AC T5–T8).
- **SoT PRIMARY catalog / heal matrix:** по-прежнему **doc-9**; doc-10 supersedes только control-plane секции doc-9.
- Gate: сценарии инцидента 09.09 + T5–T8; ship `release.zsh 0.5.0`.

Критерии (MVP baseline; уточнения — doc-10):
- При 1→0 (tun/home/macbook/nas) app сам гоняет `myvpn doctor` и пишет полный отчёт в `~/.cache/myvpn-doctor/` (как ручная диагностика) — **если галочка «Автодиагностика при отвале» ON**.
- После doctor (fail с PRIMARY вроде MACBOOK_EGRESS_DOWN / TUN_DOWN / HOME_*) — один авто-heal: down→up (или эквивалент CLI), без пароля если helper есть — **если галочка «Автовосстановление» ON** (если doctor OFF — heal тоже OFF / disabled). Матрица: **doc-9 §5**.
- Cooldown ≥5 мин между auto-heal; в drops.log / отчёте есть строки AUTO_DOCTOR / AUTO_HEAL + результат.
- Нотификация: «диагностика + попытка восстановления» вместо «Жми Диагностика».
- Ручная «Провести диагностику» всегда доступна, независимо от галочек.
- **Настройки → Диагностика:** две галочки вкл/выкл, persist; блок кодов отвалов + хвост журнала (doc-9 §6); defaults ON.
- `HEALTHY_ICMP_FALSE_ALARM` / `CONFLICT_WG_APP` — **не** auto-heal.

## Research (2026-09-08)
Индустрия: control vs data plane; DPD≠полезность → overlay probes; consecutive failures + cooldown; WG sleep/NAT keepalive. См. **doc-9**.

## Settings UI (CEO 2026-09-08)
На вкладке Диагностика:
1. ☐ Автодиагностика при отвале
2. ☐ Автовосстановление (down→up после FAIL)
3. Список PRIMARY / heal (из doc-9)
4. Журнал drops + latest report

```json
{
  "packet": "agent_packet",
  "title": "Auto-doctor + auto-heal при отвале каналов",
  "description": "Сейчас DropLogger только DIFF+notify «Жми Диагностика». Нужен автозапуск doctor в журнал и автоматическое восстановление (down/up) без человека.",
  "plan": "DropLogger → doctor → heal + cooldown; Настройки→Диагностика: 2 галочки; doc-4.",
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
    "ручной doctor и menu не регрессируют",
    "галочки автодиагностики/автовосстановления в Настройки→Диагностика"
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
    "/Volumes/Nas/Project/myVPN-mac/macos/MyVPN/MyVPN/ConnectionSettingsWindowController.swift",
    "/Volumes/Nas/Project/myVPN-mac/lib/doctor.zsh",
    "/Users/dmitrijstolarov/.cache/myvpn-doctor/latest.txt"
  ],
  "dod_testcase": [
    {
      "id": "T1",
      "step": "Симулировать macbook 1→0 (или реальный отвал egress) при галочках ON",
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
    },
    {
      "id": "T4",
      "step": "Снять обе галочки, спровоцировать drop",
      "where": "Настройки→Диагностика",
      "pass": "нет AUTO_DOCTOR/AUTO_HEAL; остаётся только DIFF notify или тишина по политике"
    }
  ]
}
```
<!-- SECTION:NOTES:END -->
