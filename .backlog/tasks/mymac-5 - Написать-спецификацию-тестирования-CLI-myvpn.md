---
id: MYMAC-5
title: Написать спецификацию тестирования CLI myvpn
status: Done
assignee:
  - '@DEV'
  - '@CEO'
created_date: '2026-09-07 13:00'
updated_date: '2026-09-07 13:47'
labels: []
milestone: m-0
dependencies: []
documentation:
  - doc-6
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Довести до подписи **doc-6 — Тестирование CLI myvpn**.

Учесть поломки текущего gv/wg-quick из чата «Почему macbook+home выключается периодически»: DNS через networksetup, AND-статус двух туннелей, orphan процессы, сон/USB-flap, hairpin 94… и 403 Hub с LAN.

ИИ тестирует всё, что может на этой машине. Человек — только сон, flap, LAN Hub.

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
- [x] #1 doc-6 полный: статика, live, регрессии, отчёт; ИИ не маскирует blocked как pass
<!-- DOD:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Опереться на doc-2 и регрессии gv. Разделить кейсы ИИ/человек. Не писать код тестов в этой карточке.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
```json
{
  "packet": "agent_packet",
  "title": "Написать спецификацию тестирования CLI myvpn",
  "description": "Довести doc-6: ИИ гоняет всё возможное, человек — сон/флап/Hub 403",
  "plan": "сверить с регрессиями gv; разделить AI/human; отчёт artifacts",
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
    "doc-6 покрывает статику, живую машину, регрессии gv, отчёт"
  ],
  "requester": "CEO",
  "assignee": "@DEV",
  "out_of_scope": [
    "писать код тестов в этой карточке",
    "Alfred UI тесты до doc-3"
  ],
  "refs": [
    {
      "role": "spec",
      "path": "/srv/nas/Project/myVPN-mac/.backlog/docs/specs",
      "doc": "doc-6 — Тестирование CLI myvpn"
    }
  ],
  "dod_testcase": "по таблице ID видно кто гоняет и что blocked ≠ pass"
}
```

Критерии:
- у каждого кейса есть ID и кто гоняет (ИИ или человек)

Спека подписана (webauthn). Текст в docs/specs. Карточка закрыта — стройка в MYMAC-6.
<!-- SECTION:NOTES:END -->
