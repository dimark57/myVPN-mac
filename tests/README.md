# Tests (doc-6)

- `static-check.zsh` — статика без секретов (фикстуры + render + sing-box check).
- `auto-up-boot-race.zsh` — регрессия auto-up при логине (ожидание helper socket; **без** live down/up).
- `cycle-myvpn.zsh` — живой цикл: down → up → C* → down → restore (`MYVPN_CYCLE_RESTORE=myvpn|app`).
- `fixtures/` — фейковые `macbook.conf` / `home.conf` (DNS=1.1.1.1 намеренно, чтобы проверить что system DNS не копируется).
- `expected/` — эталоны отчётов (по желанию).

```bash
tests/static-check.zsh
tests/auto-up-boot-race.zsh   # безопасно при смонтированном NAS
tests/cycle-myvpn.zsh   # отчёт: ~/.cache/myvpn-cycle/latest.txt
```
