"""Add the timestamp inherited by the canonical Stocktake mapping.

Revision ID: 010_stocktake_updated_at
Revises: 009_reserved_inv_asset_logs
"""

import sqlalchemy as sa

from alembic import op

revision = "010_stocktake_updated_at"
down_revision = "009_reserved_inv_asset_logs"
branch_labels = None
depends_on = None


def upgrade():
    columns = {
        entry["name"] for entry in sa.inspect(op.get_bind()).get_columns("inv_stocktakes")
    }
    if "updated_at" not in columns:
        op.add_column(
            "inv_stocktakes",
            sa.Column(
                "updated_at",
                sa.DateTime(timezone=True),
                nullable=False,
                server_default=sa.text("now()"),
            ),
        )


def downgrade():
    op.drop_column("inv_stocktakes", "updated_at")
