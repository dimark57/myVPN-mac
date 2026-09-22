---
id: MYMAC-4
title: Написать спецификацию Network Extension myVPN
status: Done
assignee:
  - '@DEV'
  - '@CEO'
created_date: '2026-09-07 12:56'
updated_date: '2026-09-07 14:53'
labels: []
milestone: m-0
dependencies: []
documentation:
  - doc-5
priority: medium
references:
  - .backlog/docs/specs/doc-5 - Network-Extension-myVPN.md
---
## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Довести до подписи **doc-5 — Network Extension myVPN**: поздний этап, TUN без постоянного sudo.

Не выбирать entitlements окончательно, если нет данных — оставить в нюансах. Код не пишем.

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
- [x] #1 doc-5 отделяет NE от MVP CLI; зависимость от doc-2/doc-4 явная
<!-- DOD:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
rewrite doc-5 for NE; leave spike open items; await CEO webauthn
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
    "реализация NE сейчас",
    "you2vpn"
  ],
  "refs": [
    {
      "role": "spec",
      "path": ".backlog/docs/specs",
      "doc": "doc-5 — Network Extension myVPN"
    }
  ],
  "dod_testcase": "человек читает спеку и понимает границу этапа",
  "title": "Написать спецификацию Network Extension myVPN",
  "description": "Довести doc-5",
  "plan": "цель NE; нюансы не выдумывать"
}
```

Критерии:
- спека doc-5 описывает поздний этап NE и что не входит

doc-5 rewritten (sing-box-in-NE default, no sudoers, migrate from CLI-TUN, keep doc-3 status). Stale .sig removed — await CEO webauthn.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
doc-5 подписан (NE: TUN без admin после одобрения; без sudoers; ядро sing-box в extension по умолчанию). Milestone m-0 спеки закрыты; стройка menu bar / NE — отдельные задачи.
<!-- SECTION:FINAL_SUMMARY:END -->
