"""Reconciliation models (docs/04, docs/05, R1).

Đối soát snapshot expected từ ledger/movements so với read model.
Sai lệch tạo exception để xử lý — KHÔNG tự vá (auto_fixed luôn False).
"""
from sqlalchemy import JSON, Boolean, Column, ForeignKey, Numeric, String
from sqlalchemy.dialects.postgresql import UUID

from app.db.base import Base, TimestampMixin


class ReconciliationRun(Base, TimestampMixin):
    __tablename__ = "reconciliation_runs"

    id: str = Column(UUID(as_uuid=True), primary_key=True)
    scope: str = Column(String(32), nullable=False)
    status: str = Column(String(32), nullable=False, default="running")
    auto_fixed: bool = Column(Boolean, nullable=True)


class ReconciliationException(Base):
    __tablename__ = "reconciliation_exceptions"

    id: str = Column(UUID(as_uuid=True), primary_key=True)
    run_id: str = Column(
        UUID(as_uuid=True), ForeignKey("reconciliation_runs.id"), nullable=False
    )
    subject: str = Column(String(256), nullable=False)
    expected_json: dict = Column(JSON, nullable=False)
    actual_json: dict = Column(JSON, nullable=False)
    expected_amount = Column(Numeric(20, 3), nullable=True)
    actual_amount = Column(Numeric(20, 3), nullable=True)
    # B2 follow-up — authorization scope columns so the dashboard can filter
    # exception counters by the caller's accessible cashboxes / locations.
    cashbox_id = Column(
        UUID(as_uuid=True),
        ForeignKey("cash_boxes.id", ondelete="SET NULL"),
        nullable=True,
    )
    location_id = Column(
        UUID(as_uuid=True),
        ForeignKey("inv_locations.id", ondelete="SET NULL"),
        nullable=True,
    )
    resolved: bool = Column(Boolean, nullable=False, default=False)
