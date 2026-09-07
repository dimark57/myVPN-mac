# myVPN-mac — AGENTS

Prefix: `MYMAC` · Role: personal · Contour: `/srv/nas/Project/myVPN-mac/`  
Mac: `/Volumes/Nas/Project/myVPN-mac/`

Клиент split-tunnel на macOS (sing-box + два WG). **Не** продукт you2vpn (`/Project/myVPN`, prefix `BACK`).

## Документация

`.backlog/docs/` — спеки. Канон MVP: `.backlog/docs/specs/doc-1 - Mac-клиент-split-tunnel-создание.md`

## Задачи

`MYMAC-*` — `backlog task list`. Create всегда Draft.

## Навыки

Территория: `/srv/nas/Project/mySkills/skills/`  
Mac: `/Volumes/Nas/Project/mySkills/skills/`  
Не копировать навыки в дом.

## Секреты

Не коммитить `*.conf` с ключами, не класть WG-ключи в чат. Локально: `~/.config/wireguard/` или `~/.config/myvpn/`.

## Alfred

Keyword `gv` живёт в **Utilits**. Этот репо — ядро/CLI; связка — отдельная задача после `myvpn` CLI.
