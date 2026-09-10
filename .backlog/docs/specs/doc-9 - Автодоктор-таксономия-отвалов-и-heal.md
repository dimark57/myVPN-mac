---
id: doc-9
title: 'Автодоктор: таксономия отвалов и heal'
type: specification
created_date: '2026-09-08 08:25'
card: DRAFT-2
---
# Автодоктор: таксономия отвалов и heal

Связано: **DRAFT-2**, **doc-4 — Menu bar myVPN**, `lib/doctor.zsh`, `DropLogger.swift`.  
Источники паттернов: IPsec/WG DPD+data-plane probes (Fortinet, AWS S2S, cr0x failover), WireGuard keepalive/sleep, Apple NE health timer — адаптировано под **userspace WG в sing-box**, не NE PacketTunnel.

## 1. Принцип (индустрия → myVPN)

| Слой | Что ломается | Как ловят | Типичный heal |
|------|--------------|-----------|---------------|
| **Control plane** | handshake / peer / process | DPD-аналог: ping peer gw, last-handshake из логов, pid/tun | restart tunnel (`down`→`up`) |
| **Data plane** | туннель «up», трафик нет | overlay probe (ping gw / HTTP egress / DNS) | restart; иначе endpoint/firewall |
| **Underlay** | Wi‑Fi/LAN/WAN до endpoint | ICMP/UDP к endpoint **через en0**, path monitor | ждать сеть; не крутить VPN впустую |
| **App / conflict** | два VPN, DNS hijack, SMB stale | conflict check, DNS≠TUN, mount probe | выключить конфликт; `flush-dns`; `mount-nas --force` |
| **False alarm** | ICMP filter при живом egress | pub IP == endpoint при ping=0 | **не** heal |

Правила автомата (как у нормальных failover):

1. Разделять **underlay / overlay / app**.
2. Heal только после **N подряд** провалов (не один miss) — DropLogger `CONFIRM` 2/2.
3. **Cooldown / rate-limit** + **follow-up exempt** для mount после restart.
4. Сначала **снимок (doctor report)** в журнал, потом действие.
5. Не auto-heal при конфликте WG.app и при underlay down.

## 2. Каталог отвалов myVPN (PRIMARY + UI)

Колонки для **Настройки → Диагностика** (таблица/справка) и для auto-doctor decision table.

| Код (PRIMARY) | Симптом у человека | Детект (авто) | Журнал | Auto-heal (если галочка) | Не делать |
|---------------|-------------------|---------------|--------|--------------------------|-----------|
| `TUN_DOWN` | VPN «выкл», иконка off | pid/sing-box.pid=0, нет utun 172.19 | doctor + drops | `myvpn up` | — |
| `MACBOOK_EGRESS_DOWN` | Нет интернета при живом Wi‑Fi | tun=1, pub empty, underlay OK | doctor + drops | `down`→`up` + mount | underlay dead → см. UNDERLAY |
| `HOME_PEER_DOWN` / `HOME_DOWN_MACBOOK_OK` | Нет NAS/Hub, интернет ок или тоже мёртв | ping home gw fail | doctor + drops | `down`→`up`; затем `mount-nas --force` | — |
| `NAS_MOUNT_ONLY` | Home ок, шара не смонтирована | host ping ok, volume missing | doctor **WARN** | `mount-nas --force` | full VPN restart |
| `NAS_STALE` | SMB half-open после flap | listdir fail / stale | doctor **WARN** | `mount-nas --force` | — |
| `DNS_STALE` | digials/RU «не те» | Wi‑Fi DNS ≠ 172.19.0.1 | doctor **WARN** | `flush-dns` | down/up первым |
| `CONFLICT_WG_APP` | Рандомные отвалы/маршруты | WG.app Connected + tun | doctor | **нет** — notify «выключи WG.app» | auto down/up |
| `UNDERLAY_DOWN` | Нет Wi‑Fi / «сеть пропала» | default route missing **или** UDP Errno 49 / unreachable на endpoint | doctor + drops | **нет** — ждать path up | VPN restart |
| `HEALTHY_BUT_ENDPOINT_VIA_TUN` | Пока ок; риск после sleep | route endpoint → utun* | doctor WARN | нет (профилактика); при следующем drop — heal по PRIMARY | ложный restart |
| `HEALTHY_ICMP_FALSE_ALARM` | Кажется «peer down» | ping 10.8.0.1=0, но egress IP=endpoint | doctor PASS | **нет** | heal по ICMP |
| `EGRESS_NOT_VIA_MACBOOK` | IP «не тот» | pub ≠ macbook ep | doctor **WARN** | повторный doctor; heal только если remote DNS/egress реально мёртв | слепой restart |
| `MIXED` | Непонятно | низкая confidence | doctor | нет — только notify + отчёт | — |
| *(новый)* `SLEEP_WAKE_STALE` | После крышки «туннель есть — интернета нет» | wake event + egress fail в окне T | doctor | `down`→`up` | — |
| *(вне MVP)* `APP_CRASH` | Меню пропало | LaunchAgent / ExcUserFault | system log | relaunch app | путать с каналом |

`UNDERLAY_DOWN` выше `MACBOOK_EGRESS_DOWN`: Errno 49 / `route_default if=?` — локальный стек, не мёртвый VPS.

Паттерны (Cloudflare WAN + MikroTik hysteresis + k8s failureThreshold):

1. Разделять **underlay / overlay / app**.
2. Heal только после **N=2 подряд** подтверждений drop (DropLogger `CONFIRM`).
3. **Cooldown** ≥5 мин; **follow-up** mount/flush в окне 120с после restart — **без** cooldown (анти-каскад).
4. Сначала снимок doctor, потом действие.
5. Не auto-heal при `CONFLICT_WG_APP` и `UNDERLAY_DOWN`.
6. Журнал `drops.log`: FLAP-coalesce (45с), trim 800 строк, skip дубль HEALTHY DOCTOR.

## 3. Как детектить автоматически (pipeline)

```
status poll
        │
        ▼
DropLogger DIFF / FLAP (coalesce 45s)
        │
        ▼  N=2 CONFIRM (hysteresis)
notify + [галочка Автодиагностика]
        │
        ▼
myvpn doctor  →  report + latest + DOCTOR line
        │
        ▼  PRIMARY
decision table (§2 / §5)
        │
        ▼  [Автовосстановление + cooldown | follow-up 120s]
heal  →  AUTO_HEAL ok=0|1
        │
        ▼
notify + DoctorStatus в меню
```

**Probes:** tun/pid · ping gw · pub IP · UDP/ICMP endpoint (underlay) · DNS=TUN · NAS listdir · sing-box.log signals.

## 4. Журналы ошибок (куда писать / что читать)

| Артефакт | Путь | Роль |
|----------|------|------|
| Doctor report | `~/.cache/myvpn-doctor/report-YYYYMMDD-HHMMSS.txt` | полный снимок + VERDICT |
| Latest | `~/.cache/myvpn-doctor/latest.txt` | UI «открыть отчёт» |
| State / DIFF | `state.json`, `state.prev.json` | флапы между запусками |
| Drop journal | `drops.log`, `drop-state.json` | timeline 1→0 / `DOCTOR primary=` / AUTO_* — **не чистить** |
| sing-box | `~/.config/myvpn/sing-box.log` | handshake/failed/timeout |
| Menu bar | `~/Library/Logs/myvpn-menubar.log` | UI/auto-up/heal |
| Helper | `/var/log` / runtime helper logs | privileged up/down |

В UI Диагностики показать:

- список последних PRIMARY из `drops.log` + время;
- кнопки: Провести / Открыть отчёт / Отправить (как сейчас);
- галочки auto-doctor / auto-heal;
- краткая таблица «код → что делать» (этот doc, сжато).

## 5. Матрица исправлений (скрипт heal)

| PRIMARY | Команда | Условие |
|---------|---------|---------|
| `TUN_DOWN` | `myvpn up` | helper ok |
| `UNDERLAY_DOWN` | — | ждать Wi‑Fi/WAN |
| `MACBOOK_EGRESS_DOWN` | `down && up` → `mount-nas --force` | underlay OK |
| `HOME_*` | `down && up` → `mount-nas --force` | — |
| `NAS_*` | `mount-nas --force` | home=1; follow-up без cooldown ≤120с после restart |
| `DNS_STALE` | `flush-dns` | tun=1; follow-up без cooldown ≤120с |
| `CONFLICT_WG_APP` | — | только notify |
| `HEALTHY*` | — | — |
| else / low confidence | — | только doctor+notify |

**Cooldown:** ≥5 мин между AUTO_HEAL (кроме follow-up mount/flush); max 3 restart-heal / час.

**OVERALL ≠ heal.** Меню «Значительные» только при FAIL (tun / underlay / egress / home / conflict). `NAS_*` / `DNS_STALE` / `EGRESS_NOT_VIA_MACBOOK` = **WARN**. PASS не показывает residual `fail=N` (soft digials samples = WARN).

## 6. UI: Настройки → Диагностика (контракт для реализации)

1. Галочки: **Автодиагностика при отвале**, **Автовосстановление** (defaults ON; heal требует doctor ON).
2. Блок **«Коды отвалов»** — компактный список из §2 (PRIMARY → симптом → действие).
3. Блок **«Журнал»** — хвост `drops.log` (последние N) + ссылка на latest report.
4. Существующие: Провести диагностику / Открыть отчёт / Отправить разработчику.

## 7. Out of scope (MVP)

- Crash reporter процесса `myVPN.app` / ExcUserFault.
- Авто-Issues на GitHub.
- Смена канала / failover на второй VPS.
- Network Extension lifecycle (`handleTimerEvent`) — у нас userspace sing-box + menu bar watchdog.

## 8. AC для стройки (зеркало DRAFT-2)

- Таблица §2 отражена в UI Диагностики (справка/список).
- Auto pipeline §3 при галочках ON.
- Heal только по §5 + cooldown (ключ = PRIMARY, не OVERALL).
- Ложные ICMP (`HEALTHY_ICMP_FALSE_ALARM`) не триггерят heal.
- `NAS_*` / `DNS_STALE` в UI = WARN; каждый doctor пишет `DOCTOR` в drops.log.
