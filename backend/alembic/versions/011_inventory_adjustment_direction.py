"""Make inventory adjustment direction explicit while keeping line quantities positive.

Revision ID: 011_inventory_adjustment_direction
Revises: 010_stocktake_updated_at
"""

import sqlalchemy as sa

from alembic import op

revision = "011_inventory_adjustment_dir"
down_revision = "010_stocktake_updated_at"
branch_labels = None
depends_on = None


def upgrade():
    inspector = sa.inspect(op.get_bind())
    columns = {entry["name"] for entry in inspector.get_columns("inv_request_lines")}
    if "direction" not in columns:
        op.add_column(
            "inv_request_lines",
            sa.Column(
                "direction",
                sa.String(length=16),
                nullable=False,
                server_default="increase",
            ),
        )

    constraints = {
        entry["name"] for entry in inspector.get_check_constraints("inv_request_lines")
    }
    if "request_line_direction_valid" not in constraints:
        op.create_check_constraint(
            "request_line_direction_valid",
            "inv_request_lines",
            "direction IN ('increase', 'decrease')",
        )


def downgrade():
    op.drop_constraint(
        "request_line_direction_valid", "inv_request_lines", type_="check"
    )
    op.drop_column("inv_request_lines", "direction")
