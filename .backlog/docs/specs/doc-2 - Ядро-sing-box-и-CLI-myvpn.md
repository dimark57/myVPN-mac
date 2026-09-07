---
id: doc-2
title: Ядро sing-box и CLI myvpn
type: specification
created_date: '2026-09-07 12:55'
updated_date: '2026-09-07 13:36'
---
# Ядро sing-box и CLI myvpn

Этап **v0**. Продуктовый замысел: **doc-1 — Mac-клиент split-tunnel**. Этот документ — замок исполнителя: с одного промпта собирается CLI, не GUI.

## Граница

Входит: генерация JSON, процесс sing-box, команды `myvpn up|down|status|update-rules|mount-nas|install-autostart`; автоподъём после логина; автомонтирование SMB NAS.

Не входит: Alfred/Utilits (см. **doc-3 — Контракт CLI для Alfred gv**), Swift menu bar (**doc-4**), Network Extension (**doc-5**), you2vpn, Happ.

## Поставка

- Язык: zsh-обёртка + бинарь `sing-box` из Homebrew.
- Установка CLI: `~/.local/bin/myvpn` (или `/opt/homebrew/bin`, если уже в PATH).
- sing-box **≥ 1.12**. WireGuard только как `endpoints[]`, не `outbounds type: wireguard`.

## Пути

| Что | Куда |
|-----|------|
| Секреты WG | `~/.config/wireguard/macbook.conf`, `home.conf` |
| JSON, pid, лог, кэш правил | `~/.config/myvpn/` |

Ключи не в git и не в лог. `AllowedIPs` и `DNS` из `.conf` **не** задают маршруты и системный DNS.

Парсер: `PrivateKey`, `Address`, `PublicKey`, `Endpoint`; опционально `PresharedKey`, `PersistentKeepalive`, `MTU`.

## Процесс

- Один экземпляр (pid-файл). Повторный `up` без `down` — ошибка или явный restart.
- Перед `up`: остановить Connected-туннели WireGuard.app (`scutil --nc stop`).
- Привилегия: один запрос admin на `up`. Если через AppleScript: **heredoc** + `json.dumps(..., ensure_ascii=False)`; без вложенных кавычек в командах (`pkill -f …`).
- `down`: SIGTERM по pid, TUN снимается; **не** вызывать `networksetup -setdnsservers`.

## Маршруты (TUN)

- `auto_route: true`. IPv6 в TUN/маршрутах **выключен**.
- Endpoint MacBook и Home (`…/32`) — всегда **direct** (без петли handshake).
- `192.168.3.0/24`, private — direct.
- `10.13.13.0/24`, `10.57.0.0/24` — endpoint Home (**все порты** NAS/сервисов).
- `geoip:ru` + `geosite` RU — direct.
- Остальное — endpoint MacBook.

Healthcheck пиров **не** в v0. Home down не валит интернет. Мёртвый MacBook — пользователь делает `down` (не чёрная дыра default).

## DNS

Только внутри sing-box (hijack с TUN). Не Fake-IP. **Не** брать `DNS=` из `macbook.conf` / `home.conf` в system DNS.

Имена домашнего контура (`backlog.digials.com`, `ocode.digials.com`, …) должны резолвиться в **`10.57.0.100`** (CoreDNS на NAS), чтобы трафик шёл в Home-сетку, а не hairpin на WAN `94…` (Caddy: `403 VPN / LAN only`).

RU-имена — так, чтобы попадали в direct; остальной резолв — через MacBook.

## Списки RU

Источник: **ru-routing-dat** (`geosite.dat`, `geoip.dat`) → кэш в `~/.config/myvpn/`.  
Direct: `category-ru-whitelist` (или `category-ru`, если whitelist нет в файле) + `geoip:ru`.  
`update-rules` качает эти два файла. Не тащить рекламу, Discord, полный Happ.

## CLI

```
myvpn up | down | status | update-rules | mount-nas | install-autostart
```

Exit 0 / ≠0. `status`: tun / macbook / home / nas-mount / публичный IPv4 (один URL, таймаут; сбой IP не роняет весь status). Ошибки: нет conf, нет sing-box, нет прав, уже up — stderr.

Публичный IP после `up` = выход MacBook (`77…`), не домашний WAN.

`mount-nas` — SMB `//NAS@10.57.0.100/Nas` → `/Volumes/Nas` (пароль из Keychain, не из git).  
`install-autostart` — LaunchAgent + запись SMB-учётки в Keychain (один раз).




## Автозапуск (логин / перезагрузка)

Замена ручного `gv → macbook+home` после reboot.

1. `myvpn install-autostart` ставит LaunchAgent `local.myvpn.mac.login` (RunAtLoad + сеть).
2. После логина агент ждёт сетевой интерфейс → `myvpn up` (схема MacBook+Home в одном ядре) → ждёт `10.57.0.100` → `myvpn mount-nas`.
3. Privileges для TUN: один запрос admin после логина допустим в v0; privileged helper — не блокер v0, можно позже.
4. `myvpn down` не обязан размонтировать `/Volumes/Nas` (чтобы Cursor не терял файлы); отдельный `umount` — вручную или флаг позже.

Не поднимать brew `wg-quick` из LaunchAgent.

## Автомонтирование NAS

Факт с машины: `//NAS@10.57.0.100/Nas` на `/Volumes/Nas` (smbfs).

| Параметр | Значение |
|----------|----------|
| Host | `10.57.0.100` (после Home) |
| Share | `Nas` → `/Volumes/Nas` |
| User | `NAS` |
| Password | **только** macOS Keychain, service `local.myvpn.mac.nas`, account `NAS`. В git / спеку / чат пароль **не** писать. |
| MVP shares | только `Nas`. Backup / Data / TimeMachine — не в v0. |

`install-autostart` один раз кладёт пароль в Keychain (ввод владельцем или из локального секрета вне git). Код читает через `security find-generic-password`. Монтирование: `mount_smbfs` / `open` smb URL без эха пароля в лог и argv процесса, если возможно через Keychain.

Если Home ещё нет (не дома) — `mount-nas` делает retry с таймаутом и пишет blocked в status, не зависает навсегда.

## Репо

```
bin/myvpn
lib/
share/sing-box.json.template
share/launchagents/local.myvpn.mac.login.plist
tests/   # фикстуры .conf; cycle-myvpn.zsh (см. doc-6)
```

## Приёмка этапа

На домашнем Wi‑Fi/USB-LAN, WireGuard.app выключен: `myvpn up` → IP MacBook; ping Home/NAS; Hub HTTP 200; dig backlog → `10.57.0.100`; ya.ru не в utun MacBook; `down` → интернет жив. Полный набор — **doc-6 — Тестирование CLI myvpn**.

## Регрессии с текущего gv / wg-quick

Чат ([Почему гаснет macbook+home](07daca87-99a5-4c9a-8b31-a896cff7a373)); эталон цикла: `cycle-macbook-home.zsh` → PASS.

1. **Не два `wg-quick`.** Один sing-box. Запрещены Darwin `route -n monitor` ×2 и `networksetup -setdnsservers` на все сервисы.
2. **`status` не AND.** tun / macbook / home по отдельности.
3. **Сон / Power Nap / USB-flap.** После wake — живое ядро или честный down; без orphan процессов.
4. **DNS vs hairpin.** `94…/32` — direct только как WG endpoint. Сервисы Hub — по `10.57.0.100` (DNS в ядре). Не тащить `94…` в «внутренние сервисы».
5. **LAN `192.168.3.0/24`** всегда direct.
6. **Keepalive** на пирах — ок для NAT; не заменяет надзор за процессом.
7. **Тест-цикл с restore.** Не рвать VPN из чата без фазы «вернуть WireGuard.app MacBook» (иначе агент теряет `/Volumes/Nas`).
