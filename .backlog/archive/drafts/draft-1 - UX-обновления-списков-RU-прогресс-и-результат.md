---
id: DRAFT-1
title: 'UX обновления списков RU: прогресс и результат'
status: Draft
assignee:
  - '@DEV'
  - '@CEO'
created_date: '2026-09-07 16:11'
labels: []
milestone: m-0
dependencies: []
documentation:
  - >-
    /srv/nas/Project/myVPN-mac/.backlog/docs/specs/doc-2 -
    Ядро-sing-box-и-CLI-myvpn.md
  - doc-2 — Ядро sing-box и CLI myvpn
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Постановщик: @CEO

Сделать понятным обновление списков RU в menu bar myVPN.

As-is: пункт «Обновить списки RU…» при клике только выставляет busy (пункты disabled); прогресса нет; при успехе нет уведомления — непонятно, обновилось ли. Фактически два набора: geosite-ru и geoip-ru (ru-routing-dat → ~/.config/myvpn/rules).

To-be: видно, что идёт обновление (прогресс/этапы); какие списки; явный успех или ошибка; в меню — когда обновляли.

Результат: пользователь без догадок понимает ход и итог обновления списков RU.

Не входит: клон Happ, NE, новые источники сверх doc-2.
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
- [ ] #1 При обновлении списков RU пользователь видит прогресс и итог без догадок
- [ ] #2 dod_testcase U1–U4 пройдены на QA
<!-- DOD:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Зафиксировать у CEO: menu/sheet по 2 спискам vs отдельный список «как Happ».
2. CLI update-rules: этапы/прогресс и данные last-updated (mtime/счётчики).
3. Menu bar: индикатор прогресса + итог + строка last-updated в покое.
4. При изменении контракта UI — правка/восстановление doc-4 и подпись.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Критерии:
- Во время «Обновить списки RU» видно, что идёт обновление (индикатор/прогресс), а не только disabled-меню.
- Видно, какие списки обновляются: минимум geosite-ru и geoip-ru (два набора из ru-routing-dat).
- После успеха — явное подтверждение (уведомление или строка в меню) с датой/временем последнего обновления.
- После ошибки — понятное сообщение (как сейчас на fail, без тишины на success).
- В покое в меню видно «когда обновляли» (или «ещё не обновляли»), без необходимости гадать.

Вопрос CEO (до promote): нужен ли отдельный список/окно «как в Happ» (строки источников + прогресс на каждую), или достаточно прогресса в menu bar / компактного sheet по двум спискам?

```json
{
  "packet": "agent_packet",
  "title": "UX обновления списков RU: прогресс и результат",
  "description": "Сделать понятным обновление списков RU в menu bar: прогресс, какие списки, успех/ошибка, дата последнего обновления. Не клонировать Happ.",
  "plan": "Уточнить у CEO глубину UI (menu/sheet vs Happ-list). CLI/update-rules — этапы и дата mtime. Menu bar — прогресс + итог. При необходимости правка doc-4.",
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
    "При обновлении списков RU пользователь видит прогресс и итог без догадок",
    "dod_testcase пройдены на QA"
  ],
  "requester": "@CEO",
  "assignee": "@DEV",
  "out_of_scope": [
    "Клон Happ (подписки, VLESS, магазин серверов, полный UI)",
    "Network Extension",
    "Новые источники списков сверх ru-routing-dat / doc-2",
    "Реклама / Discord / полный geosite Loyalsoldier"
  ],
  "refs": [
    {"role": "spec", "path": "/srv/nas/Project/myVPN-mac/.backlog/docs/specs/doc-2 - Ядро-sing-box-и-CLI-myvpn.md", "doc": "doc-2 — Ядро sing-box и CLI myvpn"},
    {"role": "spec", "path": "/srv/nas/Project/myVPN-mac/.backlog/docs/specs/doc-4 - Menu-bar-myVPN.md.sig", "doc": "doc-4 — Menu bar myVPN (подпись; .md отсутствует)"},
    {"role": "task", "path": "/srv/nas/Project/myVPN-mac/.backlog/tasks/mymac-7 - Собрать-menu-bar-myVPN-Swift.md", "id": "MYMAC-7"},
    {"role": "evidence", "path": "/Volumes/Nas/Project/myVPN-mac/macos/MyVPN/MyVPN/AppDelegate.swift"}
  ],
  "dod_testcase": [
    {"id": "U1", "step": "Нажать «Обновить списки RU»", "where": "menu bar myVPN", "pass": "Виден прогресс/этап (не только disabled)"},
    {"id": "U2", "step": "Дождаться окончания успешного обновления", "where": "menu bar / notification", "pass": "Явный успех + дата обновления"},
    {"id": "U3", "step": "Открыть меню в покое после обновления", "where": "menu bar", "pass": "Видны 2 списка (geosite/geoip) и/или last-updated"},
    {"id": "U4", "step": "Симулировать сбой сети на update-rules", "where": "menu bar", "pass": "Понятная ошибка, меню не зависает в busy"}
  ]
}
```

Intake: Clarity/Refs/Rewrite — skip с причиной: узкий UX-фидбек CEO, факты as-is из AppDelegate (busy без progress/success notify), списки = 2 из doc-2/update_rules.py; язык карточки уже RU.
<!-- SECTION:NOTES:END -->
