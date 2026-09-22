---
id: doc-3
title: Контракт CLI для Alfred gv
type: specification
created_date: '2026-09-07 13:00'
updated_date: '2026-09-07 17:30'
card: MYMAC-2
---
# Контракт CLI для Alfred gv

Контракт между keyword **`gv`** (репозиторий **Utilits**) и CLI **`myvpn`** в этом доме.  
Код Alfred здесь **не** пишется. Продукт: **doc-1**. Ядро: **doc-2**.

## Граница

| Входит | Не входит |
|--------|-----------|
| Какие команды вызывает `gv` | Workflow/UI Alfred |
| Формат stdout / exit | Menu bar (**doc-4**), NE (**doc-5**) |
| Путь к бинарю | Реализация Utilits |

## Бинарь

Alfred вызывает **`~/.local/bin/myvpn`** (symlink на локальный runtime, не `/Volumes/Nas/...`).

## Команды для gv

| Действие gv | CLI | Exit |
|-------------|-----|------|
| Статус | `myvpn status` | 0 всегда, если CLI жив; отдельные флаги в stdout |
| Включить | `myvpn up` | 0 / ≠0 |
| Выключить | `myvpn down` | 0 / ≠0 |

Опционально (не обязательны для MVP gv): `update-rules`, `mount-nas`, `helper-status`.

Замена brew `wg-quick` / старых скриптов macbook+home — только через эти команды.

## Формат `status` (обязательный)

Строки `key=value`, по одной на строку (порядок стабилен для парсера):

```text
tun=0|1
macbook=0|1
home=0|1
nas=0|1
ip=<IPv4>|
```

- **Не** AND двух пиров: UI/Alfred читают флаги **раздельно**.
- Пустой `ip=` при сбое URL публичного IP — **не** ошибка всего status.
- Публичный IP при up = выход MacBook (`77…`), не домашний WAN.

## Ошибки

Stderr + exit ≠0: нет conf, нет sing-box, нет прав / helper, уже up (если политика «ошибка»), сеть для mount.

## Приёмка контракта

Человек или скрипт в Utilits: `myvpn status` парсится в 5 ключей; `up`/`down` меняют `tun=` без brew `wg-quick`.

## Связь

- **doc-2** — поведение ядра.
- **doc-4** — тот же CLI из menu bar.
- Реализация Alfred — другой дом (Utilits).
