---
id: MYMAC-9
title: 'UX обновления списков RU: прогресс и результат'
status: Done
assignee:
  - '@DEV'
created_date: '2026-09-07 16:23'
updated_date: '2026-09-07 17:32'
labels: []
milestone: m-0
dependencies: []
documentation:
  - >-
    /srv/nas/Project/myVPN-mac/.backlog/docs/specs/doc-7 -
    UX-обновления-списков-RU-в-menu-bar.md
  - doc-7 — UX обновления списков RU в menu bar
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Постановщик: @CEO

Сделать понятным обновление списков RU в menu bar myVPN по **doc-7 — UX обновления списков RU в menu bar**.

As-is: раньше весь busy глушил меню; успех update-rules молчал. Частично уже есть per-key busy + точки в AppDelegate.

To-be (решения CEO):
- меню не глушить (disabled только текущий пункт);
- прогресс точками `.` → `..` → `...` → `..`;
- два списка geosite-ru / geoip-ru + last-updated в покое;
- явный успех/ошибка.

Результат: пользователь без догадок понимает ход и итог обновления списков RU.

Не входит: клон Happ, отдельное окно, NE, новые источники сверх doc-2.
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
- [x] #1 При обновлении списков RU пользователь видит прогресс и итог без догадок
- [x] #2 dod_testcase U1–U4 пройдены на QA
<!-- DOD:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. doc-7 написан — подпись CEO (webauthn).
2. Promote после Spec signed.
3. Build: info-строки двух списков + mtime; notify на успех update-rules; точки in-place без global mute (сверить с doc-7).
4. QA по dod_testcase U1–U4.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Критерии:
- Прогресс точками на пункте «Обновить списки RU…»; меню не серое целиком.
- В покое видны geosite-ru и geoip-ru + даты (или «нет»).
- Успех — явное уведомление/обновление дат; ошибка — понятное сообщение.

Решения CEO (2026-09-07): не глушить меню; прогресс `.`/`..`/`...`/`..`; не окно Happ. Спека: doc-7.

Пробелы к коду: last-updated строк + notify на успех update-rules (точки/per-key busy уже частично есть).

```json
{
  "packet": "agent_packet",
  "title": "UX обновления списков RU: прогресс и результат",
  "description": "По doc-7: точки, не mute меню, два списка, успех/ошибка, last-updated.",
  "plan": "Подпись doc-7 → promote → build пробелов → QA",
  "acceptance_criteria": ["attached chat","passed Draft","Research done","Spec done","Spec signed","Build done","QA done","Delivery done"],
  "definition_of_done": ["Прогресс и итог без догадок","dod_testcase U1–U4 на QA"],
  "requester": "@CEO",
  "assignee": "@DEV",
  "out_of_scope": ["Клон Happ","NE","Новые источники сверх doc-2","Отдельный progress-bar widget"],
  "refs": [
    {"role":"spec","path":"/srv/nas/Project/myVPN-mac/.backlog/docs/specs/doc-7 - UX-обновления-списков-RU-в-menu-bar.md","doc":"doc-7 — UX обновления списков RU в menu bar"},
    {"role":"spec","path":"/srv/nas/Project/myVPN-mac/.backlog/docs/specs/doc-2 - Ядро-sing-box-и-CLI-myvpn.md","doc":"doc-2 — Ядро sing-box и CLI myvpn"}
  ],
  "dod_testcase": [
    {"id":"U1","step":"Обновить списки RU","where":"menu bar","pass":"Точки на пункте; остальное меню живо"},
    {"id":"U2","step":"Успешное окончание","where":"notify/menu","pass":"Явный успех + даты"},
    {"id":"U3","step":"Меню в покое","where":"menu bar","pass":"geosite-ru и geoip-ru видны"},
    {"id":"U4","step":"Сбой сети","where":"menu bar","pass":"Ошибка, busy снят"}
  ]
}
```

CEO: реализуй 2026-09-07T16:34Z. verify-doc doc-7 valid. Claim @DEV sole.

Build (2026-09-07):
- RulesStatus.swift: mtime geosite-ru / geoip-ru из ~/.config/myvpn/rules
- Menu: info-строки + «Обновлено»; точки . .. ... .. уже были (per-key busy)
- update-rules success → notify «Списки RU обновлены · …»
- xcodebuild Debug+Release SUCCEEDED; install → ~/Applications/myVPN.app
Ждёт ручной QA: U1–U4 (doc-7 / dod_testcase).

QA feedback CEO: убрать троеточие; оповещение работы (notify старт/итог); меню не закрывать на клик.
Сделано: dots removed; «— выполняется» + UNNotification; reopen menu via performClick после клика и после завершения.

CEO: меню не закрывать по клику (только mouse leave); не reopen. StickyMenuItemView + cancelTracking on exit; notify без точек.

QA close 2026-09-07: doc-7 синхронизирован с решением CEO (без точек). Код: actionTitle выполняется, RulesStatus lines, notify success/error, StickyMenuItemView.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
UX: «— выполняется» + notify; geosite/geoip mtime; sticky menu; U1–U4 закрыты по коду и ручному фидбеку CEO.
<!-- SECTION:FINAL_SUMMARY:END -->
