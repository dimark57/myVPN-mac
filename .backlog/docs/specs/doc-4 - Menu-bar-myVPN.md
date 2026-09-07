---
id: doc-4
title: Menu bar myVPN
type: specification
created_date: '2026-09-07 13:10'
updated_date: '2026-09-07 17:30'
---
# Menu bar myVPN

Оболочка AppKit над тем же ядром/CLI (**doc-2**). Без своей маршрутизации.  
Продукт: **doc-1**. UX списков RU: **doc-7**. NE: **doc-5** (не этот этап).

## Граница

| Входит | Не входит |
|--------|-----------|
| LSUIElement menu bar `local.myvpn.mac` | Network Extension / App Store |
| Вызовы runtime CLI / helper socket | Alfred (**doc-3** / Utilits) |
| Login Item (SMAppService) | sudoers NOPASSWD |
| Установка privileged helper | Клон Happ |

## Поставка

- Сборка: `macos/MyVPN/` → `~/Applications/myVPN.app`
- Runtime внутри: `Contents/Resources/runtime/{bin,lib,share}`
- Helper: LaunchDaemon `local.myvpn.mac.helper` + socket `/var/run/myvpn-helper.sock`
- Автозапуск UI: **SMAppService** login item приложения; legacy LaunchAgent `local.myvpn.mac.login` (zsh) **не** используется как основной путь

## Меню (минимум)

- Status (tun / пиры / NAS / IP) — info
- Включить / Выключить (disabled, пока helper не установлен)
- Смонтировать NAS
- Обновить списки RU (+ info geosite-ru / geoip-ru — **doc-7**)
- Настройки: helper install/uninstall, автозапуск, auto-NAS, авто-up при запуске
- Выход

Пока долгая операция: disabled **только** текущий пункт; меню не глушить целиком. Sticky click (меню не закрывать по клику пункта) — решение CEO; закрытие — mouse leave.

## Контракт вызовов

Тот же SoT, что CLI: `up` / `down` / `status` / `update-rules` / `mount-nas` / флаги autostart / auto-nas.  
On/Off через helper socket после установки помощника (без admin на каждый up).

После успешного **первого** up (туннель был down): если auto-NAS on — `mount-nas --force` (stale smbfs после sleep/VPN flap).

## Иконка / привилегии

- Menu bar icon отражает on/off (и busy при операции).
- Первый admin — только на install helper (и при необходимости flush DNS). Дальше On/Off без пароля.
- Без Developer ID в v0 — helper, не NE.

## Приёмка

1. App в `~/Applications`, runtime не с NAS.
2. Login Item = myVPN.app; нет zsh LaunchAgent login-boot как основного автозапуска.
3. После install helper — On/Off без пароля.
4. Status и списки RU читаемы; update-rules даёт явный итог (**doc-7**).

## Связь

- Упаковка: задача **MYMAC-8**.
- UX RU: **doc-7** / **MYMAC-9**.
- Следующий этап без admin вообще: **doc-5**.
