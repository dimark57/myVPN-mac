# Tests (doc-6)

- `static-check.zsh` — статика без секретов (фикстуры + render + sing-box check).
- `cycle-myvpn.zsh` — живой цикл: down → up → C* → down → restore (`MYVPN_CYCLE_RESTORE=myvpn|app`).
- `fixtures/` — фейковые `macbook.conf` / `home.conf` (DNS=1.1.1.1 намеренно, чтобы проверить что system DNS не копируется).
- `expected/` — эталоны отчётов (по желанию).

```bash
tests/static-check.zsh
tests/cycle-myvpn.zsh   # отчёт: ~/.cache/myvpn-cycle/latest.txt
```
