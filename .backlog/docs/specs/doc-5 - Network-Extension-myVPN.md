---
id: doc-5
title: Network Extension myVPN
type: specification
created_date: '2026-09-07 12:55'
updated_date: '2026-09-07 19:46'
---
# Network Extension myVPN

Поздний этап после CLI (**doc-2**) и menu bar (**doc-4**).  
Цель: системный VPN-профиль Apple — **TUN без постоянного sudo / admin на каждый up**.

UI-имя: **myVPN**. Bundle ID приложения: `local.myvpn.mac`.  
Предполагаемый extension id: `local.myvpn.mac.tunnel` (уточняется при стройке).

## Зачем

CLI и menu bar v1 поднимают sing-box TUN с одним admin-диалогом. Это приемлемо для v0, но не для ежедневного UX. Network Extension (NE) даёт:

- постоянный VPN в «Системных настройках» / меню VPN;
- подъём без пароля после первого одобрения расширения;
- корректный sleep/wake на уровне ОС лучше, чем userspace TUN «в обход».

## Граница

| Входит | Не входит |
|--------|-----------|
| Packet Tunnel Provider (или эквивалент Apple VPN API) | App Store / биллинг / Happ-ноды |
| Упаковка app + extension, Developer ID + notarize | Переписывание you2vpn (`BACK-*`) |
| Переход с CLI-TUN на NE-TUN при сохранении правил doc-2 | Обязательный IPv6 |
| Menu bar (**doc-4**) как UI поверх NE | `/etc/sudoers` NOPASSWD |
| Тот же смысл On/Off, те же WG `.conf` | Смена продукта на клон Happ |

Не смешивать с этапом «просто Swift вызывает CLI»: это **замена способа поднять TUN**, не новая маршрутизация «с нуля».

## Зависимости

1. Рабочие правила и пути из **doc-2** (endpoints MacBook/Home, direct RU, DNS digials → `10.57.0.100`).
2. Подписанный **doc-4** (menu bar остаётся оболочкой; после NE вызывает connect/disconnect профиля, а не обязательно `osascript` admin).
3. Apple Developer: команда с capability Network Extensions / Packet Tunnel; подпись Developer ID (раздача вне App Store).

## Архитектура (решения этапа)

### Ядро внутри NE

**Решение по умолчанию:** сохранить **sing-box** (или тот же движок правил) **внутри** tunnel extension / privileged network process, а не переписывать маршрутизацию на Network.framework с нуля.

Альтернатива (только если sing-box в NE упрётся в sandbox/API): тонкий Packet Tunnel + отдельный helper — тогда отдельное решение CEO до стройки. В спеке цель — **те же outbound/direct**, что в doc-2.

### Что остаётся снаружи

| Компонент | Роль после NE |
|-----------|----------------|
| `~/.config/wireguard/*.conf` | ключи; парсер как сейчас |
| `~/.config/myvpn/rules/*.srs` | geosite/geoip; `update-rules` |
| Menu bar | On/Off, status, уведомления |
| CLI `myvpn` | остаётся для Alfred/отладки; либо тонкий клиент к NE (`startTunnel` / status), либо deprecated admin-TUN путь |
| LaunchAgent login | либо стартует NE-connect, либо уходит — не два конкурирующих TUN |

Одновременно **не** держать userspace CLI-TUN и NE-TUN.

### Тип расширения

Предпочтение: **system extension** (Packet Tunnel), если нужен полный split-tunnel и автозапуск; app extension — только если хватает ограничений и проще подпись. Финальный выбор — при spike стройки; в приёмке зафиксировать один вариант.

## DNS и hairpin (обязательно сохранить)

Как в doc-2 / уроки CLI:

- `*.digials.com` / `*.digials.ru` → `10.57.0.100` (CoreDNS), не WAN `94…` (Caddy 403).
- Endpoint Home/MacBook `/32` — direct для handshake.
- Не тащить WG `DNS=` в system DNS «как wg-quick»; DNS решает ядро (или DNS settings привязанные к VPN-профилю согласованно с CoreDNS).

## Привилегии

1. Первый запуск: пользователь одобряет Network Extension / VPN configuration (системный диалог Apple) — **один раз**, не каждый up.
2. **sudoers NOPASSWD — запрещён** (решение продукта).
3. После одобрения: On/Off из menu bar без admin-пароля.
4. Отзыв расширения в Системных настройках = Off + честный статус.

## Поведение On / Off

- **On** — NE connected; те же смысловые проверки, что CLI: IP выхода MacBook, Home/NAS, Hub 200.
- **Off** — профиль disconnected; интернет через физический интерфейс; DNS не оставлять сломанным.
- Status для Alfred/menu bar: сохранить контракт строк `tun=` / `macbook=` / `home=` / `nas=` / `ip=` (**doc-3**), даже если `tun` означает «NE up», а не pid sing-box CLI.

## Миграция с CLI-TUN

Порядок внедрения (стройка, не эта карточка-спека):

1. Spike: empty Packet Tunnel + connect/disconnect из menu bar.
2. Встроить генерацию конфига / sing-box (или эквивалент) с правилами doc-2.
3. Переключить menu bar на NE; CLI admin-TUN — fallback или `myvpn up --legacy` до выпила.
4. Обновить LaunchAgent и cycle-тесты под NE.
5. Убрать зависимость от osascript admin для повседневного up.

## Приёмка этапа (после реализации)

1. После одного одобрения NE: On без пароля администратора.
2. Те же сетевые критерии, что doc-6 / live cycle (DNS backlog → `10.57.0.100`, Hub 200, IP MacBook, ping Home/NAS).
3. Off не ломает DNS/интернет.
4. Нет параллельного CLI-TUN.
5. Menu bar иконка согласована со статусом NE.

## Связь со спеками

| Документ | Роль |
|----------|------|
| **doc-2** | правила маршрутов/DNS — SoT |
| **doc-3** | формат status для Alfred |
| **doc-4** | UI; после NE — без admin на каждый up |
| **doc-6** | цикл тестов адаптировать под NE |

## Открыто (закрыть на spike, не блокер подписи смысла doc-5)

- system vs app extension — после первого spike;
- sing-box embedded vs замена движка — подтвердить на spike;
- точное имя extension bundle и entitlements plist.
