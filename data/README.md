# data/

`mymac-mytask-import-payload.json` — снимок импорта `.backlog/tasks/` → myTask (cutover 2026-09-22).

**Apply (LAN/VPN, после «да» владельца):**

1. `project_id` — из `myNAS/stacks/agent/backlog-hub/registry/projects.json` (slug `myVPN-mac`).
2. Каждый `items[]`: `POST /todos` с заголовком `Idempotency-Key: backlog-import-<MYMAC-n>`.
3. Подтверждение: `GET /todos/{id}` (навык **mytask** в `~/repos/mySkills/skills/mytask/`).

Повторный apply идемпотентен по idempotency key.
