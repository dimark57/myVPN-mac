---
id: doc-6
title: Тестирование CLI myvpn
type: specification
created_date: '2026-09-07 13:00'
updated_date: '2026-09-07 17:35'
---
# Тестирование CLI myvpn

Этап **v0**. Продукт: **doc-1 — Mac-клиент split-tunnel**. Ядро: **doc-2 — Ядро sing-box и CLI myvpn**.

Цель: агент прогоняет всё, что можно без сна Mac, без USB-flap и без живых секретов в git. Человек — только то, чего ИИ физически не может.

Секреты и реальные `.conf` в репо и в чат не класть. Фикстуры — фейковые ключи.

## Прототип проверок (уже есть)

В Utilits отлажен полный цикл для brew `macbook+home`:

`/Users/dmitrijstolarov/Documents/Utilits/local/alfred/wireguard/cycle-macbook-home.zsh`

Отчёт: `~/.cache/utilits-wg-cycle/latest.txt` (эталон PASS: 13 checks, Hub 200, DNS `10.57.0.100`, IP `77…`, restore WireGuard.app).

Для **myvpn** сделать аналог в этом репо: `tests/cycle-myvpn.zsh` (или `bin/myvpn test-cycle`), вызывающий `myvpn` вместо `apply-wg.zsh`. Логику фаз **скопировать**, не вызывать brew `wg-quick` в целевом продукте.

### Фазы цикла (обязательны)

| # | Действие | Зачем |
|---|----------|--------|
| 1 | Выключить brew/app WG и ядро myvpn | чистая база |
| 2 | `myvpn up` | тестируемое состояние |
| 3 | Проверки C*/L*/R* | отчёт |
| 4 | `myvpn down` | teardown |
| 5 | Восстановить **myvpn** (default) или WireGuard.app MacBook (`MYVPN_CYCLE_RESTORE=app`) | агент снова видит NAS/чат |

Фазы 4–5 — в `always` / `trap`: даже при FAIL проверок сеть агенту вернуть. **Агент из чата не делает `up`/`down` в обход цикла** — иначе рвётся `/Volumes/Nas` и сессия (урок соседнего чата).

### Ошибки прототипа (не повторять в myvpn)

Источник: тот же чат + отчёт FAIL → PASS.

1. **AppleScript admin:** нельзя `osascript -e "do shell script …${quoted}…"` — zsh рвёт кавычки. Нужен heredoc. `json.dumps(..., ensure_ascii=False)` — иначе `\uXXXX` ломает notify.
2. **`pkill` в admin-команде** без вложенных одинарных кавычек (`pkill -f wg-quick`, не `pkill -f '…'`).
3. **DNS в `macbook.conf`** (`1.1.1.1`) затирает CoreDNS → Hub 403. В myvpn: `DNS` из `.conf` **не** применять к системе; имена `*.digials.com` резолвить в `10.57.0.100` внутри ядра.
4. **Не путать endpoint и сервисы:** `94…/32` — только direct для handshake. Hub/ocode **не** через hairpin на `94…`, а через `10.57.0.0/24` (после DNS).
5. **Restore app:** искать туннель по имени из `scutil --nc list` надёжно; проверить Connected + публичный IP.

## Кто что гоняет

| Кто | Когда |
|-----|--------|
| ИИ | статика всегда; живой цикл — **через** `tests/cycle-myvpn.zsh` (человек запускает, агент читает `latest` отчёт) **или** агент запускает цикл только если заранее согласовано и restore гарантирован |
| Человек | запуск цикла; сон/USB-flap; Power Nap; глазами Alfred (после doc-3) |

ИИ не маскирует: нет conf / нет admin / цикл не запускали → **blocked**, не pass.

## Статика (всегда ИИ)

| ID | Проверка |
|----|----------|
| S1 | `sing-box check` / валидный JSON из фикстур |
| S2 | WG в JSON — `endpoints[]`, не outbound wireguard |
| S3 | Нет массового `networksetup -setdnsservers` на все сервисы / DNS= из WG; разрешён только TUN-DNS на `MYVPN_DNS_SERVICES` + clear на `down` |
| S4 | Нет Darwin `route -n monitor` и brew `wg-quick` как ядра |
| S5 | Ключи не в git, не в лог-шаблоне, `.conf` в gitignore |
| S6 | IPv6 в TUN/маршрутах выключен |
| S7 | LAN `192.168.3.0/24` → direct |
| S8 | Endpoint Home WAN `/32` → direct (handshake only) |
| S9 | Endpoint MacBook → direct |
| S10 | `10.13.13.0/24`, `10.57.0.0/24` → Home |
| S11 | Default → MacBook |
| S12 | Повторный `up` при живом pid — ошибка или restart, не второй демон |
| S13 | `down` убивает pid; повторный `down` без хаоса |
| S14 | Нет `.conf` / нет sing-box → exit ≠0 |
| S15 | `update-rules` кладёт dat в `~/.config/myvpn/` |
| S16 | Парсер игнорирует `DNS=` из `.conf` (не пишет в JSON как system DNS) |
| S17 | Admin/osascript (если есть): heredoc + `ensure_ascii=False`; без вложенных кавычек в pkill |
| S18 | Автозапуск: канон = app Login Item + helper; legacy LaunchAgent не обязателен в репо; пароль SMB не в файлах репо |
| S19 | `mount-nas` читает пароль только из Keychain (`local.myvpn.mac.nas` / `NAS`) |
| S20 | В коде/логах нет plaintext SMB password |

## Живая машина — кейсы цикла (из эталона PASS)

Имена как в `cycle-macbook-home.zsh`, чтобы сверять отчёты 1:1.

| ID | Проверка | Ожидание |
|----|----------|----------|
| C1 | `disconnect_all` | нет `10.8.0.3` / `10.13.13.2` (и нет старого brew) перед up |
| C2 | `iface` после `myvpn up` | ядро/TUN up; Home-сетки достижимы |
| C3 | `dns_backlog` | `dig +short backlog.digials.com` → `10.57.0.100` |
| C4 | `dns_ocode` | `ocode.digials.com` → `10.57.0.100` |
| C5 | `dns_system` | после up сервисы из `MYVPN_DNS_SERVICES` указывают на `MYVPN_TUN_DNS` (не `1.1.1.1` из WG conf); после down — Empty / DHCP |
| C6 | `hub_http` | `https://backlog.digials.com/` → **200** |
| C7 | `ocode_http` | 200 или 3xx |
| C8 | `public_ip_macbook` | IPv4 выход MacBook (`77…`), не `94…` |
| C9 | `ping_home_gw` | `10.13.13.1` |
| C10 | `ping_nas` | `10.57.0.100` |
| C11 | `endpoint_direct` | пиры `macbook=1` и `home=1` (handshake); при TUN `route get` к endpoint часто показывает utun — это норма, не FAIL |
| C12 | `restore_app_macbook` | после цикла WireGuard.app MacBook Connected + есть интернет |
| C13 | `mount_nas` | после up существует `/Volumes/Nas/Project` (или `/Volumes/Nas`) |
| C14 | `autostart_plist` | LaunchAgent установлен (`launchctl` list / plist в `~/Library/LaunchAgents`) — проверка после `install-autostart` |

## Живая машина (доп. L*)

| ID | Проверка |
|----|----------|
| L1 | Системный DNS: up → TUN DNS на `MYVPN_DNS_SERVICES`; down → Empty; без копирования `DNS=` из `.conf` |
| L2 | = C8 |
| L3 | = C9 + C10 |
| L4 | `ya.ru` (geoip:ru) не в utun MacBook |
| L5 | `status`: tun / macbook / home раздельно; не AND |
| L6 | Сбой URL публичного IP не роняет весь `status` |
| L7 | После `down` интернет через роутер |
| L8 | Нет orphan `wireguard-go` / `wg-quick` / второго sing-box |
| L9 | LAN `192.168.3.0/24` при up |
| L10 | pid-файл = живой PID |
| L11 | `curl --resolve backlog.digials.com:443:94.41.85.180` → 403 (hairpin плохо); через `10.57.0.100` → 200 — контроль, что DNS важен |

## Регрессии gv

| ID | Кто | Проверка |
|----|-----|----------|
| R1 | ИИ | нет wg-quick-style массового DNS; TUN-DNS только на allowlist сервисов (doc-2) |
| R2 | ИИ | status не AND двух пиров |
| R3 | ИИ | нет orphan после второго up |
| R4 | Человек | sleep → wake |
| R5 | Человек | USB-LAN / Wi‑Fi flap |
| R6 | ИИ (цикл) | Hub 200 при up (= C6) |
| R7 | ИИ (цикл) | endpoint `94…` direct (= C11); сервисы по `10.57` |

## Что только человек

- Power Nap / Deep Idle
- Физический display sleep + USB NIC
- Иконки Alfred `gv`
- Согласие на запуск цикла, если агент не должен сам рвать VPN

- Проверка автозапуска после **реального reboot** (LaunchAgent + mount)

## Отчёт

- Цикл: `~/.cache/myvpn-cycle/latest.txt` (формат как Utilits: `OVERALL` + список PASS/FAIL)
- Сдача задачи: `.backlog/artifacts/<TASK-ID>/test-report.md` со всеми ID

Без pass/blocked по S* и C* этап CLI не в QA.
