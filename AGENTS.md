# myVPN-mac — AGENTS

Prefix: `MYMAC` · Role: personal → public-ready · Contour: `/Volumes/Nas/Project/myVPN-mac/`  
GitHub: `dimark57/myVPN-mac` (Releases = in-app updates)

Клиент split-tunnel на macOS (sing-box + два WG). **Не** продукт you2vpn (`/Project/myVPN`, prefix `BACK`).

## Документация (два слоя)

| Аудитория | Куда писать |
|-----------|-------------|
| Пользователи приложения | `README.md` только (install / update / configure) |
| Агенты + разработчики | этот файл + `.backlog/docs/specs/` — решения сразу в **doc-8** |

Спеки: doc-1 продукт, doc-2 ядро, doc-3 Alfred, doc-4 menu bar, doc-5 NE, doc-6 тесты, doc-7 RU UX, **doc-8 публичная дистрибуция**.

## Задачи

`MYMAC-*` — `backlog task list`. Create всегда Draft.

## Секреты

- Не коммитить `*.conf` с ключами, не класть WG-ключи в чат.
- Локально: `~/.config/wireguard/{macbook,home}.conf`
- Маршруты/NAS/DNS (без ключей): `~/.config/myvpn/settings.json` (`lib/settings.py`, `AppSettings.swift`)
- Пример: `share/settings.example.json`

## Runtime

- **Раздача пользователям:** только GitHub Releases (`myVPN.app.zip`). Не `install-app.zsh` как install path.
- **Обновление у пользователя (включая этот Mac как «прод»):** только кнопка «Проверить обновление» после нового GitHub Release.
- **Запрещено агенту/деплою:** копировать бинарь в `~/Applications` через `install-app.zsh` / `ditto` / `open` ради «подтянуть фикс». Локальный `install-app.zsh` — только явная отладка сборки по запросу «собери локально», не способ доставки.
- **Публикация релиза:** `macos/MyVPN/release.zsh [version]` → пользователь жмёт обновление.
- App: `~/Applications/myVPN.app`, runtime в `Contents/Resources/runtime`
- CLI symlink: `~/.local/bin/myvpn` → `~/.local/share/myvpn`
- Helper: LaunchDaemon `local.myvpn.mac.helper`
- Home CIDR из AllowedIPs conf; LAN/DNS/NAS из settings.json

## Alfred

Keyword `gv` живёт в **Utilits**. Этот репо — ядро/CLI/app.

## Навыки

Территория: `/Volumes/Nas/Project/mySkills/skills/` — не копировать в дом.
