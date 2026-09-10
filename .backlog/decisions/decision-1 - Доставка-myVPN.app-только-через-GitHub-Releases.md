---
id: decision-1
title: Доставка myVPN.app только через GitHub Releases
date: '2026-09-08 07:35'
status: accepted
---
## Context

Раньше агент катил фиксы через install-app.zsh в ~/Applications; Release отставал → кнопка обновления могла откатить. Пользователь: прекратить править напрямую.

## Decision

Прод-доставка только `release.zsh` → `build-app.zsh` (stage) → GitHub Releases → Update / zip.  
`install-app.zsh` **отключён** (exit 1). Копирование в `~/Applications` из stage/DerivedData запрещено.

## Consequences

После каждого смыслового фикса — bump + Release, иначе local≠GitHub. Doc: AGENTS.md, CONTRIBUTING.md, doc-8.
