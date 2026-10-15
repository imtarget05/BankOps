"""Add shift-count fields for tea-shop stocktaking.

Revision ID: 016_shift_stocktake_fields
Revises: 015_tea_ingredient_catalog
"""
from alembic import op
import sqlalchemy as sa


revision = "016_shift_stocktake_fields"
down_revision = "015_tea_ingredient_catalog"
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    stocktakes = {column["name"] for column in sa.inspect(bind).get_columns("inv_stocktakes")}
    lines = {column["name"] for column in sa.inspect(bind).get_columns("inv_stocktake_lines")}
    if "business_date" not in stocktakes:
        op.add_column("inv_stocktakes", sa.Column("business_date", sa.Date(), nullable=True))
    if "shift_code" not in stocktakes:
        op.add_column("inv_stocktakes", sa.Column("shift_code", sa.String(length=16), nullable=True))
    for name in ("opening_qty", "received_qty", "used_qty", "theoretical_qty"):
        if name not in lines:
            op.add_column(
                "inv_stocktake_lines",
                sa.Column(name, sa.Numeric(20, 3), nullable=False, server_default="0"),
            )


def downgrade():
    for name in ("theoretical_qty", "used_qty", "received_qty", "opening_qty"):
        op.drop_column("inv_stocktake_lines", name)
    op.drop_column("inv_stocktakes", "shift_code")
    op.drop_column("inv_stocktakes", "business_date")
