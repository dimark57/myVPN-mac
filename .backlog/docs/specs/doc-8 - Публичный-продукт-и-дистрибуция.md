---
id: doc-8
title: Публичный продукт и дистрибуция
type: specification
created_date: '2026-09-08 12:00'
updated_date: '2026-09-08 12:30'
---
# Публичный продукт и дистрибуция

Канон для агентов и разработчиков. Пользовательский текст — только **README.md**.

## Решения (ADR)

| Решение | Выбор | Почему |
|---------|--------|--------|
| Remote | `dimark57/myVPN-mac` (сначала private, public после scrub) | Один дом исходников + Releases |
| Секреты | Только `~/.config/wireguard/*.conf`; `*.conf` в gitignore | Ключи не в облаке |
| Топология | `settings.json`: `channels[]` + `routes[]` (+ NAS/DNS scalars) | Чужие сети без хардкода; миграция с macbook/home.conf |
| Маршруты | Только `routes[]`; AllowedIPs в `.conf` **не** источник route | Как Clash/sing-box |
| UI конфигов | Окно: System Helper / Channels / Routes / Shares / Update (+ Справка из меню) | Без submenu в menu bar; автоподключения в блоках Channels/Shares |
| Обновление app | GitHub Releases + галочки auto-check / auto-install (launch + hourly) + кнопка Update | Деплой = новый Release |
| Раздача | Только Releases; `install-app.zsh` — только явная отладка / внутри `release.zsh` | README не учит собирать из исходников |
| Доставка на Mac владельца | Не «закатывать фикс» через install; после `release.zsh` local==Release, дальше только кнопка | Иначе откаты |
| Списки RU | Отдельный пункт меню | Не путать с обновлением приложения |
| README | Маркетинг + install/update/configure | Без backlog/CLI/личных IP |
| Подпись | Ad-hoc (`codesign -`) в v0 | Нет Developer ID; Gatekeeper warning OK |

## Слои документации

1. **README.md** — люди, ставящие `.app`
2. **CONTRIBUTING.md** — сборка из исходников
3. **AGENTS.md** + **doc-1…doc-8** — агенты и инженерия
4. **SECURITY.md** — секреты и репорты

Правило: любое продуктовое «выбрали X вместо Y» → 5–10 строк сюда или в AGENTS в том же коммите.

## Дистрибуция

- Скрипт: `macos/MyVPN/release.zsh [version]`
- Asset имя (жёстко в `UpdateChecker`): `myVPN.app.zip`
- Repo API: `https://api.github.com/repos/dimark57/myVPN-mac/releases/latest`

## Открыто (gap до «спокойно раздавать»)

1. Онбординг-wizard при пустых conf
2. Developer ID + нотаризация
3. Network Extension (doc-5) без admin helper
4. N профилей с ролями, не только macbook/home
5. Sparkle / подпись обновлений
6. Homebrew cask
7. IPv6 / sleep-wake edges в справке для пользователя

## Связь

- Ядро: **doc-2**. Menu bar: **doc-4**. Тесты: **doc-6**.
