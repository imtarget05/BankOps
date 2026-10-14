"""Add inv_stock_levels, inv_stocktakes, and inv_stocktake_lines.

Revision ID: 008_stock_levels_and_stocktakes
Revises: 007_user_profile_columns
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision = "008_stock_levels_and_stocktakes"
down_revision = "007_user_profile_columns"
branch_labels = None
depends_on = None


def upgrade():
    # The demo app historically called ``metadata.create_all`` before the
    # Alembic chain was upgraded.  Preserve that database's data and let the
    # migration stamp its already-created tables instead of failing on a
    # duplicate relation.  Fresh databases still receive the complete DDL.
    existing = set(sa.inspect(op.get_bind()).get_table_names())

    if "inv_stock_levels" not in existing:
        op.create_table(
            "inv_stock_levels",
            sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
            sa.Column("location_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("inv_locations.id", ondelete="CASCADE"), nullable=False),
            sa.Column("item_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("inv_items.id", ondelete="CASCADE"), nullable=False),
            sa.Column("min_qty", sa.Numeric(20, 3), nullable=False, server_default="0"),
            sa.Column("max_qty", sa.Numeric(20, 3), nullable=True),
            sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
            sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
            sa.UniqueConstraint("location_id", "item_id", name="uq_inv_stock_levels_loc_item"),
        )

    if "inv_stocktakes" not in existing:
        op.create_table(
            "inv_stocktakes",
            sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
            sa.Column("location_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("inv_locations.id"), nullable=False),
            sa.Column("status", sa.String(32), nullable=False, server_default="open"),
            sa.Column("note", sa.Text(), nullable=True),
            sa.Column("maker_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("iam_users.id"), nullable=False),
            sa.Column("approver_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("iam_users.id"), nullable=True),
            sa.Column("adjustment_request_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("inv_requests.id"), nullable=True),
            sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
            sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        )

    if "inv_stocktake_lines" not in existing:
        op.create_table(
            "inv_stocktake_lines",
            sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
            sa.Column("stocktake_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("inv_stocktakes.id", ondelete="CASCADE"), nullable=False),
            sa.Column("item_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("inv_items.id"), nullable=False),
            sa.Column("book_qty", sa.Numeric(20, 3), nullable=False, server_default="0"),
            sa.Column("counted_qty", sa.Numeric(20, 3), nullable=False, server_default="0"),
            sa.Column("variance", sa.Numeric(20, 3), nullable=False, server_default="0"),
            sa.Column("reason", sa.String(256), nullable=True),
            sa.UniqueConstraint("stocktake_id", "item_id", name="uq_stocktake_lines_st_item"),
        )


def downgrade():
    op.drop_table("inv_stocktake_lines")
    op.drop_table("inv_stocktakes")
    op.drop_table("inv_stock_levels")
