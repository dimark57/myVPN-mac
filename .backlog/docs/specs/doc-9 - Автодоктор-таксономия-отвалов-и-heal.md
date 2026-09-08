---
id: doc-9
title: 'Автодоктор: таксономия отвалов и heal'
type: specification
created_date: '2026-09-08 08:25'
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
2. Heal только после **N подряд** провалов (не один miss).
3. **Cooldown / rate-limit failback** — иначе flap хуже отвала.
4. Сначала **снимок (doctor report)** в журнал, потом действие.
5. Не auto-heal при конфликте WG.app и при underlay down.

## 2. Каталог отвалов myVPN (PRIMARY + UI)

Колонки для **Настройки → Диагностика** (таблица/справка) и для auto-doctor decision table.

| Код (PRIMARY) | Симптом у человека | Детект (авто) | Журнал | Auto-heal (если галочка) | Не делать |
|---------------|-------------------|---------------|--------|--------------------------|-----------|
| `TUN_DOWN` | VPN «выкл», иконка off | pid/sing-box.pid=0, нет utun 172.19 | doctor + drops | `myvpn up` | — |
| `MACBOOK_EGRESS_DOWN` | Нет интернета, NAS может жить | tun=1, pub IP empty, final=macbook | doctor + drops | `down`→`up` (1×) | если underlay endpoint ICMP=0 — сначала ждать WAN |
| `HOME_PEER_DOWN` / `HOME_DOWN_MACBOOK_OK` | Нет NAS/Hub, интернет ок или тоже мёртв | ping home gw fail | doctor + drops | `down`→`up`; затем `mount-nas --force` | — |
| `NAS_MOUNT_ONLY` | Home ок, шара не смонтирована | host ping ok, volume missing | doctor | `mount-nas --force` | full VPN restart |
| `NAS_STALE` | SMB half-open после flap | listdir fail / stale | doctor | `mount-nas --force` | — |
| `DNS_STALE` | digials/RU «не те» | Wi‑Fi DNS ≠ 172.19.0.1 | doctor | `flush-dns` | down/up первым |
| `CONFLICT_WG_APP` | Рандомные отвалы/маршруты | WG.app Connected + tun | doctor | **нет** — notify «выключи WG.app» | auto down/up |
| `HEALTHY_BUT_ENDPOINT_VIA_TUN` | Пока ок; риск после sleep | route endpoint → utun* | doctor WARN | нет (профилактика); при следующем drop — heal по PRIMARY | ложный restart |
| `HEALTHY_ICMP_FALSE_ALARM` | Кажется «peer down» | ping 10.8.0.1=0, но egress IP=endpoint | doctor PASS | **нет** | heal по ICMP |
| `EGRESS_NOT_VIA_MACBOOK` | IP «не тот» | pub ≠ macbook ep | doctor | повторный doctor; heal только если remote DNS/egress реально мёртв | слепой restart |
| `MIXED` | Непонятно | низкая confidence | doctor | нет — только notify + отчёт | — |
| *(новый, MVP2)* `UNDERLAY_DOWN` | Нет сети вообще | en0 down / endpoint ICMP=0 и нет default | drops | нет (ждать path up) | VPN restart |
| *(новый, MVP2)* `SLEEP_WAKE_STALE` | После крышки «туннель есть — интернета нет» | wake event + egress fail в окне T | doctor | `down`→`up` | — |
| *(вне MVP)* `APP_CRASH` | Меню пропало | LaunchAgent / ExcUserFault | system log | relaunch app | путать с каналом |

Уже есть PRIMARY в `lib/doctor.zsh` — auto-doctor **мапит** на них; новые коды — только если текущих не хватает (UNDERLAY / SLEEP_WAKE).

## 3. Как детектить автоматически (pipeline)

```
status poll (уже есть) / path change / wake
        │
        ▼
DropLogger 1→0  или  tun=1 && egress empty (N подряд)
        │
        ▼  [галочка Автодиагностика]
myvpn doctor  →  ~/.cache/myvpn-doctor/report-*.txt + latest.txt
        │
        ▼  PRIMARY + confidence
decision table (§2)
        │
        ▼  [галочка Автовосстановление + cooldown]
heal action  →  drops.log: AUTO_HEAL primary=… ok=0|1
        │
        ▼
notify + обновить DoctorStatus в меню
```

**Probes (data-plane, не только «туннель up»):**

| Probe | Цель |
|-------|------|
| tun / pid | control: процесс жив |
| ping channel gw (10.8.0.1 / 10.13.13.1) | overlay peer |
| pub IP (ifconfig.me) vs final endpoint | egress через macbook |
| ICMP/UDP endpoint на en0 | underlay до VPS/home |
| DNS = TUN | hijack |
| NAS listdir | SMB data-plane |
| sing-box.log signals (handshake/failed/timeout) | усилитель confidence |

Индустрия: DPD ≠ полезность канала — нужен **overlay probe**. У нас уже так в doctor.

## 4. Журналы ошибок (куда писать / что читать)

| Артефакт | Путь | Роль |
|----------|------|------|
| Doctor report | `~/.cache/myvpn-doctor/report-YYYYMMDD-HHMMSS.txt` | полный снимок + VERDICT |
| Latest | `~/.cache/myvpn-doctor/latest.txt` | UI «открыть отчёт» |
| State / DIFF | `state.json`, `state.prev.json` | флапы между запусками |
| Drop journal | `drops.log`, `drop-state.json` | timeline 1→0 / AUTO_* |
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
| `MACBOOK_EGRESS_DOWN` | `myvpn down && myvpn up` | underlay endpoint ICMP=1 (или skip wait ≤30s) |
| `HOME_*` | `down && up` → `mount-nas --force` | — |
| `NAS_*` | `mount-nas --force` | home=1 |
| `DNS_STALE` | `flush-dns` | tun=1 |
| `CONFLICT_WG_APP` | — | только notify |
| `HEALTHY*` | — | — |
| else / low confidence | — | только doctor+notify |

**Cooldown:** ≥5 мин между AUTO_HEAL; max 3 heal / час → потом «нужен человек» + отчёт.

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
- Heal только по §5 + cooldown.
- Ложные ICMP (`HEALTHY_ICMP_FALSE_ALARM`) не триггерят heal.
