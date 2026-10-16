"""Database module - handles SQLAlchemy engine, session, and base."""
import logging
from collections.abc import AsyncIterator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

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

engine = create_async_engine(
    DATABASE_URL,
    echo=False,
    poolclass=NullPool,
)

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
        if settings.app_env != "production":
            from sqlalchemy import text

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