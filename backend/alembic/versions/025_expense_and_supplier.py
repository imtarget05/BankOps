"""Create suppliers and expenses tables for Phase M data engineering.

Revision ID: 025_expense_and_supplier
Revises: 024_add_branch_id_to_cashbox
"""
import sqlalchemy as sa

from alembic import op

revision = "025_expense_and_supplier"
down_revision = "024_add_branch_id_to_cashbox"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)

    # suppliers table
    if "suppliers" not in insp.get_table_names():
        op.create_table(
            "suppliers",
            sa.Column(
                "id",
                sa.UUID(as_uuid=True),
                nullable=False,
            ),
            sa.Column("code", sa.String(length=64), nullable=False),
            sa.Column("name", sa.String(length=256), nullable=False),
            sa.Column("contact_person", sa.String(length=256), nullable=True),
            sa.Column("phone", sa.String(length=32), nullable=True),
            sa.Column("email", sa.String(length=256), nullable=True),
            sa.Column("address", sa.String(length=512), nullable=True),
            sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
            sa.Column(
                "branch_id",
                sa.UUID(as_uuid=True),
                sa.ForeignKey("org_branches.id", ondelete="SET NULL"),
                nullable=True,
            ),
            sa.Column(
                "created_at",
                sa.DateTime(timezone=True),
                nullable=False,
            ),
            sa.Column(
                "updated_at",
                sa.DateTime(timezone=True),
                nullable=False,
            ),
            sa.PrimaryKeyConstraint("id", name="pk_suppliers"),
            sa.UniqueConstraint("code", name="uq_suppliers_code"),
        )
        op.create_index("ix_suppliers_branch_id", "suppliers", ["branch_id"])

    # expenses table
    if "expenses" not in insp.get_table_names():
        op.create_table(
            "expenses",
            sa.Column(
                "id",
                sa.UUID(as_uuid=True),
                nullable=False,
            ),
            sa.Column("expense_code", sa.String(length=64), nullable=False),
            sa.Column(
                "supplier_id",
                sa.UUID(as_uuid=True),
                sa.ForeignKey("suppliers.id", ondelete="SET NULL"),
                nullable=True,
            ),
            sa.Column("category", sa.String(length=128), nullable=False),
            sa.Column("amount", sa.Numeric(precision=14, scale=2), nullable=False),
            sa.Column("currency", sa.String(length=8), nullable=False, server_default="VND"),
            sa.Column("expense_date", sa.Date(), nullable=False),
            sa.Column("description", sa.String(length=1024), nullable=True),
            sa.Column("status", sa.String(length=32), nullable=False, server_default="draft"),
            sa.Column(
                "branch_id",
                sa.UUID(as_uuid=True),
                sa.ForeignKey("org_branches.id", ondelete="SET NULL"),
                nullable=True,
            ),
            sa.Column(
                "created_at",
                sa.DateTime(timezone=True),
                nullable=False,
            ),
            sa.Column(
                "updated_at",
                sa.DateTime(timezone=True),
                nullable=False,
            ),
            sa.PrimaryKeyConstraint("id", name="pk_expenses"),
            sa.UniqueConstraint("expense_code", name="uq_expenses_expense_code"),
            sa.CheckConstraint("amount >= 0", name="ck_expenses_amount_non_negative"),
        )
        op.create_index("ix_expenses_branch_id", "expenses", ["branch_id"])
        op.create_index("ix_expenses_expense_date", "expenses", ["expense_date"])
        op.create_index("ix_expenses_supplier_id", "expenses", ["supplier_id"])


def downgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)

    if "expenses" in insp.get_table_names():
        op.drop_index("ix_expenses_supplier_id", table_name="expenses")
        op.drop_index("ix_expenses_expense_date", table_name="expenses")
        op.drop_index("ix_expenses_branch_id", table_name="expenses")
        op.drop_table("expenses")

    if "suppliers" in insp.get_table_names():
        op.drop_index("ix_suppliers_branch_id", table_name="suppliers")
        op.drop_table("suppliers")
