# myVPN-mac — AGENTS

Prefix: `MYMAC` · Role: personal → public-ready · Contour: `.` (этот репо)  
GitHub: `dimark57/myVPN-mac` (Releases = in-app updates)  
**CD recipe: macos-gh-app**

Клиент split-tunnel на macOS (sing-box + два WG). **Не** продукт you2vpn (`myVPN`, prefix `BACK`).

## Репо и окружение

| | Mac | NAS |
|--|-----|-----|
| git clone | `~/repos/myVPN-mac` | `/srv/nas/repos/myVPN-mac` |
| Docker (если будет) | `~/stacks/<app>/` | `/srv/nas/stacks/<app>/` |

Layout NAS/Mac (dual-path, без `~/nas/` на Mac): навык **nas-layout** в mySkills.

## mySkills

| | Путь |
|--|------|
| clone Mac | `~/repos/mySkills` |
| clone NAS | `/srv/nas/repos/mySkills` |
| CLI | `…/bin/myskills` в PATH, prefix = корень clone |

Установка: [mySkills → docs/user/myskills-install.md](https://github.com/dimark57/mySkills/blob/main/docs/user/myskills-install.md) (git clone). **Не** копировать `skills/` в этот репо.

Ship → навык **`cd`** (`macos-gh-app`).

## Документация

| Аудитория | Куда |
|-----------|------|
| Пользователи | `README.md` |
| Агенты + разработчики | этот файл + `docs/specs/` — продуктовые решения в **doc-8** |

Оглавление: [docs/README.md](docs/README.md). Спеки: doc-1…doc-8, doc-9–13 FDIR.

## Задачи

SoT: **myTask REST** (префикс `MYMAC`, проект `myVPN-mac`). Чтение/перемещение карточек: навык **mytask-api** в репо **myTask** (`doc-29`), не `mySkills/skills/mytask`. Registry handoff: `myNAS/stacks/agent/backlog-hub/registry/projects.json`.

## Секреты

- Не коммитить `*.conf` с ключами, не класть WG-ключи в чат.
- Локально: `~/.config/wireguard/{macbook,home}.conf`
- Маршруты/NAS/DNS (без ключей): `~/.config/myvpn/settings.json` (`lib/settings.py`, `AppSettings.swift`)
- Пример: `share/settings.example.json`

## Runtime

- **Раздача / установка:** только GitHub Releases (`myVPN.app.zip`). `install-app.zsh` **отключён** (exit 1 → ссылка на Releases).
- **Обновление:** автопроверка при запуске и каждый час или Настройки → Update. **Не** копировать из stage/DerivedData в `~/Applications`.
- **Запрещено агенту/деплою:** `ditto` / `cp` / `open` бинаря в `~/Applications` в обход Releases.
- **Публикация:** `macos/MyVPN/ship.zsh --confirm --bump patch|…` (один bump → commit → tag → zip → gh → push).
- App: `~/Applications/myVPN.app`, runtime в `Contents/Resources/runtime`
- CLI symlink: `~/.local/bin/myvpn` → `~/.local/share/myvpn`
- Helper: LaunchDaemon `local.myvpn.mac.helper`
- NAS SMB: `nas_mount` / `nas_share` в settings (не legacy `/Volumes/Nas/Project` как канон)

## Alfred

Keyword `gv` живёт в **Utilits**. Этот репо — ядро/CLI/app.
