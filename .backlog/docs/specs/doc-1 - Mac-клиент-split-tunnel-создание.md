---
id: doc-1
title: Mac-клиент split-tunnel (создание)
type: specification
created_date: '2026-09-07 16:40'
updated_date: '2026-09-07 13:00'
---
# Mac-клиент split-tunnel — спецификация на создание

Личный клиент на macOS: два WireGuard (MacBook + Home), российские ресурсы **напрямую**, остальной интернет через MacBook, DNS как у Happ (по доменам).

Это **не** you2vpn.ru (Laravel, биллинг, ноды). Продукт you2vpn: `/Volumes/Nas/Project/myVPN` (`BACK-*`). Этот репо — только Mac-клиент (`MYMAC-*`).

## Каталоги

| Путь | Роль |
|------|------|
| `/Volumes/Nas/Project/myVPN` | you2vpn: сайт, API, воркеры |
| `/Volumes/Nas/Project/myVPN-mac` | этот репо: sing-box, CLI, позже menu bar |
| Utilits `local/alfred/wireguard` | Keyword **`gv`**: статус / up / down |

Секреты WG: `~/.config/wireguard/*.conf` или `~/.config/myvpn/` — не в git.

Имя в UI: **myVPN**. Бандл: `local.myvpn.mac`. Backlog: **`MYMAC`**.

---

## Проблема

Сейчас на Mac: brew `wg-quick` + два туннеля. WG видит только IP. Российские сайты на чужом CDN уходят в VPN. `wg-quick` ломает DNS через `networksetup`. Happ умеет geosite/geoip + DNS; WG — нет.

## Цель MVP

Один процесс-ядро поднимает TUN и решает маршрут **до** выхода в сеть.

| Трафик | Куда |
|--------|------|
| geosite/geoip РФ (списки уровня Happ / ru-routing-dat) | Wi‑Fi, без VPN |
| `10.13.13.0/24`, `10.57.0.0/24` | WG **Home** |
| Остальной интернет | WG **MacBook** (публичный выход пира) |
| Endpoint MacBook и Home | Физический шлюз, без петли |
| Локальная LAN | Wi‑Fi (CIDR из `settings.json`) |

Состояния: **Off** = обычный Wi‑Fi. **On** = схема выше.

При падении Home: интернет и RU-direct живы. При падении MacBook: не оставлять чёрную дыру default — down всего ядра или явный degraded (только Home + direct).

---

## Что не входит в MVP

- Клон Happ (подписки, VLESS, магазин серверов)
- GUI WireGuard.app как ядро
- App Store / Network Extension (этап 2)
- IPv6 как обязательное требование
- Код внутри `laravel/` you2vpn

---

## Стек

| Слой | Выбор |
|------|--------|
| Ядро | **sing-box** (TUN inbound, DNS, outbound `wireguard` ×2, `direct`) |
| Оболочка MVP | CLI `myvpn up` / `myvpn down` / `myvpn status` |
| UI позже | Swift menu bar |
| Правила РФ | geosite + geoip (GitHub, обновление командой `myvpn update-rules`) |
| Alfred | Utilits `gv` → CLI |

TUN в MVP: sudo или privileged helper. Без массового `networksetup` «как wg-quick»; узкий TUN-DNS на выбранные сервисы — см. **doc-2**.

---

## Конфиг ядра (логика, не секреты)

sing-box читает:

1. Ключи/endpoint из локальных WG-профилей (`macbook.conf`, `home.conf`).
2. Правило: `geoip:ru` + выбранные `geosite` → `direct`.
3. Правило: `10.13.13.0/24`, `10.57.0.0/24` → outbound `home`.
4. Default → outbound `macbook`.
5. DNS: российские имена — в direct; остальное — через MacBook. Узкий TUN-DNS на выбранные Network Services — **doc-2** (не wg-quick-style на все сервисы).

Список RU не копировать в AllowedIPs WG. Маршрутизация только в sing-box.

---

## CLI (контракт)

```
myvpn up          # TUN + оба WG outbound + RU direct
myvpn down
myvpn status      # macbook / home / tun / публичный IP если дёшево
myvpn update-rules
```

Exit 0 / ≠0. Короткий текст в stdout для Alfred. Перед `up` глушить Connected-туннели **WireGuard.app** (`scutil --nc stop`), чтобы не драться за default.

Пароль macOS: один раз на `up` (osascript admin или sudo), как сейчас у `gv` brew.

---

## Приёмка MVP

На домашнем Wi‑Fi (`192.168.3.0/24`), App WireGuard выключен:

1. `myvpn up` → публичный IPv4 = выход MacBook (`77…`), не домашний WAN (`94…`).
2. `ping 10.13.13.1` и `10.57.0.100` — ок.
3. Запрос к типичному RU-ресурсу с адресом в `geoip:ru` идёт **не** в utun MacBook.
4. `myvpn down` → интернет через роутер, без зависания DNS.
5. `gv` в Alfred: статус, macbook+home, выключить — иконки on/off, внутри CLI myvpn.

---

## Этапы

| # | Сделать | Где |
|---|---------|-----|
| 0 | Репо `myVPN-mac` | этот дом (сделано) |
| 1 | sing-box, генерация JSON из локальных `.conf` | myVPN-mac |
| 2 | CLI up/down/status, приёмка | myVPN-mac |
| 3 | Переключить Utilits `apply-wg.zsh` на `myvpn` | Utilits |
| 4 | Menu bar | myVPN-mac |
| 5 | Network Extension | myVPN-mac |

---

## Риски

- TUN без NE = sudo.
- geosite не покрывает все «российские» имена на зарубежном CDN — приемлемо для MVP.
- Имя myVPN в UI ≠ you2vpn.ru.

---

## Открыто (не блокер MVP)

Набор geosite-категорий. Источник `.dat`: ru-routing-dat vs Loyalsoldier. IPv6 direct для RU.

---

## Спеки этапов

Продукт (этот документ) задаёт зачем. На каждый этап стройки — своя спека. Веха: **v0 — Mac split-tunnel**.

| Этап | Спека | Где код |
|------|--------|---------|
| 0 Репо | этот документ | myVPN-mac (сделано) |
| 1–2 Ядро + CLI | **doc-2 — Ядро sing-box и CLI myvpn** | myVPN-mac |
| 3 Alfred `gv` | **doc-3 — Контракт CLI для Alfred gv** | Utilits (не этот репо) |
| 4 Menu bar | **doc-4 — Menu bar myVPN** | myVPN-mac |
| 5 Network Extension | **doc-5 — Network Extension myVPN** | myVPN-mac |
| Тесты v0 | **doc-6 — Тестирование CLI myvpn** | myVPN-mac |
