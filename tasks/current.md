# Current Tasks — QuanLyKho (Kho Trà Sữa / BankOps)

> **Portfolio audit checkpoint, 2026-10-21:** work started at HEAD `c9b6935`
> and concurrent local commits advanced HEAD through `d53c092` to
> `5d79314364739e48cd589604d56764583d963286` during the audit.
> At start there were pre-existing edits in `backend/app/api/routes/reconciliations.py`,
> `backend/docs/17-b2-authorization-scope-audit.md` and
> `backend/tests/test_b2_authorization_scope.py`. The historical clean-tree
> baseline below is **not** the current working-tree state. See
> `docs/PORTFOLIO_AUDIT_2026-10-21.md` for the current claim matrix, gaps and
> reproducible AI → checker demo. The focused demo passed against a disposable
> PostgreSQL database. A full run passed 674 tests at the earlier revision;
> after concurrent S9 commits, HEAD `5d79314` produced 21 MLflow failures on
> the host's read-only `/data` path. An uncommitted narrow fix and regression
> test passed three targeted checks; a fresh full-suite rerun is pending.
> Exact commands and results are recorded in the audit.

> **Updated 2026-10-20** after a full local re-verification. Earlier revisions of
> this board recorded a dirty worktree, a "missing AGENTS.md", and an
> unresolved Alembic gap. All three are now resolved; the claims below were
> reproduced locally, not copied forward.

## Verified baseline (2026-10-20, HEAD `197a08e`, branch `main`)

| Item | Verified state |
|---|---|
| Branch / HEAD | `main` @ `197a08e` — **no upstream configured** (`git branch -vv` shows no `[origin/main]`) |
| Worktree | **clean** before and after verification |
| Local branches | `main`, `codex/bankops-b1`, `qa-validation-20261014`, `backup/pre-token-scrub-20261013-213005` |
| `AGENTS.md` | **present** (6.9 KB) — the previous "MISSING" note was wrong |
| Secret guard | `python3 scripts/check_no_secrets.py` → PASS |
| Lint | `ruff check backend/` with **0.17.0** (CI pin) → All checks passed |
| Migrations | `alembic upgrade head` on an **isolated** Postgres 16 → `024_add_branch_id_to_cashbox (head)`, 42 tables |
| Backend tests | **387 passed, 7 skipped, 1 xfailed** in 129 s |
| Flutter | `flutter analyze` → No issues; `flutter test` → **180 passing** |
| Scale | backend 16,247 LOC / 56 `.py`; frontend 46,277 LOC / 86 `.dart`; 141 routes; 43 test files |

## Resolved findings

1. **Alembic `022 → 024` is not a break.** `024_add_branch_id_to_cashbox.down_revision`
   is `022_movement_cost_and_sub_kind`; no revision declares `023` as parent.
   `alembic upgrade head` succeeds and there is exactly one head. The missing
   number is a cosmetic gap in filenames, not a broken chain.
2. **`cost_price` is provided by migration 021**, not 022
   (`021_receipt_invoice_and_lots.py:41-42`). The historical CI failure
   (`i.cost_price` absent) is not reproducible from a clean database.
3. **`AGENTS.md` exists** and carries its own gotchas table. The board no longer
   duplicates it.
4. **B1 work is committed** — the worktree is clean at `197a08e`.

## Phase status

| Phase | Status | Notes |
|---|---|---|
| B0 Baseline audit | PASS | 2026-10-19 inventory; superseded by the 2026-10-20 re-verification above |
| B1 Recover CI/schema/lint | PASS | Migration, lint, backend and Flutter suites all green locally |
| B2 Identity/Auth | NOT_STARTED | |
| B3 Atomic posting | NOT_STARTED | |
| B4 Contract/Events | NOT_STARTED | |
| B5 Workflows | NOT_STARTED | |
| B6 Offline (P2) | DEFER | |
| B7 Ops/Release | NOT_STARTED | |

## Open items (do not overstate)

- **Local venv ruff is stale.** `backend/.venv/bin/ruff` is **0.6.9** while CI
  pins **0.17.0**, so a developer running the venv binary gets a false `UP038`
  failure at `app/api/pagination.py:126`. Refresh the venv before trusting a
  local lint result. `pyproject.toml` still declares `ruff = "^0.6.0"`; aligning
  it with CI is a small, separately-testable change.
- **Tests require a live database.** `backend/tests/conftest.py` only
  `setdefault`s a placeholder `DATABASE_URL`, and `backend/.env` points at
  `localhost:5432` (the developer's `kho-tra-sua-db`). A run without an explicit
  `DATABASE_URL` writes to shared data. This is why the CI job provisions its own
  Postgres service.
- **No isolated CI database locally.** Verification above used a throwaway
  container; nothing was written to the developer's database.
- **Branch has no upstream.** `main` is not tracking `origin/main`, so
  `git push` has no default and CI is not driven by a push from this checkout.

## Next step (B2 — Identity/Auth)

Scope when B2 opens: enumerate authentication and authorization surfaces, prove
object-level authorization for each route group, and add negative tests for
cross-branch access. The audit must start from `app/api/routes/` + IAM models,
not from the docs.

## AGENTS.md

Present at the repository root. Repo-specific conventions there take precedence
over the portfolio-wide conventions in `Productionized-LegacyApp` /
`AKS-SRE-Platform`.
