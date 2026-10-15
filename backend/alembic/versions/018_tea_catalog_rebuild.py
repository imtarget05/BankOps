"""Grant tea-shop managers checker access without touching inventory data.

The customer migration must preserve historical inventory, requests, and
stocktakes. It only adds the capabilities a store manager needs to approve
shift close-outs and adjustment requests.

Revision ID: 018_tea_catalog_rebuild
Revises: 017_tea_receipt_lot_expiry
"""
from alembic import op

revision = "018_tea_catalog_rebuild"
down_revision = "017_tea_receipt_lot_expiry"
branch_labels = None
depends_on = None

def upgrade():
    for capability in (
        "inventory:create_request",
        "inventory:approve_request",
        "approval:view_inbox",
    ):
        op.execute(
            "INSERT INTO iam_role_capabilities (role_code, capability_code) "
            f"VALUES ('inventory_manager', '{capability}') "
            "ON CONFLICT (role_code, capability_code) DO NOTHING"
        )


def downgrade():
    op.execute(
        "DELETE FROM iam_role_capabilities "
        "WHERE role_code = 'inventory_manager' "
        "AND capability_code IN ("
        "'inventory:create_request', 'inventory:approve_request', 'approval:view_inbox'"
        ")"
    )
