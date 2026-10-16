"""Add a safe profile avatar field and the root IAM role/capabilities.

Revision ID: 019_user_avatar_and_root_iam
Revises: 018_tea_catalog_rebuild
"""
from alembic import op
import sqlalchemy as sa

revision = "019_user_avatar_and_root_iam"
down_revision = "018_tea_catalog_rebuild"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("iam_users", sa.Column("avatar_url", sa.String(length=2048), nullable=True))
    op.execute("""
        INSERT INTO iam_roles (code, name, description, created_at, updated_at)
        VALUES ('root_admin', 'Root Administrator', 'Emergency enterprise administrator', NOW(), NOW())
        ON CONFLICT (code) DO NOTHING
    """)
    for code, name in (
        ("iam:root", "Root IAM administration"),
        ("sync:request", "Request source data synchronization"),
        ("sync:approve_root", "Approve source data synchronization"),
    ):
        op.execute(
            "INSERT INTO iam_capabilities (code, name, description, created_at, updated_at) "
            f"VALUES ('{code}', '{name}', 'Enterprise synchronization control', NOW(), NOW()) "
            "ON CONFLICT (code) DO NOTHING"
        )
    op.execute("""
        INSERT INTO iam_role_capabilities (role_code, capability_code)
        SELECT 'root_admin', code FROM iam_capabilities
        ON CONFLICT (role_code, capability_code) DO NOTHING
    """)


def downgrade() -> None:
    op.execute("DELETE FROM iam_role_capabilities WHERE role_code = 'root_admin'")
    op.execute("DELETE FROM iam_roles WHERE code = 'root_admin'")
    op.execute("DELETE FROM iam_capabilities WHERE code IN ('iam:root', 'sync:request', 'sync:approve_root')")
    op.drop_column("iam_users", "avatar_url")
