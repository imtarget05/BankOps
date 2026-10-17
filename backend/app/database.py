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
    """Initialize database connection and verify connectivity."""
    try:
        import app.models.activity  # noqa: F401
        import app.models.approval  # noqa: F401
        import app.models.cash_sim  # noqa: F401
        import app.models.iam  # noqa: F401
        import app.models.integration  # noqa: F401
        import app.models.inventory  # noqa: F401
        import app.models.reconciliation  # noqa: F401

        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)
            for col_stmt in [
                "ALTER TABLE inv_items ADD COLUMN IF NOT EXISTS category VARCHAR(128)",
                "ALTER TABLE inv_items ADD COLUMN IF NOT EXISTS packaging VARCHAR(256)",
                "ALTER TABLE inv_items ADD COLUMN IF NOT EXISTS cost_price NUMERIC(15,2)",
                "ALTER TABLE inv_items ADD COLUMN IF NOT EXISTS selling_price NUMERIC(15,2)",
                "ALTER TABLE inv_items ADD COLUMN IF NOT EXISTS min_stock NUMERIC(12,2)",
            ]:
                try:
                    await conn.execute(text(col_stmt))
                except Exception as ex:
                    logger.warning(f"Migration note: {ex}")
        if settings.app_env != "production":
            from app.seed import seed_demo

            await seed_demo()
            async with AsyncSessionLocal() as session:
                await session.execute(
                    text("UPDATE cash_balances SET amount = 0.00 WHERE cashbox_id = '11111111-1111-4111-8111-111111111111'")
                )
                await session.commit()
        logger.info("Database initialized successfully")
    except Exception as e:
        logger.error(f"Database initialization failed: {e}")
        if settings.app_env != "production":
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