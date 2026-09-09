---
id: doc-4
title: Menu bar myVPN
type: specification
created_date: '2026-09-07 13:10'
updated_date: '2026-09-08 13:20'
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

- Пользователь: **только** GitHub Releases (`myVPN.app.zip`) или in-app Update → `~/Applications/myVPN.app`
- Сборка релиза: `release.zsh` → `build-app.zsh` (stage) → zip → `gh release create` (не ставит локально)
- Runtime внутри: `Contents/Resources/runtime/{bin,lib,share}`
- Helper: LaunchDaemon `local.myvpn.mac.helper` + socket `/var/run/myvpn-helper.sock`
- Автозапуск UI: **SMAppService** login item приложения; legacy LaunchAgent `local.myvpn.mac.login` (zsh) **не** используется как основной путь

## Меню (минимум)

```
[status badge]
────────
Включить / Выключить
────────
Смонтировать NAS / Перемонтировать NAS
────────
Провести диагностику
Проверка обновления
────────
Настройки…          ⌃⌥⌘,
Горячие клавиши ▸
────────
Выход
```

### Глобальные горячие клавиши (Carbon, без Accessibility)

Модификатор **⌃⌥⌘** — меньше конфликтов, чем ClashX-style ⌘⇧*.

| Комбо | Действие |
|-------|----------|
| ⌃⌥⌘V | Вкл / Выкл VPN |
| ⌃⌥⌘N | Смонтировать NAS |
| ⌃⌥⌘D | Диагностика |
| ⌃⌥⌘, | Настройки |

- Helper install — только если helper отсутствует/сломан
- Настройки… → окно (shell фиксирован: sidebar + content frame одной высоты):
  - System Helper / Channels / Routes / **Доменные зоны** / Shares / **Диагностика** / Update / Справка
  - Доменные зоны: Обновить RU (geosite/geoip)
  - Диагностика: галочки автодиагностики / автовосстановления; L1/L2; Safe Mode Resume; коды отвалов; журнал `drops.log`; отчёт + GitHub Issues (**doc-9** + **doc-10 FDIR**)
- Справка — только внутри Настроек (не отдельный пункт menu bar)
- Установка app — только GitHub Releases (не локальный `install-app.zsh`)

### Автодоктор (FDIR 0.5 — doc-10)

Hard DROP (tun/nas/egress; ICMP peer = FLAP only) → L1 doctor → heal:

1. `DesiredState`: ручной Off → без `AUTO_HEAL up`
2. `myvpn doctor` (L1) / `doctor --deep` (L2) → report + `AUTO_DOCTOR` + `cid`
3. По PRIMARY (**doc-9**): `up` / `down→up` / `mount-nas --safe` / `flush-dns` + verify
4. Cooldown restart 300с после verify; Safe Mode; grace 60с; `flight.jsonl` + `incidents/`

Prefs: UserDefaults `local.myvpn.mac.autoDoctor` / `autoHeal` (default ON).

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
- Автодоктор / таксономия heal: **doc-9**; control plane FDIR: **doc-10**.
