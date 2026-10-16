"""Staged source-data synchronization requests with Root maker-checker approval."""
import uuid
from app.db.base import Base, TimestampMixin
from sqlalchemy import Column, DateTime, ForeignKey, JSON, String
from sqlalchemy.dialects.postgresql import UUID


class SyncRequest(Base, TimestampMixin):
    __tablename__ = "sync_requests"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    requester_id = Column(UUID(as_uuid=True), ForeignKey("iam_users.id", ondelete="RESTRICT"), nullable=False, index=True)
    scope = Column(String(64), nullable=False)
    payload = Column(JSON, nullable=False)
    status = Column(String(24), nullable=False, default="submitted", index=True)
    decision_note = Column(String(1000), nullable=True)
    reviewed_by = Column(UUID(as_uuid=True), ForeignKey("iam_users.id", ondelete="RESTRICT"), nullable=True)
    reviewed_at = Column(DateTime(timezone=True), nullable=True)
