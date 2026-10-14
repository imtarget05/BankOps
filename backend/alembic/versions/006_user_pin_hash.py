"""Add pin_hash to iam_users for supervisor PIN management.

Revision ID: 006_user_pin_hash
Revises: 005_integration_fields
"""

import sqlalchemy as sa

from alembic import op

revision = "006_user_pin_hash"
down_revision = "005_integration_fields"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column(
        "iam_users",
        sa.Column("pin_hash", sa.String(256), nullable=True),
    )


def downgrade():
    op.drop_column("iam_users", "pin_hash")
