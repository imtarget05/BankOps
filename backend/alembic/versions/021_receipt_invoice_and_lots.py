"""Receipt multi-line invoice, sub_kind, and lot balances tracking.

Revision ID: 021_receipt_invoice_and_lots
Revises: 020_sync_requests
"""
import uuid
from datetime import UTC, date, datetime

import sqlalchemy as sa
from alembic import op

revision = "021_receipt_invoice_and_lots"
down_revision = "020_sync_requests"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)

    # 1. inv_requests columns
    req_cols = {c["name"] for c in insp.get_columns("inv_requests")}
    if "invoice_no" not in req_cols:
        op.add_column("inv_requests", sa.Column("invoice_no", sa.String(128), nullable=True))
    if "sub_kind" not in req_cols:
        op.add_column("inv_requests", sa.Column("sub_kind", sa.String(32), nullable=True))

    # 2. inv_request_lines columns
    line_cols = {c["name"] for c in insp.get_columns("inv_request_lines")}
    if "unit" not in line_cols:
        op.add_column("inv_request_lines", sa.Column("unit", sa.String(32), nullable=True))
    if "conversion_rate" not in line_cols:
        op.add_column("inv_request_lines", sa.Column("conversion_rate", sa.Numeric(10, 4), nullable=True))

    # 3. inv_lot_balances table
    tables = set(insp.get_table_names())
    if "inv_lot_balances" not in tables:
        op.create_table(
            "inv_lot_balances",
            sa.Column("id", sa.UUID(), primary_key=True),
            sa.Column(
                "location_id",
                sa.UUID(),
                sa.ForeignKey("inv_locations.id", ondelete="RESTRICT"),
                nullable=False,
            ),
            sa.Column(
                "item_id",
                sa.UUID(),
                sa.ForeignKey("inv_items.id", ondelete="RESTRICT"),
                nullable=False,
            ),
            sa.Column("lot_no", sa.String(64), nullable=True),
            sa.Column("expiry_date", sa.Date(), nullable=True),
            sa.Column("quantity", sa.Numeric(20, 3), nullable=False, server_default="0"),
            sa.Column("unit_cost", sa.Numeric(14, 2), nullable=True),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
            sa.CheckConstraint("quantity >= 0", name="lot_qty_non_negative"),
        )
        op.create_index("ix_inv_lot_balances_loc", "inv_lot_balances", ["location_id"])
        op.create_index("ix_inv_lot_balances_item", "inv_lot_balances", ["item_id"])
        op.create_index("ix_inv_lot_balances_exp", "inv_lot_balances", ["expiry_date"])
        op.execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_lot_balance_record "
            "ON inv_lot_balances (location_id, item_id, COALESCE(lot_no, ''), COALESCE(expiry_date, '2099-12-31'))"
        )

    # 4. Seed initial lot balances from existing inv_balances
    # Hàng tồn kho hiện có được chuyển đổi thành lô 'TON-DAU-KY' (HSD 2099-12-31)
    # để bảo đảm tương thích ngược và có thể xuất kho bình thường.
    now = datetime.now(UTC)
    far_future = date(2099, 12, 31)
    balances = bind.execute(
        sa.text(
            "SELECT b.location_id, b.item_id, b.quantity, i.cost_price "
            "FROM inv_balances b "
            "LEFT JOIN inv_items i ON i.id = b.item_id "
            "WHERE b.quantity > 0"
        )
    ).fetchall()

    for row in balances:
        loc_id, it_id, qty, cost = row[0], row[1], row[2], row[3]
        exists = bind.execute(
            sa.text(
                "SELECT 1 FROM inv_lot_balances WHERE location_id = :loc AND item_id = :it"
            ),
            {"loc": loc_id, "it": it_id},
        ).first()
        if not exists:
            bind.execute(
                sa.text(
                    "INSERT INTO inv_lot_balances (id, location_id, item_id, lot_no, expiry_date, quantity, unit_cost, created_at, updated_at) "
                    "VALUES (:id, :loc, :it, 'TON-DAU-KY', :exp, :qty, :cost, :now, :now)"
                ),
                {
                    "id": uuid.uuid4(),
                    "loc": loc_id,
                    "it": it_id,
                    "exp": far_future,
                    "qty": qty,
                    "cost": cost,
                    "now": now,
                },
            )


def downgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    tables = set(insp.get_table_names())
    if "inv_lot_balances" in tables:
        op.drop_table("inv_lot_balances")

    req_cols = {c["name"] for c in insp.get_columns("inv_requests")}
    if "invoice_no" in req_cols:
        op.drop_column("inv_requests", "invoice_no")
    if "sub_kind" in req_cols:
        op.drop_column("inv_requests", "sub_kind")

    line_cols = {c["name"] for c in insp.get_columns("inv_request_lines")}
    if "conversion_rate" in line_cols:
        op.drop_column("inv_request_lines", "conversion_rate")
    if "unit" in line_cols:
        op.drop_column("inv_request_lines", "unit")
