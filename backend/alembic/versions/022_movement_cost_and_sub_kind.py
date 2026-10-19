"""Movement sub_kind, unit_cost, cost_amount, and inv_lot_movements table.

Revision ID: 022_movement_cost_and_sub_kind
Revises: 021_receipt_invoice_and_lots
"""
import sqlalchemy as sa

from alembic import op

revision = "022_movement_cost_and_sub_kind"
down_revision = "021_receipt_invoice_and_lots"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)

    # 1. inv_movements columns
    mv_cols = {c["name"] for c in insp.get_columns("inv_movements")}
    if "sub_kind" not in mv_cols:
        op.add_column("inv_movements", sa.Column("sub_kind", sa.String(32), nullable=True))
    if "unit_cost" not in mv_cols:
        op.add_column("inv_movements", sa.Column("unit_cost", sa.Numeric(14, 2), nullable=True))
    if "cost_amount" not in mv_cols:
        op.add_column("inv_movements", sa.Column("cost_amount", sa.Numeric(20, 2), nullable=True))

    # 2. inv_lot_movements table
    tables = set(insp.get_table_names())
    if "inv_lot_movements" not in tables:
        op.create_table(
            "inv_lot_movements",
            sa.Column("id", sa.UUID(), primary_key=True),
            sa.Column(
                "movement_id",
                sa.UUID(),
                sa.ForeignKey("inv_movements.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column(
                "request_id",
                sa.UUID(),
                sa.ForeignKey("inv_requests.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column(
                "line_id",
                sa.UUID(),
                sa.ForeignKey("inv_request_lines.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column(
                "item_id",
                sa.UUID(),
                sa.ForeignKey("inv_items.id", ondelete="RESTRICT"),
                nullable=False,
            ),
            sa.Column(
                "location_id",
                sa.UUID(),
                sa.ForeignKey("inv_locations.id", ondelete="RESTRICT"),
                nullable=False,
            ),
            sa.Column("lot_no", sa.String(64), nullable=True),
            sa.Column("expiry_date", sa.Date(), nullable=True),
            sa.Column("quantity_signed", sa.Numeric(20, 3), nullable=False),
            sa.Column("unit_cost", sa.Numeric(14, 2), nullable=True),
            sa.Column("cost_amount", sa.Numeric(20, 2), nullable=True),
            sa.Column("sub_kind", sa.String(32), nullable=True),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        )
        op.create_index(
            "ix_inv_lot_movements_movement_id",
            "inv_lot_movements",
            ["movement_id"],
        )
        op.create_index(
            "ix_inv_lot_movements_request_id",
            "inv_lot_movements",
            ["request_id"],
        )


def downgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    tables = set(insp.get_table_names())
    if "inv_lot_movements" in tables:
        op.drop_table("inv_lot_movements")

    mv_cols = {c["name"] for c in insp.get_columns("inv_movements")}
    if "cost_amount" in mv_cols:
        op.drop_column("inv_movements", "cost_amount")
    if "unit_cost" in mv_cols:
        op.drop_column("inv_movements", "unit_cost")
    if "sub_kind" in mv_cols:
        op.drop_column("inv_movements", "sub_kind")
