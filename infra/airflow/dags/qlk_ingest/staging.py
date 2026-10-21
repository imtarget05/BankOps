"""Bảng staging cho DAG ingest (lớp hạ tầng, do DAG sở hữu).

Bảng ``qlk_ingest_staging`` là **bảng staging của pipeline orchestration**,
không phải bảng nghiệp vụ của ứng dụng: nó lưu *nguyên bản* dòng nguồn kèm
fingerprint để chứng minh ingest thật đã xảy ra, và là nơi kiểm tra tính
idempotent (cùng fingerprint + cùng nội dung dòng ⇒ không nạp lại).

Vì bảng nằm ngoài phạm vi model của ứng dụng, nó được tạo bằng SQLAlchemy
Core (``create_all``) thay vì Alembic — không cần migration, không đụng vào
``backend/app/models/**``.
"""

from __future__ import annotations

import hashlib
import json
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import (
    Column,
    DateTime,
    Integer,
    MetaData,
    String,
    Table,
    Text,
    UniqueConstraint,
    create_engine,
    func,
    insert,
    select,
)
from sqlalchemy.engine import Engine


def normalize_sync_url(url: str) -> str:
    """Chuyển URL async của ứng dụng (asyncpg) sang URL sync (psycopg2).

    Ứng dụng dùng ``postgresql+asyncpg://``; task Airflow chạy đồng bộ nên
    cần driver sync (``psycopg2-binary`` đã có trong dependency).
    """
    if url.startswith("postgresql+asyncpg://"):
        return url.replace("postgresql+asyncpg://", "postgresql+psycopg2://", 1)
    if url.startswith("postgresql://"):
        return url.replace("postgresql://", "postgresql+psycopg2://", 1)
    if url.startswith("postgres://"):
        return url.replace("postgres://", "postgresql+psycopg2://", 1)
    if url.startswith("sqlite+aiosqlite://"):
        return url.replace("sqlite+aiosqlite://", "sqlite://", 1)
    return url


def create_staging_engine(database_url: str) -> Engine:
    """Tạo engine sync trỏ tới database đích."""
    return create_engine(normalize_sync_url(database_url), pool_pre_ping=True, future=True)


def staging_metadata(table_name: str) -> MetaData:
    """Metadata + định nghĩa bảng staging (idempotent, không phụ thuộc model app)."""
    metadata = MetaData()
    Table(
        table_name,
        metadata,
        Column("id", Integer, primary_key=True, autoincrement=True),
        Column("dataset", String(64), nullable=False, index=True),
        Column("source_name", String(512), nullable=False),
        Column("source_fingerprint", String(64), nullable=False, index=True),
        Column("row_number", Integer, nullable=False),
        Column("business_key", String(128), nullable=False),
        Column("row_hash", String(64), nullable=False),
        Column("payload", Text, nullable=False),
        Column("ingested_at", DateTime(timezone=True), nullable=False),
        UniqueConstraint(
            "dataset",
            "source_fingerprint",
            "row_hash",
            # Tên constraint là duy nhất theo schema trong Postgres ⇒ phải
            # gắn với tên bảng, nếu không hai bảng staging cùng tồn tại sẽ đụng nhau.
            name=f"uq_{table_name}_row_hash"[:63],
        ),
    )
    return metadata


def row_hash(row: dict[str, Any]) -> str:
    """Hash ổn định của một dòng (canonical JSON, sort keys)."""
    canonical = json.dumps(row, sort_keys=True, default=str, ensure_ascii=False)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def load_rows(
    engine: Engine,
    table_name: str,
    dataset: str,
    source_name: str,
    fingerprint: str,
    rows: list[dict[str, Any]],
    business_key: str,
) -> dict[str, Any]:
    """Nạp dòng nguồn vào bảng staging; bỏ qua dòng đã có (idempotent).

    Trả về số liệu thật: ``inserted`` / ``skipped`` / ``total_rows``.
    """
    metadata = staging_metadata(table_name)
    metadata.create_all(engine)
    table = metadata.tables[table_name]

    inserted = 0
    skipped = 0
    now = datetime.now(UTC)

    with engine.begin() as conn:
        existing = set(
            conn.execute(
                select(table.c.row_hash).where(
                    table.c.dataset == dataset,
                    table.c.source_fingerprint == fingerprint,
                )
            )
            .scalars()
            .all()
        )
        for index, row in enumerate(rows, start=1):
            digest = row_hash(row)
            if digest in existing:
                skipped += 1
                continue
            key = str(row.get(business_key) or f"row_{index}").strip().upper()[:128]
            conn.execute(
                insert(table).values(
                    dataset=dataset,
                    source_name=source_name,
                    source_fingerprint=fingerprint,
                    row_number=index,
                    business_key=key,
                    row_hash=digest,
                    payload=json.dumps(row, sort_keys=True, default=str, ensure_ascii=False),
                    ingested_at=now,
                )
            )
            existing.add(digest)
            inserted += 1

    return {
        "inserted": inserted,
        "skipped": skipped,
        "total_rows": len(rows),
        "table": table_name,
        "dataset": dataset,
    }


def count_rows(engine: Engine, table_name: str, dataset: str) -> int:
    """Đếm số dòng đang có trong bảng staging cho một dataset."""
    metadata = staging_metadata(table_name)
    metadata.create_all(engine)
    table = metadata.tables[table_name]
    with engine.connect() as conn:
        return int(
            conn.execute(
                select(func.count())
                .select_from(table)
                .where(table.c.dataset == dataset)
            ).scalar_one()
        )
