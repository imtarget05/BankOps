"""Add reserved_quantity, inv_asset_logs, and return_reason.

Revision ID: 009_reserved_inventory_and_asset_logs
Revises: 008_stock_levels_and_stocktakes
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision = "009_reserved_inv_asset_logs"
down_revision = "008_stock_levels_and_stocktakes"
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)

    def has_column(table: str, column: str) -> bool:
        return column in {entry["name"] for entry in inspector.get_columns(table)}

    # Support demo databases where metadata.create_all created the tables
    # before Alembic recorded this revision; never fail or overwrite data.
    if not has_column("inv_balances", "reserved_quantity"):
        op.add_column(
            "inv_balances",
            sa.Column("reserved_quantity", sa.Numeric(20, 3), nullable=False, server_default="0"),
        )

    if not has_column("inv_requests", "return_reason"):
        op.add_column(
            "inv_requests",
            sa.Column("return_reason", sa.Text(), nullable=True),
        )
    if not has_column("cash_requests", "return_reason"):
        op.add_column(
            "cash_requests",
            sa.Column("return_reason", sa.Text(), nullable=True),
        )

    if "inv_asset_logs" not in set(inspector.get_table_names()):
        op.create_table(
            "inv_asset_logs",
            sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
            sa.Column("asset_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("inv_assets.id", ondelete="CASCADE"), nullable=False),
            sa.Column("serial", sa.String(128), nullable=False),
            sa.Column("from_location_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("inv_locations.id"), nullable=True),
            sa.Column("to_location_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("inv_locations.id"), nullable=True),
            sa.Column("from_assignee", sa.String(128), nullable=True),
            sa.Column("to_assignee", sa.String(128), nullable=True),
            sa.Column("status_before", sa.String(32), nullable=True),
            sa.Column("status_after", sa.String(32), nullable=False),
            sa.Column("request_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("inv_requests.id"), nullable=True),
            sa.Column("actor_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("iam_users.id"), nullable=True),
            sa.Column("notes", sa.Text(), nullable=True),
            sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        )


def downgrade():
    op.drop_table("inv_asset_logs")
    op.drop_column("cash_requests", "return_reason")
    op.drop_column("inv_requests", "return_reason")
    op.drop_column("inv_balances", "reserved_quantity")
