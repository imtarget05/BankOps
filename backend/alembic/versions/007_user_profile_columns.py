"""Add email, phone_number, and branch to iam_users for profile persistence.

Revision ID: 007_user_profile_columns
Revises: 006_user_pin_hash
"""

import sqlalchemy as sa

from alembic import op

revision = "007_user_profile_columns"
down_revision = "006_user_pin_hash"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("iam_users", sa.Column("email", sa.String(256), nullable=True))
    op.add_column("iam_users", sa.Column("phone_number", sa.String(32), nullable=True))
    op.add_column("iam_users", sa.Column("branch", sa.String(256), nullable=True))


def downgrade():
    op.drop_column("iam_users", "branch")
    op.drop_column("iam_users", "phone_number")
    op.drop_column("iam_users", "email")
