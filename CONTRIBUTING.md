# Contributing / building from source

**Пользователям приложение не собирают.** Дистрибутив — только [GitHub Releases](https://github.com/dimark57/myVPN-mac/releases) (`myVPN.app.zip`). Обновление у пользователя — кнопка **Проверить обновление** в меню.

Этот файл — для разработчиков и агентов.

## Dev layout

| Path | Role |
|------|------|
| `bin/myvpn`, `lib/` | CLI + sing-box glue |
| `macos/MyVPN/` | Menu bar app + helper |
| `.backlog/docs/specs/` | Engineering specs (agents + humans) |
| `AGENTS.md` | Agent/developer contour |

## Publish a release (единственный путь «деплоя»)

```bash
# нужен gh auth, remote dimark57/myVPN-mac
macos/MyVPN/release.zsh 0.3.0
```

Скрипт: `install-app.zsh` → zip → `gh release create` с asset `myVPN.app.zip`.  
После этого у пользователей кнопка **Проверить обновление** подтягивает релиз.

Локальная пересборка без публикации (`install-app.zsh`) — только для отладки на своей машине, не способ раздачи.

## CLI (local runtime)

```bash
myvpn update-rules
myvpn up | down | status | doctor | render | mount-nas
```

Runtime must live on local disk (`~/.local/share/myvpn` or inside the app bundle), not on a network volume that VPN may unmount.

## Tests

```bash
./tests/static-check.zsh
```

## Docs rule

User-facing copy → `README.md` only.  
Product/architecture decisions → `AGENTS.md` + `.backlog/docs/specs/doc-8 - …` in the same change as the code.
