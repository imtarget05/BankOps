# QuanLyKho — Kho Quản Lý & Ngân Hàng AI

**Repo:** `QuanLyKho` (Kho-Trà-Sữa core banking ops)
**Stack:** FastAPI + SQLAlchemy 2.x + Alembic + PostgreSQL 16 + Poetry + Pytest
**Language:** Python 3.11+
**Python toolchain:** **Poetry** là canonical (`backend/poetry.lock`) — xem
[`docs/engineering/python-toolchain.md`](docs/engineering/python-toolchain.md).

---

## 1. Project Structure

```
QuanLyKho/
├── backend/
│   ├── app/
│   │   ├── api/                 # FastAPI routes, controllers
│   │   ├── models/              # SQLAlchemy ORM models
│   │   ├── schemas/             # Pydantic v2 request/response schemas
│   │   ├── core/                # Config, security, exceptions
│   │   ├── db/                  # Session, engine, base
│   │   ├── worker.py            # Background worker (Celery / RQ)
│   │   └── main.py              # FastAPI app factory
│   ├── alembic/                 # DB migrations (Alembic)
│   │   ├── versions/            # Migration files: 001..024
│   │   ├── env.py               # Alembic env
│   │   └── alembic.ini
│   ├── tests/                   # Pytest unit + integration
│   ├── scripts/                 # Helper scripts (seed, checks)
│   ├── pyproject.toml           # Poetry config
│   └── README.md
├── docker-compose.yml           # Local dev: Postgres + app
└── .github/workflows/ci.yml     # CI: secrets guard, lint (ruff 0.17.0), test
```

---

## 2. Dev Commands

```bash
# Setup
make dev        # or: docker compose up -d
cd backend && poetry install --with dev   # canonical toolchain: Poetry (xem docs/engineering/python-toolchain.md)

# Lint
ruff check backend/            # 0.17.0 pinned in CI
# ruff rules 0.17.0+: I001/UP041 added (enabled explicitly in pyproject)

# Test
cd backend && poetry run pytest tests -q          # hoặc: pytest -xvs (nếu đã có .venv)

# Migrations
poetry run alembic revision --autogenerate -m "desc"   # after model change
poetry run alembic upgrade head
poetry run alembic downgrade -1

# Run app
poetry run uvicorn app.main:app --reload --port 8000
```

---

## 3. Code Conventions

- **Immutability:** spread/operator instead of in-place mutation
- **Types:** Pydantic v2 `BaseModel`, SQLAlchemy 2.0 `Mapped` / `mapped_column`
- **DB model example:**
  ```python
  from sqlalchemy.orm import Mapped, mapped_column
  from sqlalchemy import String, Numeric, Boolean

  class Item(Base):
      __tablename__ = "inv_items"
      id: Mapped[str] = mapped_column(String(36), primary_key=True)
      sku: Mapped[str] = mapped_column(String(128))
      name: Mapped[str] = mapped_column(String(256))
      unit: Mapped[str | None] = mapped_column(String(32))
      tracked_serial: Mapped[bool] = mapped_column(Boolean, default=False)
      active: Mapped[bool] = mapped_column(Boolean, default=True)
      cost_price: Mapped[Decimal | None] = mapped_column(Numeric(14, 2), nullable=True)
      selling_price: Mapped[Decimal] = mapped_column(Numeric(12, 2))
      min_stock: Mapped[int] = mapped_column(Integer, default=0)
  ```
- **Migrations:** Alembic, idempotent checks via `op.get_bind()` + `insp.get_columns()`
- **Secrets:** env vars only, `.env` ignored, no hardcoded tokens
- **Logging:** structured JSON via `structlog` or `logging` with `app/core/logger.py`
- **Testing:** pytest + testcontainers Postgres 16, isolate per test

---

## 4. Deployment

- **Local dev:** `docker compose up -d`
- **Production:** GitHub Actions CI → container → Cloudflare / infra (see `docs/11-devops.md`)
- **Migrations:** Alembic upgrade/downgrade on production DB

---

## 5. Architecture Overview

```
API (FastAPI) → DB (Postgres) → Worker (async jobs)
                   ↑
              Alembic (migrations)
```

- **API**: REST endpoints in `app/api/`, layered by domain (`inventory`, `cash_sim`, `reconciliation`, `etl`, `iam`, `integration`, `activity`)
- **Worker**: Background processing in `app/worker.py`
- **Events**: Outbox pattern (`outbox_events` table, `Kafka`/Redis pub/sub)

---

## 6. Known Gotchas

| Issue | Fix |
|-------|-----|
| `alembic: revision file missing` | Check `alembic_version` vs `versions/`; recreate missing migration |
| `cost_price` missing on fresh DB | Migration 021 step 3 conditionally adds `cost_price` before step 5 backfill |
| `branch_id` missing on fresh DB | Migration 024 (`add_branch_id_to_cashbox`) must be applied before 022 backfill |
| `ruff` line length / import order | CI pins `ruff==0.17.0`; follow English/I001/UP041 enforced rules |

---

## 7. Test Results & Evidence

> Cập nhật: 2026-10-20

| Suite | Lệnh | Kết quả |
|-------|------|---------|
| QuanLyKho backend | `pytest backend/tests` (venv `.venv311`) | **387 passed, 8 skipped, 0 failed** (~2 phút) |
| AKS-SRE-Platform gates | `.venv/bin/python tests/test_gates.py` | **17 passed, 0 failed**; validator: 16 PASS / 0 FAIL / 2 EXTERNAL_REPO_NOT_PRESENT (advisory) |
| OpsBridge (.NET) | `dotnet test AzureFlashSale.slnx` | **310 passed, 0 failed** (173 FlashSale.UnitTests + 45 OpsBridge.UnitTests + 7 ContractTests + 23 OpsBridge.IntegrationTests + 62 FlashSale.IntegrationTests) |

### Root cause đã xử lý (2026-10-20)

1. **2 test QuanLyKho fail trên DB dùng chung tích tụ dữ liệu** (`test_api_v1_web_e2e.py::test_api_v1_maker_checker_web_flow`, `test_etl_pipeline.py::TestEtlPipeline::test_balance_adjustment_posting_with_single_admin_override`):
   - `GET /inventory/balances` dùng keyset pagination (default limit 50, max 100, trả `{balances, next_cursor, limit}`) — một GET duy nhất chỉ thấy trang đầu. DB dev tích tụ 259 dòng `inv_balances` → các dòng ngoài trang đầu "vô hình" với test (`assert 0 == 15.0`).
   - Fix: helper `fetch_all_balances()` trong `backend/tests/conftest.py` duyệt theo `next_cursor`; áp dụng tại các call site đọc balances. Đồng thời query `cash-sim/journals` lọc theo `request_id` để không phụ thuộc thứ tự trang.
   - API pagination hoạt động đúng thiết kế (docs/06, `test_pagination.py`) — lỗi thuộc về test, không phải API.
2. **AKS gate test fail do môi trường**: `test_gates.py` gọi validator bằng `sys.executable` (python homebrew thiếu PyYAML) → rc=1 trên mọi fixture. Chạy qua `.venv` dựng từ `requirements.lock` (`uv venv .venv --python 3.11` + `uv pip install -r requirements.lock`) là đủ, không cần sửa code.

### Follow-up (không chặn)

- Một số test khác vẫn đọc balances bằng 1 GET (vd. `test_phase1_stock_levels.py`, `test_tea_inventory_catalog.py`, `test_reserved_inventory_and_return.py`) — hiện pass vì row mục tiêu tình cờ rơi vào trang đầu; nên chuyển dần sang `fetch_all_balances()`.
- DB dev tích tụ dữ liệu (311 `inv_balances`, 440 `inv_items` sau 2 lần chạy full suite). Script reset đã có sẵn: `cd backend && python -m app.reset_demo_db` (xoá dữ liệu giao dịch + re-seed từ `sample-data`, cần `DATABASE_URL` trỏ đúng DB; với flow docker dùng `make reset-demo`). Chạy tay khi cần, không gắn vào CI.
