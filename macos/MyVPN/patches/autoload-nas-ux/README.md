# Patch: autoload + NAS UX

Локальный патч menu bar (когда NAS недоступен для правки/сборки).

## Что даёт

- При старте `myVPN.app` сразу поднимает VPN (если helper есть).
- В меню видно `NAS: смонтирован|не смонтирован`.
- Пока идёт auto-up: `myVPN: включаю…`, затем `NAS: ожидание…` / `NAS: монтирую…`.

## Как применить (локальный диск)

```bash
# дерево сборки уже в ~/.local/share/myvpn/macos-src
# или скопируйте macos/MyVPN → туда и поправьте SRC_TREE в patch.zsh
zsh ~/.local/share/myvpn/patches/autoload-nas-ux/patch.zsh
```

Канон после remount: исходники уже в `macos/MyVPN/MyVPN/` — доставка только через GitHub:

```bash
macos/MyVPN/release.zsh [version]
# затем Настройки → Update (не install-app.zsh — отключён)
```

## Файлы

| Файл | Роль |
|------|------|
| `files/AppDelegate.swift` | auto-up + loading UX |
| `files/MyVPNHelper.swift` | `waitUntilAvailable` — Login Item ждёт socket helper |
| `files/StatusSnapshot.swift` | `nasLine`, без nas в peers |
| `files/RulesStatus.swift` | `notifyStamp` |
| `files/MyVPNCLI.swift` | `mountNAS(force:)` |
| `files/generate-xcodeproj.py` | RulesStatus + StickyMenu в sources |

Дата: 2026-09-08.
