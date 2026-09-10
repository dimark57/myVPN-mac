---
id: doc-12
title: 'FDIR 0.5.19: doctor не ломает живое соединение'
type: specification
created_date: '2026-09-11 01:05'
updated_date: '2026-09-11 01:05'
---
# FDIR 0.5.19: doctor не ломает живое соединение

Связано: **doc-11**, **doc-10**, **doc-9**, чат `4af62158` (отвалы vs Doctor / EISCONN / NAS).

Цель релиза: **0.5.19**. Dual-WG / `render_config` / NE — **не трогать**.

**Отношение к SoT:** doc-12 **дополняет** doc-11. При конфликте по NAS hard-DROP и timeout→restart — **doc-12 wins**.

Слоган: **живой L0 → никогда down→up; NAS flap ≠ VPN restart**.

## Проблема (логи 9–10 сен + NAS-чат)

1. Doctor **не** создаёт первичный обрыв (sing-box / EISCONN / empty pub-IP).
2. Doctor **усиливает**: `down→up` рвёт SMB → Cursor/NAS «отваливается», хотя PRIMARY мог быть ложным или NAS-only.
3. `nas 1→0` был **hard DROP** → L1 → при timeout форсировался `MACBOOK_EGRESS_DOWN` / `.restart` даже при живом туннеле.
4. Race: к моменту heal L0 уже зелёный, но restart всё равно шёл.

## Решения

### 1. NAS не hard DROP

`DropLogger.Sample.hardDropFrom`: только `tun↓` и `egress↓` (при живом tun).  
`nas 1→0` → DIFF/FLAP + **`HEAL_NAS flap=1` mount-nas --safe** (AppDelegate), без AUTO_DOCTOR pipeline.

### 2. Last-chance abort перед restart

Перед любым `.restart` / `.restartAndMount`: если `isSoftHealOK` (`tun && (ip ∨ macbook)`) → `AUTO_HEAL skip=l0_already_ok`, **не** `down→up`.

### 3. Timeout heal только для VPN-каналов

`handleDoctorFailure`: restart только если `channels` содержат `egress` или `tun`.  
Иначе: NAS → mount-only; пусто → skip.

### 4. L0 curl connect-timeout

`StatusSnapshot.publicIP`: `--connect-timeout 1` (как `lib/process.zsh`) — меньше ложных empty на blackhole.

## Не менять

- CONFIRM 20 с / N=2 / grace 60 / cooldown 300 / streak AND `!macbook` (doc-11)
- `HEALTHY_EGRESS_PROBE_FALSE_ALARM`
- WakeRecover путь

## Журнал

```
HEAL_NAS flap=1 action=mount-nas --safe
AUTO_HEAL skip=l0_already_ok primary=…
AUTO_HEAL skip=timeout_no_vpn_channel channels=…
AUTO_HEAL timeout→mount-only channels=nas
```

## Тесты (статические)

| ID | Условие | Ожидание |
|----|---------|----------|
| T23 | `hardDropFrom` | нет `prev.nas && !nas` |
| T24 | pipeline | `skip=l0_already_ok` |
| T25 | timeout | `timeout_no_vpn_channel` или `timeout→mount-only` |
| T26 | AppDelegate | `maybeRemountNASAfterFlap` / `HEAL_NAS flap=1` |
| T27 | StatusSnapshot | `--connect-timeout` |
