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

## Publish a release (единственный путь доставки на Mac)

```bash
# нужен gh auth, remote dimark57/myVPN-mac
macos/MyVPN/release.zsh 0.3.1
```

Скрипт: сборка → zip → `gh release create` с asset `myVPN.app.zip`.  
На Mac пользователя (и на «проде» владельца): только **Проверить обновление** в меню.

**Не делать:** `install-app.zsh` / ручной `cp` в `~/Applications` как способ «закатить фикс». Это обход релиза и рассинхрон с GitHub. `install-app.zsh` — только локальная проверка сборки, если явно попросили «собери локально».

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
