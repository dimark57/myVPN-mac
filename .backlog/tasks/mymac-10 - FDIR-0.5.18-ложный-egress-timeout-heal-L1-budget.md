---
id: MYMAC-10
title: 'FDIR 0.5.18: ложный egress, timeout-heal, L1 budget'
status: To Do
assignee:
  - '@MYMAC'
  - '@CEO'
created_date: '2026-09-10 05:48'
updated_date: '2026-09-10 05:55'
labels: []
dependencies:
  - DRAFT-2
references:
  - >-
    /srv/nas/Project/myVPN-mac/.backlog/docs/specs/doc-11 -
    FDIR-0.5.18-ложный-egress-timeout-heal-L1-budget.md
  - >-
    /Volumes/Nas/Project/myVPN-mac/.backlog/docs/specs/doc-11 -
    FDIR-0.5.18-ложный-egress-timeout-heal-L1-budget.md
  - >-
    /srv/nas/Project/myVPN-mac/.backlog/docs/specs/doc-10 -
    FDIR-автодоктор-DesiredState-L1-L2.md
  - >-
    /srv/nas/Project/myVPN-mac/.backlog/docs/specs/doc-11 -
    FDIR-0.5.18-ложный-egress-timeout-heal-L1-budget.md
  - >-
    /srv/nas/Project/myVPN-mac/.backlog/docs/specs/doc-9 -
    Автодоктор-таксономия-отвалов-и-heal.md
documentation:
  - doc-11
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Постановщик: @CEO

## Зачем
Прод 0.5.17 ловит зомби UDP (EISCONN) через пустой ifconfig.me — и тем же детектором рвёт живой overlay (10:15: ICMP+DNS PASS). Doctor timeout при красном L0 не heal'ит (дыра 07:22–09:34). Нужен патч 0.5.18, который **не** добавит ложных restart.

## As-is → To-be
**As-is:** 2 пустых curl → hard DROP при macbook=1; L1 `pub empty` → MACBOOK_EGRESS_DOWN → down→up+mount; timeout doctor → notify, heal нет; DispatchTime спит с крышкой.
**To-be:** clear_cached только `empty IP ∧ !macbook` два тика подряд; L1 false-alarm если DNS/ICMP overlay жив; timeout + L0 красный → `.restart` без mount; kill process group + wall deadline; wake abort in-flight doctor.

SoT: **doc-11 — FDIR 0.5.18: ложный egress, timeout-heal, L1 budget**. Исследование в спеке §1 — второй HTTP на L0 запрещён.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 attached chat
- [x] #2 passed Draft
- [x] #3 Research done
- [x] #4 Spec done
- [ ] #5 Spec signed
- [ ] #6 Build done
- [ ] #7 QA done
- [ ] #8 Delivery done
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 doc-11 подписан; T9–T19 зелёные
- [ ] #2 прод: нет DROP при живом ICMP+DNS (сценарий 10:15)
- [ ] #3 прод: timeout doctor не оставляет overlay мёртвым до wake (сценарий 07:22)
- [ ] #4 dual-WG / NE / sing-box UDP не тронуты
<!-- DOD:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Спека doc-11 (research+anti-worsen) → подпись CEO → код строго §9 → fdir-policy T9–T19 → ship 0.5.18 через cd/ship.zsh.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Критерии (наблюдаемые, T9–T22 в doc-11 §9):
- T9: macbook=1 + пустой ifconfig.me → нет DROP egress
- T10: macbook=0 + 2 empty → clear_cached → DROP
- T11: L1 HEALTHY_EGRESS_PROBE_FALSE_ALARM, нет AUTO_HEAL
- T12: реальный EGRESS_DOWN → down→up без mount
- T13: doctor timeout + L0 красный → AUTO_HEAL down→up
- T14: timeout + L0 зелёный → soft, без restart
- T15: wake во время doctor — kill, CONFIRM reset, один WAKE_HEAL
- T16: потомки ping/curl мертвы после timeout
- T17: follow-up mount только если nas=0
- T18: watchdog 1× на cid
- T19: T5–T8 doc-10 без регресса
- T20: DROP «нет интернета через VPN» → channels=egress (не tun)
- T21: INCIDENT end + outcome + recovery_ms; heal не null
- T22: flight pub_empty=1 при пустом probe + skip=peer_up

Anti-worsen: нет второго HTTP на poll 16с; нет clear_cached при macbook=1; нет снижения CONFIRM/grace/cooldown.

```json
{
  "packet": "agent_packet",
  "title": "FDIR 0.5.18: ложный egress, timeout-heal, L1 budget",
  "description": "Патч FDIR: AND overlay ICMP с пустым pub-IP; timeout doctor при красном L0 → restart без mount; kill process group. Не новый HTTP-probe.",
  "plan": "Спека doc-11 → подпись → код строго по anti-worsen §9 → tests/fdir-policy T9–T19 → ship 0.5.18.",
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
    "doc-11 подписан, T9–T19 зелёные",
    "прод: нет DROP при живом ICMP+DNS",
    "прод: timeout doctor не оставляет overlay мёртвым до wake",
    "dual-WG / NE не тронуты"
  ],
  "requester": "@CEO",
  "assignee": "@MYMAC",
  "out_of_scope": [
    "sing-box gVisor UDP reconnect",
    "замена ifconfig.me на Cloudflare trace на L0",
    "CONFIRM <20с / streak <2",
    "Network Extension"
  ]
}
```
<!-- SECTION:NOTES:END -->
