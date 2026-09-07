# myVPN-mac

Личный Mac-клиент split-tunnel (UI: **myVPN**). Не you2vpn.ru.

- Спека: `.backlog/docs/specs/doc-1 - Mac-клиент-split-tunnel.md`
- Prefix backlog: `MYMAC`
- Секреты WG: `~/.config/wireguard/` — не в git
- Alfred `gv`: репозиторий Utilits, позже вызывает CLI отсюда

## CLI (план)

```
myvpn up | down | status | update-rules
```

Ядро: sing-box. Код MVP ещё не в репо.
