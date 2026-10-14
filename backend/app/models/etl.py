"""ETL Pipeline Models (Phase 2).

4-layer configurable and scoped ETL:
  Connection -> Pipeline -> MappingVersion -> Run -> Review/Post -> Staging Rows

Enforces:
  - Branch and Location scoping
  - Idempotent runs with fingerprint deduplication
  - Non-destructive staging: never direct UPDATE balance
  - Single-admin override auditability for balance adjustments
"""

import uuid

from sqlalchemy import (
    JSON,
    Boolean,
    Column,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import UUID

from app.db.base import Base, TimestampMixin


class EtlConnection(Base, TimestampMixin):
    __tablename__ = "etl_connections"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(String(256), nullable=False)
    type = Column(String(64), nullable=False)  # csv, json, xlsx, google_sheets
    status = Column(String(32), nullable=False, default="active")  # active, inactive, error
    secret_ref = Column(String(256), nullable=True)
    allowlist_sheets = Column(JSON, nullable=True)  # list of allowed sheet IDs/ranges
    config_json = Column(JSON, nullable=True)
    branch_id = Column(UUID(as_uuid=True), ForeignKey("org_branches.id", ondelete="SET NULL"), nullable=True)
    owner_id = Column(UUID(as_uuid=True), ForeignKey("iam_users.id", ondelete="SET NULL"), nullable=True)


class EtlPipeline(Base, TimestampMixin):
    __tablename__ = "etl_pipelines"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(String(256), nullable=False)
    target = Column(
        String(64), nullable=False
    )  # catalog_upsert, inventory_receipt, inventory_issue, inventory_transfer, stocktake, balance_adjustment_admin
    connection_id = Column(UUID(as_uuid=True), ForeignKey("etl_connections.id", ondelete="CASCADE"), nullable=False)
    branch_id = Column(UUID(as_uuid=True), ForeignKey("org_branches.id", ondelete="SET NULL"), nullable=True)
    location_id = Column(UUID(as_uuid=True), ForeignKey("inv_locations.id", ondelete="SET NULL"), nullable=True)
    destination_location_id = Column(
        UUID(as_uuid=True), ForeignKey("inv_locations.id", ondelete="SET NULL"), nullable=True
    )
    schedule_cron = Column(String(128), nullable=True)
    status = Column(String(32), nullable=False, default="active")  # active, paused, archived
    owner_id = Column(UUID(as_uuid=True), ForeignKey("iam_users.id", ondelete="SET NULL"), nullable=True)
    config_json = Column(JSON, nullable=True)


class EtlMappingVersion(Base, TimestampMixin):
    __tablename__ = "etl_mapping_versions"
    __table_args__ = (
        UniqueConstraint("pipeline_id", "version", name="uq_etl_mapping_pipeline_version"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    pipeline_id = Column(UUID(as_uuid=True), ForeignKey("etl_pipelines.id", ondelete="CASCADE"), nullable=False)
    version = Column(Integer, nullable=False, default=1)
    status = Column(String(32), nullable=False, default="draft")  # draft, published, retired
    mapping_json = Column(JSON, nullable=False)  # list of {source_field, target_field, required, transform, default}
    validation_rules_json = Column(JSON, nullable=True)
    duplicate_policy = Column(String(32), nullable=False, default="reject")  # reject, skip, overwrite
    created_by = Column(UUID(as_uuid=True), ForeignKey("iam_users.id", ondelete="SET NULL"), nullable=True)
    published_at = Column(DateTime(timezone=True), nullable=True)


class EtlRun(Base, TimestampMixin):
    __tablename__ = "etl_runs"
    __table_args__ = (
        Index("ix_etl_runs_pipeline_id", "pipeline_id"),
        Index("ix_etl_runs_source_fingerprint", "source_fingerprint"),
        Index("ix_etl_runs_status", "status"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    pipeline_id = Column(UUID(as_uuid=True), ForeignKey("etl_pipelines.id", ondelete="CASCADE"), nullable=False)
    mapping_version_id = Column(
        UUID(as_uuid=True), ForeignKey("etl_mapping_versions.id", ondelete="SET NULL"), nullable=True
    )
    mapping_version_num = Column(Integer, nullable=False, default=1)
    runner_id = Column(UUID(as_uuid=True), ForeignKey("iam_users.id", ondelete="SET NULL"), nullable=False)
    status = Column(
        String(32), nullable=False, default="staged"
    )  # pending, running, staged, reviewing, posted, rejected, failed, cancelled
    progress_pct = Column(Integer, nullable=False, default=0)
    total_rows = Column(Integer, nullable=False, default=0)
    valid_rows = Column(Integer, nullable=False, default=0)
    invalid_rows = Column(Integer, nullable=False, default=0)
    source_fingerprint = Column(String(128), nullable=False)
    external_event_id = Column(String(256), nullable=True)
    single_admin_override = Column(Boolean, nullable=False, default=False)
    reviewer_id = Column(UUID(as_uuid=True), ForeignKey("iam_users.id", ondelete="SET NULL"), nullable=True)
    review_decision = Column(String(32), nullable=True)  # approved, rejected
    review_note = Column(String(512), nullable=True)
    posted_at = Column(DateTime(timezone=True), nullable=True)
    generated_reference_type = Column(String(64), nullable=True)  # request, stocktake, balance_adjustment, catalog
    generated_reference_id = Column(String(128), nullable=True)
    error_code = Column(String(64), nullable=True)
    error_message = Column(String(512), nullable=True)


class EtlRunRow(Base):
    __tablename__ = "etl_run_rows"
    __table_args__ = (
        Index("ix_etl_run_rows_run_number", "run_id", "row_number"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    run_id = Column(UUID(as_uuid=True), ForeignKey("etl_runs.id", ondelete="CASCADE"), nullable=False)
    row_number = Column(Integer, nullable=False)
    source_row_key = Column(String(256), nullable=True)
    raw_data_json = Column(JSON, nullable=False)
    canonical_data_json = Column(JSON, nullable=True)
    valid = Column(Boolean, nullable=False, default=True)
    errors_json = Column(JSON, nullable=True)  # list of error strings
    action_preview = Column(JSON, nullable=True)  # preview summary of change
