"""Database module - handles SQLAlchemy engine, session, and base."""
import logging
import os
import sys
from collections.abc import AsyncIterator

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.config import settings
from app.db.base import Base

logger = logging.getLogger(__name__)

def _normalize_async_database_url(url: str) -> str:
    """Normalize database URL for asyncpg engine."""
    if url.startswith("postgresql://"):
        url = url.replace("postgresql://", "postgresql+asyncpg://", 1)
    elif url.startswith("postgresql+psycopg2://"):
        url = url.replace("postgresql+psycopg2://", "postgresql+asyncpg://", 1)
    # asyncpg expects ssl=require, not sslmode=require
    if "sslmode=" in url:
        url = url.replace("sslmode=", "ssl=")
    return url


DATABASE_URL = _normalize_async_database_url(settings.database_url)

_engine_kwargs = {
    "echo": False,
    "pool_pre_ping": True,
}

_is_testing = (
    "pytest" in sys.modules
    or "PYTEST_CURRENT_TEST" in os.environ
    or os.environ.get("TESTING", "").lower() in ("1", "true", "yes")
    or getattr(settings, "environment", "") == "test"
)

if "sqlite" in DATABASE_URL:
    from sqlalchemy.pool import StaticPool
    _engine_kwargs["poolclass"] = StaticPool
elif _is_testing:
    from sqlalchemy.pool import NullPool
    _engine_kwargs["poolclass"] = NullPool
else:
    _engine_kwargs.update({
        "pool_size": 10,
        "max_overflow": 20,
        "pool_timeout": 30,
        "pool_recycle": 300,
    })

engine = create_async_engine(DATABASE_URL, **_engine_kwargs)

AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autoflush=False,
    autocommit=False,
)


async def init_db() -> None:
    """Initialize database connection and verify connectivity.

    Fail-fast (R8): bất kỳ lỗi DB nào cũng **raise** ở mọi môi trường —
    orchestrator sẽ restart app thay vì phục vụ traffic với DB chết.

    Schema bootstrap (`create_all` + seed demo) chỉ chạy ở **demo mode tường
    minh** (`APP_ENV=demo` + `DEMO_MODE=true`). Ở staging/production, Alembic là
    nguồn sự thật (`alembic upgrade head` chạy ở entrypoint) — `create_all` từng
    âm thầm bỏ qua Alembic và có thể tạo schema lệch với migration.
    """
    try:
        import app.models.activity  # noqa: F401
        import app.models.approval  # noqa: F401
        import app.models.cash_sim  # noqa: F401
        import app.models.iam  # noqa: F401
        import app.models.integration  # noqa: F401
        import app.models.inventory  # noqa: F401
        import app.models.reconciliation  # noqa: F401

        # Seed dữ liệu demo CHỈ chạy khi demo mode được bật tường minh
        # (`APP_ENV=demo` + `DEMO_MODE=true`). Trước đây điều kiện là
        # `app_env != "production"`, nên mọi môi trường (staging/dev) đều tự
        # nạp dữ liệu demo — bao gồm cả user demo kèm mật khẩu mặc định.
        if settings.is_demo_mode:
            async with engine.begin() as conn:
                await conn.run_sync(Base.metadata.create_all)
                for col_stmt in [
                    "ALTER TABLE inv_items ADD COLUMN IF NOT EXISTS category VARCHAR(128)",
                    "ALTER TABLE inv_items ADD COLUMN IF NOT EXISTS packaging VARCHAR(256)",
                    "ALTER TABLE inv_items ADD COLUMN IF NOT EXISTS cost_price NUMERIC(15,2)",
                    "ALTER TABLE inv_items ADD COLUMN IF NOT EXISTS selling_price NUMERIC(15,2)",
                    "ALTER TABLE inv_items ADD COLUMN IF NOT EXISTS min_stock NUMERIC(12,2)",
                    "ALTER TABLE inv_requests ADD COLUMN IF NOT EXISTS invoice_no VARCHAR(128)",
                    "ALTER TABLE inv_requests ADD COLUMN IF NOT EXISTS sub_kind VARCHAR(32)",
                    "ALTER TABLE inv_request_lines ADD COLUMN IF NOT EXISTS unit VARCHAR(32)",
                    "ALTER TABLE inv_request_lines ADD COLUMN IF NOT EXISTS conversion_rate NUMERIC(10,4)",
                    "ALTER TABLE inv_movements ADD COLUMN IF NOT EXISTS sub_kind VARCHAR(32)",
                    "ALTER TABLE inv_movements ADD COLUMN IF NOT EXISTS unit_cost NUMERIC(14,2)",
                    "ALTER TABLE inv_movements ADD COLUMN IF NOT EXISTS cost_amount NUMERIC(20,2)",
                ]:
                    try:
                        await conn.execute(text(col_stmt))
                    except Exception as ex:
                        logger.warning(f"Migration note: {ex}")

                try:
                    res = await conn.execute(text(
                        "SELECT b.location_id, b.item_id, b.quantity, COALESCE(i.cost_price, 0) "
                        "FROM inv_balances b "
                        "LEFT JOIN inv_items i ON i.id = b.item_id "
                        "WHERE b.quantity > 0 "
                        "AND NOT EXISTS (SELECT 1 FROM inv_lot_balances lb WHERE lb.location_id = b.location_id AND lb.item_id = b.item_id)"
                    ))
                    rows = res.fetchall()
                    for r in rows:
                        import uuid as _uuid_m
                        from datetime import date as _date_m
                        await conn.execute(text(
                            "INSERT INTO inv_lot_balances (id, location_id, item_id, lot_no, expiry_date, quantity, unit_cost, created_at, updated_at) "
                            "VALUES (:id, :loc, :it, 'TON-DAU-KY', :exp, :qty, :cost, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)"
                        ), {
                            "id": _uuid_m.uuid4(),
                            "loc": r[0],
                            "it": r[1],
                            "exp": _date_m(2099, 12, 31),
                            "qty": r[2],
                            "cost": r[3],
                        })
                except Exception as ex:
                    logger.warning(f"Initial lot seeding note: {ex}")

            from app.seed import seed_demo

            await seed_demo()
            async with AsyncSessionLocal() as session:
                await session.execute(
                    text("UPDATE cash_balances SET amount = 0.00 WHERE cashbox_id = '11111111-1111-4111-8111-111111111111'")
                )
                await session.commit()
        else:
            # Ngoài demo mode: KHÔNG create_all/seed — chỉ xác minh kết nối.
            # Lỗi kết nối phải raise để app không serve traffic với DB chết.
            async with engine.connect() as conn:
                await conn.execute(text("SELECT 1"))
        logger.info("Database initialized successfully")
    except Exception as e:
        logger.error(f"Database initialization failed: {e}")
        raise


async def get_db() -> AsyncIterator[AsyncSession]:
    """Get database session as an async iterator."""
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise