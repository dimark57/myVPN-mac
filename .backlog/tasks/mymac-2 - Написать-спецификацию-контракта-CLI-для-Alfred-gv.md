---
id: MYMAC-2
title: Написать спецификацию контракта CLI для Alfred gv
status: Done
assignee:
  - '@DEV'
  - '@CEO'
created_date: '2026-09-07 12:56'
updated_date: '2026-09-07 14:32'
labels: []
milestone: m-0
dependencies: []
documentation:
  - doc-3
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Довести до подписи **doc-3 — Контракт CLI для Alfred gv**: что вызывает keyword gv.

Код Alfred/Utilits в этой карточке не пишем (другой дом, нет в registry как myvpn-mac). Нужен только контракт stdout/exit.

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
- [x] #1 doc-3 описывает вызовы gv без кода Utilits; нюансы формата status явные
<!-- DOD:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Опереться на подписанный/стабильный doc-2.
Зафиксировать команды status/up/down и формат status.
Не проектировать workflow Alfred.
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
    "реализация Alfred",
    "wg-quick",
    "menu bar"
  ],
  "refs": [
    {
      "role": "spec",
      "path": "/srv/nas/Project/myVPN-mac/.backlog/docs/specs",
      "doc": "doc-3 — Контракт CLI для Alfred gv"
    }
  ],
  "dod_testcase": "человек читает спеку и понимает границу этапа",
  "title": "Написать спецификацию контракта CLI для Alfred gv",
  "description": "Довести doc-3",
  "plan": "контракт команд; не код Utilits"
}
```

Критерии:
- спека doc-3 задаёт команды и ожидания exit/stdout для gv

doc-3 обновлён под реальный myvpn status (tun/macbook/home/nas/ip) и замену brew-up/down. Старая .sig недействительна — нужна повторная подпись CEO.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
doc-3 подписан (status tun/macbook/home/nas/ip; gv → ~/.local/bin/myvpn). Реализация Alfred — в Utilits.
<!-- SECTION:FINAL_SUMMARY:END -->
