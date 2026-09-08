---
id: doc-8
title: Публичный продукт и дистрибуция
type: specification
created_date: '2026-09-08 12:00'
updated_date: '2026-09-08 12:00'
---
# Публичный продукт и дистрибуция

Канон для агентов и разработчиков. Пользовательский текст — только **README.md**.

## Решения (ADR)

| Решение | Выбор | Почему |
|---------|--------|--------|
| Remote | `dimark57/myVPN-mac` (сначала private, public после scrub) | Один дом исходников + Releases |
| Секреты | Только `~/.config/wireguard/*.conf`; `*.conf` в gitignore | Ключи не в облаке |
| Топология | `~/.config/myvpn/settings.json` + AllowedIPs из home.conf | Чужие сети без хардкода digials/LAN в коде |
| Home routes | `AllowedIPs` профиля home (не 0.0.0.0/0) | Как у нормального WG split-клиенте |
| UI конфигов | Окно: импорт / буфер / правка текста | Паритет с WireGuard.app по вводу |
| Обновление app | GitHub Releases `myVPN.app.zip` + кнопка «Проверить обновление» (не silent auto) | Деплой = новый Release; пользователь жмёт кнопку |
| Раздача | Только Releases; `install-app.zsh` — dev/debug | README не учит собирать из исходников |
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
