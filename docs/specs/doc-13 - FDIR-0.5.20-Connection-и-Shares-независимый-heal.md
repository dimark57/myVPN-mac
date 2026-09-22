---
id: doc-13
title: 'FDIR 0.5.20: Connection и Shares независимый heal'
type: specification
created_date: '2026-09-11 07:40'
updated_date: '2026-09-11 07:40'
---
# FDIR 0.5.20: Connection и Shares независимый heal

Связано: **doc-12**, **doc-11**, **doc-10**, **doc-9**.

Цель релиза: **0.5.20**. Dual-WG / `render_config` / NE — **не трогать**.

**Отношение к SoT:** doc-13 **дополняет** doc-12. При конфликте по `HOME_*` heal и `--safe` unmount — **doc-13 wins**.

Слоган: **живой egress не рвать ради home; `--safe` не umount при open files.**

## Проблема (остаток 0.5.19)

1. `HOME_DOWN_MACBOOK_OK` / `HOME_PEER_DOWN` → `.restartAndMount`: чиним home — валим живой macbook + SMB.
2. Wake / `--safe` сначала зовёт graceful unmount, busy проверяет **после**. Если soft-umount прошёл при открытых файлах — Cursor/NAS падают, хотя том «ещё был».

`l0_already_ok` уже режет restart при зелёном L0. Дыра: PRIMARY `HOME_*` при красном home и живом egress; и unmount-before-busy.

## Решения

### 1. HOME не каскадит в VPN restart

| PRIMARY | 0.5.19 | 0.5.20 |
|---------|--------|--------|
| `HOME_DOWN_MACBOOK_OK` | `down→up+mount` | **`mount-nas --safe` только**. Интернет жив — `down→up` запрещён. Home peer сам не лечится (ручной On/Off или wake, если egress тоже мёртв). |
| `HOME_PEER_DOWN` | `down→up+mount` | **`.restart`** (как egress 0.5.18). Mount **не** в том же `performHeal`. Follow-up `--safe` если после verify `nas=0`. |
| `SLEEP_WAKE_STALE` | `.restartAndMount` в таблице | **`.restart`**. NAS — WakeRecover после канала (уже так). |

`skip=l0_already_ok` без изменений.

### 2. `--safe`: busy **до** любого unmount

`myvpn_nas_unmount_for_remount`: если `safe` и том в mount table и `myvpn_nas_volume_busy` → `NAS_BUSY`, **return 2**, без `diskutil unmount`.

UI `--remount` / без `--safe` — **не** трогать (человек сам жмёт «Перемонтировать»).

CLI `mount-nas --safe` exit 2 → Swift **не throw**, `HEAL_NAS skip=busy` (не verify_fail / не Safe Mode).

Wake по-прежнему зовёт `--safe` при `nas=1` (stale ghost). Busy-first закрывает yank; alive → no-op как сейчас.

### 3. Follow-up mount после VPN restart

После `.restart` + verify PASS: `followUpMountIfNASDown` для `MACBOOK_EGRESS_DOWN` **и** `HOME_PEER_DOWN`.

## Не менять

- NAS не hard DROP / `maybeRemountNASAfterFlap` / timeout→mount-only (doc-12)
- CONFIRM 20 с / grace / cooldown / AND `!macbook` (doc-11)
- `NAS_BUSY` → `.none` в doctor PRIMARY
- Dual-WG / NE / `render_config`

## Журнал

```
AUTO_HEAL skip=l0_already_ok primary=HOME_DOWN_MACBOOK_OK
HEAL_NAS skip=busy
WAKE_NAS mount-nas --safe reason=remount_stale_ok
AUTO_HEAL follow-up mount-nas --safe nas=0
```

## Тесты (статические)

| ID | Условие | Ожидание |
|----|---------|----------|
| T28 | `healKind HOME_DOWN_MACBOOK_OK` | `.mountNAS`, не restart |
| T29 | `healKind HOME_PEER_DOWN` | `.restart`, не `restartAndMount` |
| T30 | `nas.zsh` `--safe` | busy-check до `unmount` |
| T31 | pipeline follow-up | `HOME_PEER_DOWN` в follow-up |
| T32 | CLI `--safe` exit 2 | `HEAL_NAS skip=busy` |
| T33 | `healKind SLEEP_WAKE_STALE` | `.restart` |
| T34 | T23–T27 doc-12 | без регрессии |

## Out of scope

- Отдельный restart только home-peer (один sing-box)
- Авто-heal home при живом macbook (сознательный trade-off)
- Смена `--remount` UI
