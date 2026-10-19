# B1 — Fresh migration and quality-gate evidence

## Scope

This cycle covers the B1 requirement that a clean PostgreSQL database can run
the complete Alembic chain, and that the repository's Ruff gate is clean.

## User journey

As an operator deploying BankOps to a fresh environment, I can run database
migrations before the API starts, so that the initial lot-balance backfill does
not fail because `inv_items.cost_price` is absent.

## RED → GREEN evidence

| Stage | Command | Result |
| --- | --- | --- |
| RED | `python -m pytest tests/test_migration_cost_price.py -q` | Failed at revision 021 with `UndefinedColumn: i.cost_price`. |
| GREEN | `python -m pytest tests/test_migration_cost_price.py -q` | Passed after revision 021 adds `cost_price` before its lot-balance query. |
| Regression | `DATABASE_URL=... python -m pytest tests/ -q` | 302 passed, 8 skipped. |
| Lint | `ruff check app alembic tests` | Passed. |

`tests/test_migration_cost_price.py` deliberately resets only the isolated
PostgreSQL test database on port 15432, then restores application-ready demo
state with `init_db`. This prevents a migration test from contaminating later
session-scoped integration tests. The reservation fixture also resets its lot
balances alongside its aggregate balance, so the concurrency test measures
available FEFO stock rather than stale lots.

## Guarantees

| # | Guarantee | Test | Result |
| --- | --- | --- |
| 1 | Fresh Alembic upgrade reaches `head` without a missing `cost_price` column. | `tests/test_migration_cost_price.py` | PASS |
| 2 | The full backend regression suite remains green against isolated PostgreSQL. | `tests/` | PASS |
| 3 | Two concurrent issue submissions preserve one full reservation rather than partial reservations. | `test_concurrent_issue_submits_reserve_one_full_request_only` | PASS |
| 4 | Ruff finds no selected lint violations in application, migrations, or tests. | `ruff check app alembic tests` | PASS |

## Coverage and remaining gap

The full suite measures 46% statement coverage for `app` (302 passed, 8
skipped). It does not meet the wider 80% portfolio target yet; that is an
existing suite-wide gap, not hidden by this B1 change. Future functional phases
must raise coverage in the untested route, worker, ETL, and integration paths.
