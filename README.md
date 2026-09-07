# myVPN-mac

Личный Mac-клиент split-tunnel (UI: **myVPN**). Не you2vpn.ru.

- Продукт: `.backlog/docs/specs/doc-1 - Mac-клиент-split-tunnel-создание.md`
- Prefix backlog: `MYMAC`
- Секреты WG: `~/.config/wireguard/` — не в git
- Alfred `gv`: репозиторий Utilits (контракт — **doc-3**)

## Стек

- CLI: `bin/myvpn` + `lib/` (zsh/Python) + Homebrew `sing-box` ≥ 1.12
- Menu bar: `macos/MyVPN/` → `~/Applications/myVPN.app` (runtime в `Contents/Resources/runtime`)
- Privileged helper: LaunchDaemon `local.myvpn.mac.helper` (один admin при установке)

## Быстрый старт

```bash
# CLI в PATH (локальный диск, не NAS)
cp -R bin lib share ~/.local/share/myvpn/   # или install-app.zsh
ln -sf ~/.local/share/myvpn/bin/myvpn ~/.local/bin/myvpn

myvpn update-rules
myvpn up
myvpn status   # tun= / macbook= / home= / nas= / ip=

# App + helper
macos/MyVPN/install-app.zsh
# В меню: Установить помощник (один пароль) → далее On/Off без пароля
```

## Команды CLI

```
myvpn up | down | status | update-rules | mount-nas [--force]
myvpn install-autostart | uninstall-autostart
myvpn autostart | auto-nas | helper-status | flush-dns | render
```

Спеки этапов: doc-2 (ядро), doc-3 (Alfred), doc-4 (menu bar), doc-5 (NE позже), doc-6 (тесты), doc-7 (UX списков RU).
