"""Integration hub models (docs/04, docs/09).

Import ngoài không bao giờ ghi thẳng ledger: dữ liệu dừng ở staging,
chờ human confirm rồi mới tạo draft đi qua approval như mọi phiếu khác.
"""
from datetime import datetime

from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    ForeignKey,
    Integer,
    JSON,
    String,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import UUID

from app.db.base import Base, TimestampMixin


class IntegrationConnection(Base, TimestampMixin):
    __tablename__ = "integration_connections"

    id: str = Column(UUID(as_uuid=True), primary_key=True)
    type: str = Column(String(64), nullable=False)
    name: str = Column(String(256), nullable=False)
    status: str = Column(String(32), nullable=False, default="pending_test")
    secret_ref: str = Column(String(256), nullable=True)
    config_json: dict = Column(JSON, nullable=True)
    owner_id: str = Column(UUID(as_uuid=True), nullable=True)
    schema_json: dict = Column(JSON, nullable=True)
    last_tested_at: datetime = Column(DateTime(timezone=True), nullable=True)
    last_error: str = Column(String(512), nullable=True)


class IntegrationRun(Base, TimestampMixin):
    __tablename__ = "integration_runs"

    id: str = Column(UUID(as_uuid=True), primary_key=True)
    connection_id: str = Column(
        UUID(as_uuid=True), ForeignKey("integration_connections.id"), nullable=False
    )
    status: str = Column(String(32), nullable=False, default="staged")
    source_fingerprint: str = Column(String(128), nullable=False)
    mapping_version: int = Column(Integer, nullable=False, default=1)
    valid_count: int = Column(Integer, nullable=False, default=0)
    invalid_count: int = Column(Integer, nullable=False, default=0)
    external_event_id: str = Column(String(256), nullable=True)
    phase: str = Column(String(32), nullable=False, default="staged")
    finished_at: datetime = Column(DateTime(timezone=True), nullable=True)
    error_code: str = Column(String(64), nullable=True)
    message_key: str = Column(String(256), nullable=True)
    message_params_json: dict = Column(JSON, nullable=True)


class IntegrationStagingRow(Base):
    __tablename__ = "integration_staging_rows"
    __table_args__ = (
        UniqueConstraint("run_id", "source_row_key", name="uq_staging_run_row"),
    )

    id: str = Column(UUID(as_uuid=True), primary_key=True)
    run_id: str = Column(
        UUID(as_uuid=True), ForeignKey("integration_runs.id"), nullable=False
    )
    source_row_key: str = Column(String(256), nullable=False)
    data_json: dict = Column(JSON, nullable=False)
    valid: bool = Column(Boolean, nullable=False, default=True)
    errors_json: list = Column(JSON, nullable=True)
