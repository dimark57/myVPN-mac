---
id: MYMAC-1
title: Написать спецификацию ядра sing-box и CLI
status: Done
assignee:
  - '@DEV'
  - '@CEO'
created_date: '2026-09-07 12:56'
updated_date: '2026-09-07 13:47'
labels: []
milestone: m-0
dependencies: []
documentation:
  - doc-2
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Довести до подписи **doc-2 — Ядро sing-box и CLI myvpn**: замок исполнителя для v0 (пути, процесс, DNS, ru-routing-dat, контракт CLI).

Источник правды продукта: **doc-1 — Mac-клиент split-tunnel**. Код в этой карточке не пишем.

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
- [x] #1 doc-2 подписан или владелец явно принял текст; этап v0 понятен без чата
<!-- DOD:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Прочитать doc-1 и черновик doc-2.
Закрыть открытые нюансы списком в спеке (не раздувать Happ).
Отдать CEO на подпись. Код не начинать.
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
    "код CLI",
    "Alfred",
    "menu bar",
    "NE",
    "you2vpn"
  ],
  "refs": [
    {
      "role": "spec",
      "path": "/srv/nas/Project/myVPN-mac/.backlog/docs/specs",
      "doc": "doc-2 — Ядро sing-box и CLI myvpn"
    }
  ],
  "dod_testcase": "человек читает спеку и понимает границу этапа",
  "title": "Написать спецификацию ядра sing-box и CLI",
  "description": "Довести doc-2 до подписи",
  "plan": "читать doc-1/doc-2; нюансы списком; подпись CEO"
}
```

Критерии:
- в docs/specs лежит полный текст doc-2 без дыр исполнителя (пути, DNS, списки RU, CLI)

Спека подписана (webauthn). Текст в docs/specs. Карточка закрыта — стройка в MYMAC-6.
<!-- SECTION:NOTES:END -->
