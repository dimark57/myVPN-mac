# myVPN-mac — AGENTS

Prefix: `MYMAC` · Role: personal → public-ready · Contour: `.` (этот репо)  
GitHub: `dimark57/myVPN-mac` (Releases = in-app updates)  
**CD recipe: macos-gh-app**

Клиент split-tunnel на macOS (sing-box + два WG). **Не** продукт you2vpn (`myVPN`, prefix `BACK`).

## Документация (два слоя)

| Аудитория | Куда писать |
|-----------|-------------|
| Пользователи приложения | `README.md` только (install / update / configure) |
| Агенты + разработчики | этот файл + `.backlog/docs/specs/` — решения сразу в **doc-8** |

Спеки: doc-1 продукт, doc-2 ядро, doc-3 Alfred, doc-4 menu bar, doc-5 NE, doc-6 тесты, doc-7 RU UX, **doc-8 публичная дистрибуция**, doc-11/12 FDIR.

## Задачи

`MYMAC-*` — `backlog task list`. Create всегда Draft.

## Секреты

- Не коммитить `*.conf` с ключами, не класть WG-ключи в чат.
- Локально: `~/.config/wireguard/{macbook,home}.conf`
- Маршруты/NAS/DNS (без ключей): `~/.config/myvpn/settings.json` (`lib/settings.py`, `AppSettings.swift`)
- Пример: `share/settings.example.json`

## Runtime

- **Раздача / установка:** только GitHub Releases (`myVPN.app.zip`). `install-app.zsh` **отключён** (exit 1 → ссылка на Releases).
- **Обновление у пользователя (включая этот Mac как «прод»):** после ship — автопроверка при запуске и каждый час (auto-install) или Настройки → Update. **Не** копировать из stage/DerivedData в `~/Applications`.
- **Запрещено агенту/деплою:** `ditto` / `cp` / `open` бинаря в `~/Applications` в обход Releases.
- **Публикация релиза (канон):** навык `cd` → `cd-skill release --confirm --version X.Y.Z` → `macos/MyVPN/ship.zsh` (один bump → commit → tag → zip → gh → push). Legacy: `release.zsh` только package; не вызывать без ship (двойной bump / retag).
- App у пользователя: `~/Applications/myVPN.app` (из zip или Update), runtime в `Contents/Resources/runtime`
- CLI symlink: `~/.local/bin/myvpn` → `~/.local/share/myvpn`
- Helper: LaunchDaemon `local.myvpn.mac.helper`
- Home CIDR из AllowedIPs conf; LAN/DNS/NAS из settings.json

## Alfred

Keyword `gv` живёт в **Utilits**. Этот репо — ядро/CLI/app.

## Навыки

Территория: соседний дом `mySkills/skills/` — не копировать в этот репо.  
Ship/катим → навык **`cd`** (`macos-gh-app`), не ad-hoc субагент с retag.
