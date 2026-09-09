---
id: doc-10
title: 'FDIR: DesiredState, L0/L1/L2, Safe Mode'
type: specification
created_date: '2026-09-09 14:20'
target_version: '0.5.16'
---

# FDIR: DesiredState, L0/L1/L2, Safe Mode

Связано: **DRAFT-2**, **doc-9 — Автодоктор: таксономия отвалов и heal**, **doc-4**, `DropLogger.swift`, `AutoDoctor.swift`, `lib/doctor.zsh`.  
Цель релиза: **0.5.6** (wake always remount NAS). Dual-WG / `render_config` / NE (doc-5) — **не трогать**.
Первичный FDIR ship был **0.5.0**; 0.5.4 = channel-first; **0.5.6** = remount NAS даже при L0 `nas=1` (stale SMB).
**0.5.7** = wake `WAKE_HEAL` только `.restart` (без mount в helper); soft-success если L0 зелёный после timeout helper; `egressDead` = tun && ip пуст && !macbook; `skip=ip_ok_icmp_flap`; `CONFIRM skip=desired_off` + cap confirmCount (нет spam 3/2).
**0.5.8** = single-instance UI (`SingleInstance`): один `NSStatusItem` на `local.myvpn.mac`; `~/Applications` бьёт DerivedData; update terminate peers before relaunch; `UI_LAUNCH`/`UI_UPDATE` в drops; release/build не `open` stage.
**0.5.9** = observability: `UI_CMD` в drops; helper `forbidden peer_uid=`; doctor `helper_proto`; update SHA-256 sidecar + verify before install.
**0.5.10** = pipeline `AUTO_HEAL` soft-success (`AutoDoctor.isSoftHealOK`): helper timeout / verify lag при зелёном L0 → `ok=1 soft=1`, без ✕ / Safe Mode; wake использует тот же helper.
**0.5.11** = cooldown vs DROP: детальный `skip=cooldown … last_primary=`; bypass при *новом* PRIMARY; `EGRESS_PROBE empty keep_cached`; `AUTO_DOCTOR ok=1 soft=1` при timeout + L0 green.
**0.5.12** = live menu status: NAS SoT = mount table (не зависающий `fileExists`); poll 2с при открытом меню; rebuild во время busy; mount UI soft-ok если том уже жив.
**0.5.13** = fast up: helper/`MYVPN_QUIET` skip nested auto-nas; `after_up` только `--safe` (без blind `--force`); UI up watchdog 50с; skip mount если NAS уже жив.
**0.5.14** = UI «Перемонтировать» = `--remount` (unmount→mount, не `--safe` BUSY abort); mount SoT = mount table; soft umount then force.
**0.5.15** = полный `UI_CMD` на все клики (settings/send-report/quit/hotkey/autostart/…); диагноз «что нажали» = `drops.log`.
**0.5.16** = doctor soft: `runtime_local` на NAS = WARN (не FAIL); `autostart` off = INFO (preference); флаги не шумят HEALTHY.

Слоган: DropLogger = симптомы; L1 = дифференциальный диагноз; heal = протокол; Safe Mode = стоп + ground; commanded OFF = DNR.

## 1. Отношение к doc-9

| Документ | Роль |
|----------|------|
| **doc-9** | **PRIMARY catalog** + heal matrix (§2/§5) + UI Диагностики — **остаётся SoT кодов** |
| **doc-10** | **Control plane** FDIR: DesiredState, hysteresis/grace, cooldown, Safe Mode, L0/L1/L2, verify, NAS busy, flight/incidents |

**Supersedes** в doc-9: §1 правила автомата (N=2 poll), §3 pipeline hysteresis/cooldown wording, §5 cooldown «≥5 мин между AUTO_HEAL» без DesiredState/verify.  
**Не supersedes:** таблица PRIMARY (§2), матрица команд heal (§5 строки PRIMARY→команда), WARN/FAIL семантика, out-of-scope MVP (§7).

При конфликте control-plane правил — **doc-10 wins**. Код PRIMARY / `healKind(for:)` — **doc-9**.

## 2. DesiredState (ON/OFF)

Явный latch `desiredOn` (k8s replicas / OpenVPN HALT), не «suppress на 1 клик».

| Событие | `desiredOn` |
|---------|-------------|
| User / CLI `up`, Login auto-up, Settings On | `true` |
| User / CLI `down`, menu Off | `false` |
| Auto-heal `up` / `down→up` | **не** меняет (heal = restore к desired) |

Persist: `UserDefaults` + mirror в journal (`DESIRED on|off`).  
`TUN_DOWN` → heal `.up` **только если** `desiredOn == true`.

## 3. INTENTIONAL_OFF — no auto-heal

PRIMARY / событие: `INTENTIONAL_OFF` (или journal `skip=desired_off`).

- `desiredOn == false` → **запрещён** любой `AUTO_HEAL` (включая `TUN_DOWN→up`).
- Auto-doctor (L1) — **опционально log-only** (галочка doctor ON): снимок без heal.
- Не путать с outage: Off → DIFF `tun 1→0` **не** = `DROP_CONFIRMED` для pipeline heal.

## 4. Wall-clock CONFIRM + grace

Замена poll-count `N=2` из doc-9:

| Параметр | Значение | Когда |
|----------|----------|--------|
| **CONFIRM** | ≥ **20s** wall-clock устойчивого hard-drop | до `DROP_CONFIRMED` |
| **Grace** | **60s** | после `up` / `down` / heal / `NSWorkspace.didWake` |

В grace: Detect+L0 можно писать FLAP/DIFF; **pipeline heal skip=`grace`** (restart/`TUN_DOWN→up` через DropLogger).  
**Carve-out 0.5.1+:** `WakeRecover` после `didWake` **может** heal/pin/mount во время grace; DropLogger→pipeline restart по-прежнему `skip=grace`.

Wake (**0.5.6**): settle **10s** → L0 → при `tun` + (ip пуст **или** `!macbook`) — `SLEEP_WAKE_STALE` → `down→up` → pin если не restart → при `tun && (home||macbook)` — **всегда** `mount-nas --safe` (даже если L0 `nas=1` — stale ghost); иначе `WAKE_NAS skip=no_channel`. `HEAL_NAS` логируется (не silent `try?`).
Не: disconnect-on-sleep; не: kill на каждый wake; не: NAS до проверки канала.

## 5. ICMP peer ≠ DROP_CONFIRMED

Hard drops, которые **могут** открыть pipeline после CONFIRM:

- `tun` 1→0 (и только при `desiredOn`)
- `nas` hard drop (volume missing / listdir hard-fail — не ICMP)

**Не** `DROP_CONFIRMED`: ICMP peer flaps (`home` / `macbook` ping 1↔0) → только `DIFF` / `FLAP` (coalesce 45s).  
Egress/peer PRIMARY (`MACBOOK_EGRESS_DOWN`, `HOME_*`) ставит **L1 doctor** после hard trigger или ручного/auto doctor — не ICMP storm.

`HEALTHY_ICMP_FALSE_ALARM` (doc-9) — **не** heal.

## 6. Cooldown

| Kind | Правило |
|------|---------|
| Restart (`down→up*`) | **300s** после **verify PASS** (не после старта heal) |
| `TUN_DOWN` → `.up` | **exempt** от shared restart-cooldown, если `desiredOn` |
| Follow-up mount/flush | ≤120s после restart — без cooldown (как doc-9) |
| Hourly budget | max **3** restart-heals / час → иначе Safe Mode |

`AUTO_HEAL ok=1` **без** предшествующего verify PASS — запрещён (§9).

## 7. Safe Mode (circuit breaker)

Состояния: `Closed` → `Open(SafeMode)` → `HalfOpen` (один probe-heal) → Closed | Open.

**Вход в Safe Mode:**

- post-heal verify FAIL ×2, **или**
- hourly heal budget исчерпан при всё ещё FAIL

**В Safe Mode:** Detect + Isolate (L0/L1) работают; `AUTO_HEAL skip=safe_mode`; sticky notify.  
**Выход:** кнопка **Resume** в Настройки → Диагностика, **или** явный user On (`desiredOn=true` + HalfOpen/Closed по политике).

## 8. L0 / L1 / L2 budgets

| Layer | Budget | Содержание | Кто зовёт |
|-------|--------|------------|-----------|
| **L0** | ≤2.5s | StatusSnapshot + строка в `flight.jsonl` | poll / wake |
| **L1** | **hard ≤8s**, parallel | tun/utun, UDP, default route, pub IP (~2s), peer ping (~400ms), DNS=TUN, WG.app, log-tail signals | auto pipeline; `myvpn doctor` |
| **L2** | 60–90s | dig×3, hub, nas_alive, WAN ICMP, full sing-box check, полный report | `myvpn doctor --deep`; UI «Полная» |

CLI: **`myvpn doctor` = L1**; `--deep` = L2; `--json` → `primary` + `cid`.  
Auto path = **только L1** на отдельной queue (не общий `runCommand` 55s busyKey).  
Manual: «Провести»=L1, «Полная»=L2.

## 9. Post-heal verify → ok=1

После любого auto-heal:

1. Mini-L1: tun up + egress probe (pub / endpoint).
2. PASS → `AUTO_HEAL ok=1` + старт cooldown (§6).
3. FAIL → `ok=0` + счётчик к Safe Mode; **не** писать успешный heal.

## 10. NAS busy — no force

Перед `mount-nas --force`:

- если `/Volumes/Nas` смонтирован **и** есть open files / path = активный workspace → **не** force;
- soft remount **или** `skip` + notify / PRIMARY `NAS_BUSY`;
- helper `after_up_remount` — не force-blind при busy;
- UI timeout mount **120s**.

## 11. Observability: flight + incidents + cid

| Артефакт | Путь | Роль |
|----------|------|------|
| Flight | `~/.cache/myvpn-doctor/flight.jsonl` | ring ~2k lines / ~4h; L0 samples |
| Incident | `~/.cache/myvpn-doctor/incidents/inc_<id>.json` | на `DROP_CONFIRMED`: L0 window + L1 + heal + paths |
| Journal | `drops.log` | после CONFIRM все строки несут `cid=` |
| Reports | `report-*.txt` / `latest.txt` | как doc-9; в шапке `cid=` |

Retention: incidents **50**, reports **20**.  
`drops.log` / FLAP coalesce — без смены семантики doc-9 §6 (кроме `cid` и DesiredState lines).

## 12. Pipeline (target)

```
L0 sample
    │
    ▼
desiredOff? ──yes──► INTENTIONAL_OFF / skip heal (doctor log-only?)
    │ no
    ▼
grace? ──yes──► skip=grace
    │ no
    ▼
wall-clock CONFIRM ≥20s (hard: tun|nas only)
    │
    ▼
DROP_CONFIRMED + cid=…
    │
    ▼  [Автодиагностика]
L1 doctor (≤8s) → PRIMARY (doc-9)
    │
    ▼  [Автовосстановление + !safe_mode + cooldown policy]
heal → verify → ok=0|1 → flight + inc_*.json
    │
    ▼ fail budget
Safe Mode
```

Галочки auto-doctor / auto-heal — как doc-9 §6 (defaults ON; heal требует doctor ON).

## 13. AC / тесты (T5–T8 + инцидент 09.09)

Дополняют T1–T4 из DRAFT-2. Gate релиза **0.5.0**: сценарии 09.09 не воспроизводятся.

| ID | Шаг | Pass |
|----|-----|------|
| **T5** | Menu/CLI Off при галочках ON | `desiredOn=false`; **нет** `AUTO_HEAL up`; journal `skip=desired_off` / `INTENTIONAL_OFF` |
| **T6** | Off во время активного restart-cooldown | остаётся Off; cooldown **не** поднимает VPN |
| **T7** | Шторм ICMP home/macbook FLAP | только FLAP/DIFF; **нет** `DROP_CONFIRMED`; heal budget не жжётся |
| **T8** | Hard drop → L1 → heal | L1 ≤8s; один heal; `ok=1` только после verify PASS; в `drops`/`inc_*` есть `cid=` |

**Сценарии инцидента 09.09 (обязательные):**

1. Off → no AUTO_HEAL up  
2. Off while cooldown → stays Off  
3. ICMP FLAP storm → no DROP_CONFIRMED  
4. `MACBOOK_EGRESS_DOWN` → L1&lt;8s → one heal → verify  
5. Heal claimed ok but egress still fail → Safe Mode path (`ok=0`)  
6. Second DROP during grace → `skip=grace`  
7. NAS busy (open files) → no `--force` deadlock  

## 14. Out of scope (эта программа)

- Network Extension lifecycle (doc-5)  
- Смена dual-WG / sing-box rules  
- Бесконечный reconnect loop  
- Авто-GitHub Issues / crash reporter app  

## 15. Ship

- Версия: **0.5.0** via `macos/MyVPN/release.zsh 0.5.0` после Wave D + ручной T5–T8.  
- Hotfix после: `0.5.1+`.  
- Код-агентам: одна backlog-задача; PRIMARY из doc-9; control plane из **этого** doc.
