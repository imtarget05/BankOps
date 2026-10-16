"""Add staged source synchronization requests.

Revision ID: 020_sync_requests
Revises: 019_user_avatar_and_root_iam
"""
from alembic import op
import sqlalchemy as sa

revision = "020_sync_requests"
down_revision = "019_user_avatar_and_root_iam"
branch_labels = None
depends_on = None

def upgrade() -> None:
    op.create_table(
        "sync_requests",
        sa.Column("id", sa.UUID(), primary_key=True),
        sa.Column("requester_id", sa.UUID(), sa.ForeignKey("iam_users.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("scope", sa.String(64), nullable=False),
        sa.Column("payload", sa.JSON(), nullable=False),
        sa.Column("status", sa.String(24), nullable=False),
        sa.Column("decision_note", sa.String(1000)),
        sa.Column("reviewed_by", sa.UUID(), sa.ForeignKey("iam_users.id", ondelete="RESTRICT")),
        sa.Column("reviewed_at", sa.DateTime(timezone=True)),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_sync_requests_status", "sync_requests", ["status"])
    op.create_index("ix_sync_requests_requester_id", "sync_requests", ["requester_id"])

def downgrade() -> None:
    op.drop_table("sync_requests")
