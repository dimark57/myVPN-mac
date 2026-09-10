---
id: doc-11
title: 'FDIR 0.5.18: ложный egress, timeout-heal, L1 budget'
type: specification
created_date: '2026-09-10 05:48'
updated_date: '2026-09-10 05:59'
card: DRAFT-3
---
# FDIR 0.5.18: ложный egress, timeout-heal, L1 budget

Связано: **DRAFT-3**, **DRAFT-2**, **doc-10 — FDIR: DesiredState, L0/L1/L2, Safe Mode**, **doc-9 — Автодоктор: таксономия отвалов и heal**, `DropLogger.swift`, `AutoDoctorPipeline.swift`, `AutoDoctor.swift`, `AppDelegate.swift`, `MyVPNCLI.swift`, `lib/doctor.zsh`, `lib/process.zsh`.

Цель релиза: **0.5.18**. Dual-WG / `render_config` / NE (doc-5) / sing-box UDP stack — **не трогать**.

**Отношение к SoT:** doc-11 **supersedes** doc-10 §5 (hard DROP по пустому pub-IP), §8 (L1 wall-clock + kill process group), §9 (timeout ≠ no-heal), §11 (каналы DROP + закрытие incident), healKind `MACBOOK_EGRESS_DOWN` = `.restart` (не `+mount`). Остальное doc-10 / PRIMARY catalog doc-9 — без изменений. При конфликте по этим пунктам — **doc-11 wins**.

Слоган патча: **AND сигналов, не новый HTTP; timeout → heal только если L0 красный; kill group, не ждать DNS curl; журнал, которому можно верить**.

---

## 0. Зачем / инцидент 09–10.09 (прод 0.5.17)

Прод `~/Applications/myVPN.app` v0.5.17. Журнал: `~/.cache/myvpn-doctor/drops.log`, `inc_*.json`, `report-*.txt`.

| Когда (локаль) | Что | Класс |
|---|---|---|
| 01:14, 02:21, 02:27 | `ifconfig.me` пуст → DROP → `down→up+mount`; overlay часто оживал *во время* L1 | реальный зомби **или** самовосстановление до heal |
| 05:47→06:22 | DROP → L1 doctor **35 мин** (`ms=2088475`); gaps 18+17 мин внутри `doctor.zsh` | hang (sleep + `DispatchTime` + дети zsh) |
| **07:22** | DROP → `AUTO_DOCTOR ok=0 err=timeout` → **heal нет** до wake 09:34 | recovery-дыра ~2 ч |
| **10:15** | DROP при `ping_macbook_gw=PASS`, `dns_remote=PASS`, `udp=PASS`; единственный FAIL = empty ifconfig.me → restart+mount 120с → `verify_fail` | **ложный** heal, усугубил |

sing-box при реальных зомби: `sendmsg: socket is already connected` (EISCONN). Это известный macOS/BSD `sendmsg` на connected UDP + stale bind после sleep/NAT (sing-box #1415). Heal `down→up` для **этого** класса — правильный. Детектор 0.5.17 (пустой ifconfig.me) орёт чаще, чем EISCONN.

0.5.7 уже имел conjunct `egressDead = tun && ip пуст && !macbook`. 0.5.17 ослабил до «2 пустых curl» независимо от ICMP — это и дало 10:15. **0.5.18 возвращает conjunct 0.5.7**, не изобретает третий HTTP.

---

## 1. Исследование: что нельзя делать

Проверено по открытым источникам (не «мнение модели»). Выводы — **отказ от части идей из разбора логов**, иначе патч ухудшит.

### 1.1 Не добавлять второй HTTP IP-probe на L0 (16 с)

Индустрия (transmissionvpn PR #35, gluetun #2923) лечит ложные HTTP/ICMP **двумя хостами, оба должны упасть**. Но:

- `curl --max-time` **не** убивает блокирующий `getaddrinfo` (curl #2975, #11062, everything-curl Timeouts). Apple curl без c-ares: DNS hang 5–20 с после «Resolving timed out».
- `https://1.1.1.1/cdn-cgi/trace` как «онлайн» даёт ложные down: DoH-блок, неверный IP `104.18.0.0`, даунтрейс (cloudflare-ddns #202/#216, project-nomad #258).
- Второй curl на каждом тике = больше зависаний `workQueue` (serial), не меньше ложных.

**Решение 0.5.18:** второй HTTP **запрещён** на L0. Overlay ICMP `10.8.0.1` уже есть, 400 мс, без DNS. AND с ним.

L1 `dns_remote_sample` — уже overlay data-plane (как gluetun «full» TCP+TLS/DNS, только реже). Его использовать как **вето PRIMARY**, не как новый poll.

### 1.2 Не крутить VPN от одного HTTP miss

Cloudflare WAN: tunnel Down только после **трёх** неудачных probe; часть success → Degraded, не Down. gluetun: ICMP каждые 15 с, **3 consecutive**; полный TCP+TLS раз в 5 мин, 2 retry. OpenVPN keepalived: `fall 3`.

0.5.17: 2 пустых ifconfig.me (~16–32 с) → hard DROP при живом ICMP. Это агрессивнее Cloudflare/gluetun и ломает 10:15.

**Не** поднимать streak 2→4 «на всякий случай»: при реальном EISCONN ICMP и так падает; лишние 32 с только затягивают recovery. AND с `!macbook` на тех же тиках достаточно.

### 1.3 Не heal вслепую на любой timeout doctor

07:22: timeout + L0 красный → abort без heal — дыра. Обратная ошибка: timeout из-за NAS/`ping_nas`, overlay зелёный → restart живого туннеля.

Уже есть `isSoftHealOK` (0.5.10/0.5.11). **Timeout → heal только если soft-OK ложен** (`tun && !ip && !macbook`). Иначе `AUTO_DOCTOR ok=1 soft=1` как сейчас.

### 1.4 Не mount на каждый egress restart

Workspace = `/Volumes/Nas`. Каждый `down→up+mount` → `NAS_BUSY` или 120 с timeout → `verify_fail` (10:15). doc-10 §10 уже запрещает force. 0.5.7 wake heal = `.restart` без mount в helper — прецедент.

`HOME_*` / `NAS_*` — mount **остаётся**. Только `MACBOOK_EGRESS_DOWN` / `SLEEP_WAKE_STALE` → `.restart`. Follow-up `--safe` если после verify `nas=0` (окно 120 с, как doc-10 §6).

### 1.5 Не детектить EISCONN по хвосту лога на L0

10:15 report всё ещё содержал wake-строки `can't assign requested address` с 09:34. Log-tail как DROP = ложные. EISCONN — **evidence** в L1, не PRIMARY сам по себе, если overlay DNS/ICMP жив.

### 1.6 Sleep ≠ «ещё 20 с CONFIRM»

`DispatchTime` / `mach_absolute_time` **останавливаются** при sleep крышки (Apple Forums, QA1340). Wall-clock `Date()` при wake прыгает → CONFIRM 00:09→DROP 00:47 без `WAKE`. Doctor timeout 10 с не тикает, процесс живёт 35 мин.

**На `didWake`:** сбросить CONFIRM; abort in-flight auto-doctor; путь = существующий `WakeRecover` (10 с settle). Не второй pipeline.

L1 timeout в Swift: **wall** (`Date` / `DispatchWallTime`), не только `DispatchTime.now()+10`. После wake просроченный doctor убивается сразу, не дописывает отчёт 17 мин.

---

## 2. L0: hard egress DROP (supersedes 0.5.17 clear_cached)

`EGRESS_PROBE` остаётся. Меняется **условие clear**.

Счётчик `egressEmptyAndPeerDownStreak` (новый смысл `egressEmptyClearAfter=2`):

Инкремент **только** если в одном sample: `includePublicIP && tun && ip.isEmpty && !macbook`.

Сброс streak, **keep_cached**, если любой из: `!ip.isEmpty` **или** `macbook==true`.

`clear_cached` (ip → empty → `hardDrop` egress) — только при streak ≥ 2 **подряд** таких тиков.

Лог:

- `EGRESS_PROBE empty keep_cached=… streak=1/2 peer=0` — кандидат
- `EGRESS_PROBE empty keep_cached=… skip=peer_up` — **не** инкремент (10:15)
- `EGRESS_PROBE empty clear_cached=… streak=2` — как сейчас, затем DIFF egress 1→0

ICMP home/macbook по-прежнему **не** hard DROP (doc-10 §5). Меняется только egress.

**Почему не усугубит EISCONN:** внутренний ping `10.8.0.1` идёт через тот же userspace WG. Stale connected UDP (sing-box #1415) валит handshake → ICMP gw падает вместе с overlay. 01:14/ночь: `icmp_mb_gw=0` + empty IP. 10:15: `icmp_mb_gw=1` — veto.

Остаточный риск: ICMP к 10.8.0.1 отфильтрован **всегда**. На этом Mac в HEALTHY `icmp_mb_gw=1` (latest.txt). Если когда-нибудь фильтр постоянен — L1 `HEALTHY_ICMP_FALSE_ALARM` уже есть; L0 просто не будет egress-DROP (туннель жив по DNS). Не лечить это в 0.5.18 отдельным HTTP.

CONFIRM 20 с / N=2 / grace 60 с — **без изменений**.

На `NSWorkspace.didWake`: `confirmBaseline=nil`, streak=0. Не эскалировать wall-clock sleep в DROP. WakeRecover без гонки с pipeline.

`CONFIRM 1/2` и `2/2` — **по одной строке** на переход (не каждый poll при открытом меню). Поведение автомата не менять.

---

## 3. L1 PRIMARY (doc-9 catalog + doctor.zsh)

Новый код (PASS, **не** auto-heal), рядом с `HEALTHY_ICMP_FALSE_ALARM`:

| Код | Симптом | Детект | Heal |
|---|---|---|---|
| `HEALTHY_EGRESS_PROBE_FALSE_ALARM` | ifconfig.me пуст, overlay жив | `tun=1`, `pub` empty, **и** (`dns_remote` PASS **или** `ping_macbook_gw=1`) | нет |

Порядок в `lib/doctor.zsh` **до** ветки `tun==1 && pub empty → MACBOOK_EGRESS_DOWN`:

1. `CONFLICT_WG_APP` / `TUN_DOWN` / `INTENTIONAL_OFF` / `UNDERLAY_DOWN` — как сейчас.
2. Если `tun && pub empty` **и** (`dns_ok_remote` или `macbook_icmp`): `HEALTHY_EGRESS_PROBE_FALSE_ALARM` (не FAIL).
3. Иначе `tun && pub empty` → `MACBOOK_EGRESS_DOWN` (реальный зомби: 07:22/ночь).

`udp send ok=1` **не** вето: UDP send на connected socket может «успеть» при мёртвом handshake (тот же класс, что #1415).

`log_signals` EISCONN — evidence в Interpretation, не PRIMARY.

`ping_nas` на L1 **убрать** (nas_fast / mount table уже есть). Ночной gap 06:05→06:22. L2 `--deep` — как сейчас.

Пинги L1 — **параллельно** (как `myvpn_cmd_status`), не 4× sequential. Budget: hard **wall ≤8 с** (doc-10 §8), Swift 10 с с запасом.

`myvpn_public_ip`: `-4 --connect-timeout 1 --max-time 2`. Пустой/не-IPv4 ответ = empty. **Не** добавлять второй URL в 0.5.18.

---

## 4. Timeout / kill / pipeline (supersedes «timeout → notify only»)

### 4.1 Process group

`MyVPNCLI.run`: новый process group (`setpgid` / `posix_spawn` SETPGROUP). По timeout: `killpg(SIGTERM)`, через 0.5 с `SIGKILL`. Не `terminate()` только на zsh — дети ping/curl/dig переживают (35 мин отчёт). Helper **не** в этой группе.

Deadline: `Date() + timeout` **или** `DispatchWallTime`, не один `DispatchTime`.

### 4.2 Pipeline catch

```
doctor throws timeout
    │
    ├─ isSoftHealOK(.restart)  → AUTO_DOCTOR ok=1 soft=1, heal skip   (как 0.5.11)
    │
    └─ иначе, desiredOn, !grace, !safe_mode:
           AUTO_DOCTOR ok=0 err=timeout
           AUTO_HEAL kind=.restart (без mount)   // 07:22 дыра
           verify / soft-OK как §9 doc-10
           attachHeal + INCIDENT end (не heal:null)
```

Не вызывать полный L1 повторно. Не heal при `desiredOff`. Не обходить Safe Mode / restart-cooldown.
Любой выход pipeline (soft / timeout / skip / heal ok|fail) зовёт `IncidentStore.attachHeal` и `INCIDENT end` — **запрещён** `heal: null` после `INCIDENT begin`.

### 4.3 Watchdog «stuck dead» (один раз на cid)

После `DROP_CONFIRMED`, если pipeline закончился **без** успешного heal (`timeout` no-soft / `verify_fail` / `skip=in_flight`) и L0 всё ещё `desiredOn && tun && !macbook && ip empty` ≥ **60 с**: один `AUTO_HEAL .restart` с `skip` если cooldown/Safe Mode.

Максимум **1** watchdog на `cid`. Не бесконечный reconnect (doc-10 §14).

Это закрывает: timeout-heal не стартовал из-за `busyKey`; или verify_fail после mount, overlay мёртв, ребра 1→0 больше нет.

### 4.4 Wake vs in-flight doctor

`didWake` → abort auto-doctor in-flight (kill group) → `WakeRecover`. Не два restart подряд: если WakeRecover уже `.restart`, pipeline skip=`wake`.

---

## 5. Heal matrix (узкий diff doc-9 §5)

| PRIMARY | 0.5.17 | 0.5.18 |
|---|---|---|
| `MACBOOK_EGRESS_DOWN` | `down→up+mount` | **`down→up`** |
| `SLEEP_WAKE_STALE` | restart (+ wake mount отдельно) | без изменений (WakeRecover) |
| `HOME_PEER_DOWN` / `HOME_DOWN_MACBOOK_OK` | `down→up+mount` | без изменений |
| `NAS_*` | mount | без изменений |
| `HEALTHY_EGRESS_PROBE_FALSE_ALARM` | — | **не heal** |

После egress `.restart` + verify PASS: если L0 `nas=0` — follow-up `mount-nas --safe` в окне 120 с (doc-10 §6), не в том же `performHeal`.

`maxHealsPerHour=6`, cooldown 300 с — без изменений.

---


## 6. Observability (drops + incident; не дашборд)

Цель: T9–T22 доказываются `rg` по `drops.log` / одному `inc_*.json`. Не UI, не метрики, не EISCONN-счётчик по хвосту лога.

### 6.1 Каналы DROP — не `contains("VPN")` первым

Баг 0.5.17: label `нет интернета через VPN` содержит `"VPN"` → `channels: ["tun"]` при живом tun (`inc_…04750`).

Порядок match в `DropLogger.maybeFire` (первый **точный** класс, не substring «VPN»):

| Label | channel |
|---|---|
| содержит `интернета` | `egress` |
| содержит `NAS` | `nas` |
| содержит `выключился` (VPN процесс/tun) | `tun` |
| иначе | `other` |

В `DROP_CONFIRMED` и `INCIDENT begin` — `channels=egress` (csv). Несколько hard-drop в одном CONFIRM — csv без дублей.

### 6.2 Строки drops.log (канон grep)

```
DROP_CONFIRMED нет интернета через VPN channels=egress cid=inc_…
AUTO_DOCTOR primary=… overall=… layer=L1 ms=… killed=0|1 cid=…
AUTO_HEAL ok=0|1 action=down→up primary=… cid=…
INCIDENT end cid=… outcome=heal_ok|timeout_heal|soft|false_alarm|verify_fail|skip_… recovery_ms=…
EGRESS_PROBE empty keep_cached=… skip=peer_up
```

`killed=1` — process group убит по wall timeout (T16). `recovery_ms` — от `DROP_CONFIRMED` до L0 `tun && (ip nonempty ∨ macbook)` после heal/soft, или до `INCIDENT end` если так и не ожил.

`outcome=false_alarm` — L1 PRIMARY `HEALTHY_*` (heal не звали).

### 6.3 Incident JSON

После begin поле `heal` не остаётся `null`. Обязательные ключи к `end`:

```json
{
  "channels": ["egress"],
  "ts_end": "ISO-8601",
  "outcome": "timeout_heal",
  "recovery_ms": 8400,
  "l1": { "primary": "…", "ms": 10012, "killed": 1 },
  "heal": { "attempted": true, "ok": 1, "action": "down→up" }
}
```

Timeout-catch 0.5.17 не вызывал `attachHeal` → `heal: null`. **Запрещено.**

### 6.4 flight.jsonl

Если `includePublicIP && ip.isEmpty` — писать `"pub_empty": 1` (сейчас ключ `pub_cached` просто отсутствует: в window не видно, был ли probe). Не писать сам IP при empty. Остальной flight без изменений (ring 2k).

### 6.5 Не входит

Дашборд, экспорт, GitHub Issues, парсинг EISCONN в счётчик, второй HTTP, расширение menubar.log.

## 7. Что сознательно не входит

- Смена dual-WG, keepalive, sing-box gVisor UDP reconnect (это корневой EISCONN; отдельный трек, не 0.5.18).
- Замена `ifconfig.me` на Cloudflare trace / ipify на L0.
- Снижение CONFIRM &lt;20 с, streak &lt;2.
- Auto-heal `UNDERLAY_DOWN` / `CONFLICT_WG_APP`.
- Crash reporter / Network Extension.
- Бесконечный retry.
- Дашборд / экспорт метрик / GitHub Issues с инцидентов.

---

## 8. Файлы (ориентир, не пошаговая стройка)

- `AppDelegate.swift` — streak AND `!macbook`; log `skip=peer_up`; watchdog 60 с / 1× cid.
- `DropLogger.swift` — CONFIRM 1 строка на переход; reset на wake; **channels match §6.1**; `DROP_CONFIRMED … channels=`.
- `AutoDoctor.swift` — `healKind(MACBOOK_EGRESS_DOWN)=.restart`; catalog row нового PRIMARY.
- `AutoDoctorPipeline.swift` — timeout → `.restart` если !soft; **каждый выход → attachHeal + INCIDENT end**.
- `IncidentStore.swift` — `ts_end`, `outcome`, `recovery_ms`; `l1.killed`.
- `FlightRecorder.swift` — `pub_empty=1` при пустом probe.
- `MyVPNCLI.swift` — process group + wall deadline.
- `WakeRecover.swift` — abort in-flight doctor.
- `lib/doctor.zsh` — ветка false-alarm; skip `ping_nas` на L1; parallel ping.
- `lib/process.zsh` — curl `--connect-timeout 1`.
- `tests/fdir-policy.zsh` — новые grep/AC включая T20.
- Settings Диагностика: строка каталога нового кода (doc-9 §6).

---

## 9. AC / тесты (ворота 0.5.18)

Дополняют T5–T8 doc-10. Gate: сценарии 10.09 не воспроизводятся **и** ночной EISCONN всё ещё ловится. T9–T18 + **T20–T22** (журнал).

| ID | Шаг | Pass |
|----|-----|------|
| **T9** | L0: tun=1, macbook=1, 3 пустых pub-IP подряд | `keep_cached skip=peer_up`; **нет** DIFF egress 1→0; **нет** DROP |
| **T10** | L0: tun=1, macbook=0, 2 пустых pub-IP | `clear_cached` → CONFIRM → при wall≥20с DROP `нет интернета` |
| **T11** | L1: pub empty + `dns_remote` PASS + ping gw | PRIMARY `HEALTHY_EGRESS_PROBE_FALSE_ALARM`; overall PASS; **нет** AUTO_HEAL |
| **T12** | L1: pub empty + ping gw FAIL + dns fail, underlay ок | `MACBOOK_EGRESS_DOWN` → AUTO_HEAL `.restart` **без** mount; verify по tun/ip\|macbook |
| **T13** | Doctor timeout 10 с, L0 красный (tun, !macbook, ip empty) | `AUTO_DOCTOR ok=0 err=timeout` **и** `AUTO_HEAL action=down→up` (не `+mount`) |
| **T14** | Doctor timeout, L0 зелёный (macbook или ip) | `AUTO_DOCTOR ok=1 soft=1`; **нет** restart |
| **T15** | `didWake` во время doctor | doctor killed; CONFIRM reset; один `WAKE_HEAL`, нет второго DROP из wall-clock sleep |
| **T16** | `MyVPNCLI.doctor` timeout | zsh **и** ping/curl потомки мертвы (не 35 мин report) |
| **T17** | После egress restart nas=0 | follow-up `--safe` ≤120 с; при nas=1 — skip mount |
| **T18** | Watchdog: DROP + timeout-heal не стартовал, 60 с красный L0 | ровно один `.restart`; второй не раньше cooldown |
| **T19** | Регрессия T5–T8 doc-10 | Off / ICMP FLAP / grace / NAS_BUSY — без изменений |
| **T20** | DROP egress (текст «нет интернета через VPN») | `channels=egress` в DROP_CONFIRMED **и** `inc_*.json`; не `tun` |
| **T21** | Любой выход pipeline (timeout / soft / HEALTHY / heal) | `INCIDENT end … outcome=… recovery_ms=`; JSON `heal` не `null` |
| **T22** | Пустой pub-IP при macbook=1 | flight: `pub_empty=1`; drops: `skip=peer_up` |

Ручной QA на этом Mac: крышка sleep 30+ мин; «сайт не открывается» при живом ICMP (не должен рвать VPN); реальное выдёргивание overlay (если можно) — heal &lt;30 с без NAS timeout.

---

## 10. Anti-worsen чеклист для code-агента

Перед сдачей — все «нет»:

1. Нет нового HTTP URL на poll 16 с.
2. Нет `clear_cached` при `macbook=1`.
3. Нет AUTO_HEAL на `HEALTHY_*`.
4. Нет `+mount` в `performHeal` для `MACBOOK_EGRESS_DOWN`.
5. Нет heal на doctor timeout при зелёном L0.
6. Нет второго pipeline на wake параллельно WakeRecover.
7. Нет снижения CONFIRM/grace/cooldown.
8. `tests/fdir-policy.zsh` зелёный.
9. Нет дашборда / EISCONN-счётчика по логу / второго HTTP.
10. Нет `heal: null` после `INCIDENT begin`; DROP «нет интернета» не `channels=tun`.

---

## 11. Ship

Версия **0.5.18** через канон `cd` / `macos/MyVPN/ship.zsh` (не `ditto` в `~/Applications`).

После merge: одна строка в шапку **doc-10** (`0.5.18 = doc-11 …`) — не переписывать control-plane целиком.

---

## Источники (исследование)

- Cloudflare One — [WAN tunnel health](https://developers.cloudflare.com/cloudflare-one/troubleshooting/wan/tunnel-health/): 3 probe retries before Down.
- gluetun [PR #2923](https://github.com/qdm12/gluetun/pull/2923): ICMP 15s × 3 consecutive; TCP+TLS every 5 min.
- transmissionvpn [PR #35](https://github.com/magicalyak/transmissionvpn/pull/35): dual host, both must fail.
- curl [issue #2975](https://github.com/curl/curl/issues/2975), [#11062](https://github.com/curl/curl/issues/11062); [everything curl — Timeouts](https://everything.curl.dev/usingcurl/timeouts.html): `--max-time` vs blocking DNS.
- Apple: mach_absolute_time stops in sleep ([forums](https://developer.apple.com/forums/thread/106199)); [QA1340](https://developer.apple.com/library/archive/qa/qa1340/) wake notifications.
- sing-box [#1415](https://github.com/SagerNet/sing-box/issues/1415): stale connected UDP after network change.
- FreeBSD/macOS `sendmsg` EISCONN on connected UDP (Envoy [#38171](https://github.com/envoyproxy/envoy/issues/38171), Haivision SRT #2178).
- Не единственный online-check: [1.1.1.1/cdn-cgi/trace](https://github.com/Crosstalk-Solutions/project-nomad/issues/258), cloudflare-ddns #202/#216.
