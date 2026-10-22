# Evidence — QuanLyKho (MilkTea Ops)

| Field | Content |
|-------|---------|
| Project | QuanLyKho — Kho Quản Lý & Ngân Hàng AI (MilkTea Ops core banking / inventory operations) |
| Version | Commit `9c3468e` (`9c3468e334bd2afdfd675c2db3b156d7d9ccc009`, `feat(obs): support LANGFUSE_BASE_URL alias and auto-load .env in e2e smoke test`); tag `prod-20261019` |
| Real vs Simulated | Backend (FastAPI + SQLAlchemy 2.x + Alembic, Python 3.11) runs on real PostgreSQL 16 for tests and validation (isolated local container `postgres:16`; Neon Postgres for cloud validation on Modal). Flutter frontend. AI assessment and background worker paths are partly simulated/stubbed (worker historically a sleep-loop; outbox claim/dispatch verified as a gap and fixed). |
| Environment Tested | Isolated PostgreSQL 16 (`docker run postgres:16-alpine`, local `:5432` and QA `:5433`); FastAPI 0.143 on Python 3.11; Flutter frontend; cloud chain FastAPI on Modal → Neon Postgres verified end-to-end (14/10 and 15/10). |
| Results | 677 passed / 7 skipped / 1 xfailed on isolated PostgreSQL (backend `pytest`). Flutter tests pass; `flutter analyze` clean; `ruff` lint clean; `alembic upgrade head` runs clean from empty DB (revision `014`, 39 tables). |
| Limits / Not Proven | No production deployment yet. Historically open gaps: bcrypt/passlib version pin, Alembic migration syntax, Dockerfile build context, RBAC enforcement (`require_capability` not called on protected routes), missing write endpoints, CSV formula injection (fixed since). `mypy` strict is intentionally xfailed (tech debt, ~481 annotations). Legacy Worker left on `workers.dev` as fallback (not re-deployed). |
