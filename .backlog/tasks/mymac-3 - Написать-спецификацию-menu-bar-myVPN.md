---
id: MYMAC-3
title: Написать спецификацию menu bar myVPN
status: Done
assignee:
  - '@DEV'
  - '@CEO'
created_date: '2026-09-07 12:56'
updated_date: '2026-09-07 14:49'
labels: []
milestone: m-0
dependencies: []
documentation:
  - doc-4
priority: medium
references:
  - .backlog/docs/specs/doc-4 - Menu-bar-myVPN.md
---
## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Довести до подписи **doc-4 — Menu bar myVPN**: оболочка над CLI, без своей маршрутизации.

Не строить Swift в этой карточке. Нужен понятный этап после v0 CLI.

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
- [x] #1 doc-4 понятен как следующий этап после CLI; не смешивает NE
<!-- DOD:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Сверить doc-1/doc-2/doc-3 и фактический CLI (status, admin, runtime).
2. Расписать doc-4: граница, меню, контракт вызовов, иконка, привилегии, автозапуск, приёмка.
3. Явно развести с doc-5 (NE) и Utilits gv.
4. Отдать CEO на webauthn-подпись.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
```json
{
  "packet": "agent_packet",
  "requester": "CEO",
  "assignee": "@DEV",
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
    "спека в .backlog/docs/specs, этап понятен без чата"
  ],
  "out_of_scope": [
    "Network Extension",
    "App Store",
    "код сейчас"
  ],
  "refs": [
    {
      "role": "spec",
      "path": ".backlog/docs/specs",
      "doc": "doc-4 — Menu bar myVPN"
    }
  ],
  "dod_testcase": "человек читает спеку и понимает границу этапа",
  "title": "Написать спецификацию menu bar myVPN",
  "description": "Довести doc-4",
  "plan": "UI над CLI; нюансы sudo списком"
}
```

Критерии:
- спека doc-4 задаёт menu bar как оболочку над тем же ядром

doc-4 переписан: оболочка над ~/.local/bin/myvpn; меню On/Off/status; без NE/sudoers; admin на up как у CLI; helper опционален. Ждёт webauthn CEO.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
doc-4 signed (menu bar over CLI; no NE/sudoers).
<!-- SECTION:FINAL_SUMMARY:END -->
