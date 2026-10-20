# Current Tasks — QuanLyKho (Kho Trà Sữa / BankOps)

> Created during Phase 0 triage (2026-10-19). Repo had no `tasks/current.md`; scoreboard added per executor contract §7.

## Baseline (read-only audit, 2026-10-19)

- Branch: `codex/bankops-b1` @ `79b1bdf` (fix: limit inventory request reads to branch scope)
- Remote `origin/main`: `fc2978d` (ahead of local — local is behind; no divergence conflict, just unpulled)
- Local branch `backup/pre-token-scrub-20261013-213005` @ `e5ee6fc` exists
- Remote `qa-validation-20261014` @ `1c5d521` exists
- Worktree: DIRTY — 8 modified (`cash_sim.py`, `integrations.py`, `inventory.py`, `reconciliations.py`, `main.py`, `worker.py`, `poetry.lock`, `pyproject.toml`) + 5 new observability files (`observability.py`, `request_context.py`, `structured_logging.py`, `telemetry.py`, 3 test files)
- Remote CI (per roadmap): `39199216961` FAIL — migration `i.cost_price` absent; Ruff 34 errors; backend pytest skipped due migration failure

## Phase status (from 05_PHASE_TRACKER.csv)

| Phase | Status | Notes |
|---|---|---|
| B0 Baseline audit | PASS | Baseline inventory done; dirty worktree preserved |
| B1 Recover CI/schema/lint | PASS 2026-10-20 | Full suite 387 passed + 8 skipped, 2 consecutive runs on shared DB `kho-tra-sua`; `ruff check app/ tests/` clean; new `test_pagination.py` 10/10 (keyset round-trip, INVALID_CURSOR 400, limit clamp 100, legacy cursor) |
| B2 Identity/Auth | NOT_STARTED | |
| B3 Atomic posting | NOT_STARTED | |
| B4 Contract/Events | NOT_STARTED | |
| B5 Workflows | NOT_STARTED | |
| B6 Offline (P2) | DEFER | |
| B7 Ops/Release | NOT_STARTED | |

## B1 evidence (2026-10-20)

- Run 1 (before pagination test): 377 passed, 8 skipped.
- Run 2 (after `test_pagination.py` + `decode_cursor` legacy fix): **387 passed, 8 skipped**.
- `ruff check backend/app/ backend/tests/`: All checks passed.
- Worktree dirty (chưa commit): `pagination.py` (fix legacy-JSON collision), `inventory.py`, `integrations.py`, `reconciliations.py`, `seed.py`, `conftest.py` + `open_shift` retry, `test_pagination.py` mới, `test_migration_cost_price.py` isolated-DB.
- Blocked còn lại: chuỗi Alembic `022 -> 024` (thiếu `023`, intentional hay missing chưa xác minh); shared dev DB không có isolated CI DB riêng.

## Immediate next step (B1)

Fix missing `cost_price` schema via forward-only migration (never rewrite applied `021`); clear 34 Ruff issues without mutating tests; fix CI job ordering so lint doesn't hide migration/test evidence.

## AGENTS.md

**MISSING** — QuanLyKho has no `AGENTS.md` (checked maxdepth 4). Portfolio engineering conventions from `Productionized-LegacyApp`/`AKS-SRE-Platform` AGENTS.md apply by reference until a repo-specific one is added.
