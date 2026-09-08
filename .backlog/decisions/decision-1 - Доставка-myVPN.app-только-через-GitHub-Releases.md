---
id: decision-1
title: Доставка myVPN.app только через GitHub Releases
date: '2026-09-08 07:35'
status: accepted
---
## Context

Раньше агент катил фиксы через install-app.zsh в ~/Applications; Release отставал → кнопка обновления могла откатить. Пользователь: прекратить править напрямую.

## Decision

Прод-доставка только release.zsh → GitHub Releases → кнопка Проверить обновление (Настройки → Update). install-app.zsh не способ доставки на Mac владельца; допустим только внутри release.zsh или по явной просьбе «собери локально».

## Consequences

После каждого смыслового фикса — bump + Release, иначе local≠GitHub. Doc: AGENTS.md, CONTRIBUTING.md, doc-8.
