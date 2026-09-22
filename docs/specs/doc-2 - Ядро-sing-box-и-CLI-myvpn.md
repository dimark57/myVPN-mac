---
id: doc-2
title: Ядро sing-box и CLI myvpn
type: specification
created_date: '2026-09-07 12:55'
updated_date: '2026-09-07 17:35'
card: MYMAC-6
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
- `down`: SIGTERM по pid, TUN снимается; системный DNS сервисов из `MYVPN_DNS_SERVICES` возвращается в `Empty` (см. § DNS).

## Маршруты (TUN)

- `auto_route: true`. IPv6 в TUN/маршрутах **выключен**.
- Endpoint MacBook и Home (`…/32`) — всегда **direct** (без петли handshake).
- `192.168.3.0/24`, private — direct.
- `10.13.13.0/24`, `10.57.0.0/24` — endpoint Home (**все порты** NAS/сервисов).
- `geoip:ru` + `geosite` RU — direct.
- Остальное — endpoint MacBook.

Healthcheck пиров **не** в v0. Home down не валит интернет. Мёртвый MacBook — пользователь делает `down` (не чёрная дыра default).

## DNS

Внутри sing-box — hijack с TUN. Не Fake-IP. **Не** брать `DNS=` из `macbook.conf` / `home.conf` в system DNS.

Чтобы digials не уходили в LAN DHCP / DoH → hairpin `94…` (Hub 403), на **перечисленных** Network Services (`MYVPN_DNS_SERVICES`, по умолчанию `Wi-Fi`) при `up` выставляется `networksetup -setdnsservers <service> ${MYVPN_TUN_DNS}` (`172.19.0.1`). При `down` — `Empty` на тех же сервисах. Вызовы **таймаутятся** (stale USB hang). Это **не** «DNS= из WG conf на все сервисы» и не brew `wg-quick`.

Имена домашнего контура (`backlog.digials.com`, `ocode.digials.com`, …) → **`10.57.0.100`** (CoreDNS на NAS).

RU-имена — direct; остальной резолв — через MacBook.

## Списки RU

Источник: **ru-routing-dat** (`geosite.dat`, `geoip.dat`) → кэш в `~/.config/myvpn/`.  
Direct: `category-ru-whitelist` (или `category-ru`, если whitelist нет в файле) + `geoip:ru`.  
`update-rules` качает эти два файла. Не тащить рекламу, Discord, полный Happ.

## CLI

```
myvpn up | down | status | update-rules | mount-nas [--force]
myvpn install-autostart | uninstall-autostart
myvpn autostart | auto-nas | helper-status | flush-dns | render
```

Exit 0 / ≠0. `status`: `tun=` / `macbook=` / `home=` / `nas=` / `ip=` (сбой IP не роняет весь status). Ошибки: нет conf, нет sing-box, нет прав, уже up — stderr.

Публичный IP после `up` = выход MacBook (`77…`), не домашний WAN.

`mount-nas` — SMB `//NAS@10.57.0.100/Nas` → `/Volumes/Nas` (пароль из Keychain). `--force` — всегда remount (после VPN up / stale smbfs).  
`install-autostart` — Keychain SMB + флаги; основной UI-автозапуск — **menu bar Login Item** (**doc-4**), не zsh LaunchAgent.

## Автозапуск (логин / перезагрузка)

Замена ручного `gv → macbook+home` после reboot.

1. Канон v0: **myVPN.app** как SMAppService login item + privileged helper; при старте — optional auto-up и auto-NAS (`mount-nas --force` после свежего up).
2. Legacy `login-boot` / LaunchAgent `local.myvpn.mac.login` — только запасной путь; не основной.
3. `myvpn down` не обязан размонтировать `/Volumes/Nas`.

Не поднимать brew `wg-quick` из автозапуска.

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
lib/          # env, process, nas, render_config, parse_conf, update_rules, …
macos/MyVPN/  # menu bar + helper (doc-4)
share/        # опциональные шаблоны; JSON генерирует render_config.py
tests/        # static-check + фикстуры (doc-6)
```

## Приёмка этапа

На домашнем Wi‑Fi/USB-LAN, WireGuard.app выключен: `myvpn up` → IP MacBook; ping Home/NAS; Hub HTTP 200; dig backlog → `10.57.0.100`; ya.ru не в utun MacBook; `down` → интернет жив. Полный набор — **doc-6 — Тестирование CLI myvpn**.

## Регрессии с текущего gv / wg-quick

Чат ([Почему гаснет macbook+home](07daca87-99a5-4c9a-8b31-a896cff7a373)); эталон цикла: `cycle-macbook-home.zsh` → PASS.

1. **Не два `wg-quick`.** Один sing-box. Запрещены Darwin `route -n monitor` ×2 и массовый `networksetup -setdnsservers` «как wg-quick на все сервисы». Узкий TUN-DNS на `MYVPN_DNS_SERVICES` — разрешён (см. § DNS).
2. **`status` не AND.** tun / macbook / home по отдельности.
3. **Сон / Power Nap / USB-flap.** После wake — живое ядро или честный down; без orphan процессов.
4. **DNS vs hairpin.** `94…/32` — direct только как WG endpoint. Сервисы Hub — по `10.57.0.100` (DNS в ядре). Не тащить `94…` в «внутренние сервисы».
5. **LAN `192.168.3.0/24`** всегда direct.
6. **Keepalive** на пирах — ок для NAT; не заменяет надзор за процессом.
7. **Тест-цикл с restore.** Не рвать VPN из чата без фазы «вернуть WireGuard.app MacBook» (иначе агент теряет `/Volumes/Nas`).
