"""Create the durable `idempotency_keys` table (R2).

Revision ID: 027_idempotency_keys
Revises: 026_schema_alignment
Create Date: 2026-10-20

Context
-------
The Idempotency-Key store used to live **in memory per process**: after a
restart (or on another replica) the key was gone, so a retried write request
was executed twice. `cash_requests.idempotency_key` only covered cash
requests; other idempotent writes (inventory requests, reconciliations,
integration runs) had no durable record at all.

This migration adds the missing table:

* `key` — UNIQUE, the client-supplied `Idempotency-Key`
* `scope` — endpoint/namespace the key belongs to
* `request_hash` — SHA-256 of the canonical payload (A3/A4 conflict check)
* `status_code` / `response_body` — the response to replay; NULL while the
  request is still in flight (claimed but not finished)
* `expires_at` — retention window (mirrors `idempotency_key_retention_hours`)

The ORM class is imported at module level so that `Base.metadata` already
contains the table when Alembic compares the model with the live database
(`alembic check` must not report drift for a table the application owns).
"""

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

from alembic import op

# Import để đăng ký bảng vào `Base.metadata` khi Alembic so sánh model với DB
# thật (`alembic check` không được báo drift cho bảng mà app sở hữu).
from app.models.idempotency import IdempotencyKey  # noqa: F401

revision = "027_idempotency_keys"
down_revision = "026_schema_alignment"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if "idempotency_keys" in inspector.get_table_names():
        return
    op.create_table(
        "idempotency_keys",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("key", sa.String(length=128), nullable=False),
        sa.Column("scope", sa.String(length=128), nullable=False, server_default=""),
        sa.Column("request_hash", sa.String(length=64), nullable=False),
        sa.Column("status_code", sa.Integer(), nullable=True),
        sa.Column("response_body", sa.JSON(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.UniqueConstraint("key", name="uq_idempotency_keys_key"),
    )
    op.create_index(
        "ix_idempotency_keys_expires_at",
        "idempotency_keys",
        ["expires_at"],
    )


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if "idempotency_keys" not in inspector.get_table_names():
        return
    indexes = {i["name"] for i in inspector.get_indexes("idempotency_keys")}
    if "ix_idempotency_keys_expires_at" in indexes:
        op.drop_index("ix_idempotency_keys_expires_at", table_name="idempotency_keys")
    op.drop_table("idempotency_keys")
