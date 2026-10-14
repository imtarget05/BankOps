"""Add organizational branches, IAM scope grants, user provisioning, and ETL capabilities.

Revision ID: 013_iam_scopes_and_branches
Revises: 012_job_leases
"""
import uuid
from datetime import UTC, datetime

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

from alembic import op

revision = "013_iam_scopes_and_branches"
down_revision = "012_job_leases"
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    existing_tables = set(inspector.get_table_names())

    # 1. Create org_branches table
    if "org_branches" not in existing_tables:
        op.create_table(
            "org_branches",
            sa.Column("id", UUID(as_uuid=True), primary_key=True),
            sa.Column("code", sa.String(length=64), nullable=False, unique=True),
            sa.Column("name", sa.String(length=256), nullable=False),
            sa.Column("address", sa.String(length=512), nullable=True),
            sa.Column("active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        )
        op.create_index("ix_org_branches_code", "org_branches", ["code"])

    # 2. Add branch_id to inv_locations
    if "inv_locations" in existing_tables:
        loc_cols = {col["name"] for col in inspector.get_columns("inv_locations")}
        if "branch_id" not in loc_cols:
            op.add_column(
                "inv_locations",
                sa.Column("branch_id", UUID(as_uuid=True), sa.ForeignKey("org_branches.id", ondelete="SET NULL"), nullable=True),
            )

    # 3. Add columns to iam_users
    if "iam_users" in existing_tables:
        user_cols = {col["name"] for col in inspector.get_columns("iam_users")}
        if "branch_id" not in user_cols:
            op.add_column(
                "iam_users",
                sa.Column("branch_id", UUID(as_uuid=True), sa.ForeignKey("org_branches.id", ondelete="SET NULL"), nullable=True),
            )
        if "must_change_password" not in user_cols:
            op.add_column(
                "iam_users",
                sa.Column("must_change_password", sa.Boolean(), nullable=False, server_default=sa.text("false")),
            )
        if "invite_token_hash" not in user_cols:
            op.add_column(
                "iam_users",
                sa.Column("invite_token_hash", sa.String(length=128), nullable=True),
            )
        if "invite_expires_at" not in user_cols:
            op.add_column(
                "iam_users",
                sa.Column("invite_expires_at", sa.DateTime(timezone=True), nullable=True),
            )
        if "auth_version" not in user_cols:
            op.add_column(
                "iam_users",
                sa.Column("auth_version", sa.Integer(), nullable=False, server_default=sa.text("1")),
            )

    # 4. Create iam_scope_grants table
    if "iam_scope_grants" not in existing_tables:
        op.create_table(
            "iam_scope_grants",
            sa.Column("id", UUID(as_uuid=True), primary_key=True),
            sa.Column("user_id", UUID(as_uuid=True), sa.ForeignKey("iam_users.id", ondelete="CASCADE"), nullable=False, index=True),
            sa.Column("branch_id", UUID(as_uuid=True), sa.ForeignKey("org_branches.id", ondelete="CASCADE"), nullable=True),
            sa.Column("location_id", UUID(as_uuid=True), sa.ForeignKey("inv_locations.id", ondelete="CASCADE"), nullable=True),
            sa.Column("capability", sa.String(length=64), nullable=True),
            sa.Column("valid_from", sa.DateTime(timezone=True), nullable=True),
            sa.Column("valid_to", sa.DateTime(timezone=True), nullable=True),
            sa.Column("granted_by", UUID(as_uuid=True), sa.ForeignKey("iam_users.id", ondelete="SET NULL"), nullable=True),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        )
        op.create_index("ix_iam_scope_grants_user_branch", "iam_scope_grants", ["user_id", "branch_id"])

    # 5. Seed default branches and initial capabilities
    now = datetime.now(UTC)
    ho_id = uuid.UUID("11111111-1111-4111-8111-111111111111")
    bt_id = uuid.UUID("22222222-2222-4222-8222-222222222222")
    hk_id = uuid.UUID("33333333-3333-4333-8333-333333333333")

    branches_table = sa.table(
        "org_branches",
        sa.column("id", UUID(as_uuid=True)),
        sa.column("code", sa.String),
        sa.column("name", sa.String),
        sa.column("address", sa.String),
        sa.column("active", sa.Boolean),
        sa.column("created_at", sa.DateTime(timezone=True)),
        sa.column("updated_at", sa.DateTime(timezone=True)),
    )

    capabilities_table = sa.table(
        "iam_capabilities",
        sa.column("code", sa.String),
        sa.column("name", sa.String),
        sa.column("description", sa.String),
    )

    role_capabilities_table = sa.table(
        "iam_role_capabilities",
        sa.column("role_code", sa.String),
        sa.column("capability_code", sa.String),
    )

    # Insert branches if not present
    existing_branches = {row[0] for row in bind.execute(sa.text("SELECT code FROM org_branches")).fetchall()} if "org_branches" in existing_tables or True else set()
    branches_to_insert = [
        {"id": ho_id, "code": "HO", "name": "Hội Sở Chính - TP.HCM", "address": "123 Lê Lợi, Q.1, TP.HCM", "active": True, "created_at": now, "updated_at": now},
        {"id": bt_id, "code": "CN_BEN_THANH", "name": "Chi nhánh Bến Thành", "address": "45 Hai Bà Trưng, Q.1, TP.HCM", "active": True, "created_at": now, "updated_at": now},
        {"id": hk_id, "code": "CN_HOAN_KIEM", "name": "Chi nhánh Hoàn Kiếm", "address": "88 Phố Huế, Hoàn Kiếm, Hà Nội", "active": True, "created_at": now, "updated_at": now},
    ]
    for b in branches_to_insert:
        if b["code"] not in existing_branches:
            op.bulk_insert(branches_table, [b])

    # Insert new IAM & ETL capabilities
    new_caps = [
        ("iam:admin", "Quản trị người dùng & phân quyền", "Toàn quyền quản trị nhân viên, tài khoản, khóa và cấp quyền"),
        ("etl:admin", "Quản trị ETL", "Toàn quyền cấu hình kết nối và pipeline ETL"),
        ("etl:design", "Thiết kế mapping ETL", "Tạo và xuất bản phiên bản mapping ETL"),
        ("etl:run", "Chạy nhập liệu ETL", "Thực thi import dữ liệu theo phạm vi được gán"),
        ("etl:review", "Duyệt staging ETL", "Xem xét và chấp thuận dữ liệu staging ETL"),
        ("etl:post_balance", "Ghi sổ điều chỉnh tồn kho ETL", "Cho phép admin tự duyệt và post balance adjustment"),
    ]

    existing_caps = {row[0] for row in bind.execute(sa.text("SELECT code FROM iam_capabilities")).fetchall()}
    caps_to_insert = [
        {"code": code, "name": name, "description": desc}
        for code, name, desc in new_caps
        if code not in existing_caps
    ]
    if caps_to_insert:
        op.bulk_insert(capabilities_table, caps_to_insert)

    # Assign capabilities to roles
    role_cap_pairs = [
        ("admin", "iam:admin"),
        ("admin", "etl:admin"),
        ("admin", "etl:design"),
        ("admin", "etl:run"),
        ("admin", "etl:review"),
        ("admin", "etl:post_balance"),
        ("staff", "etl:run"),
        ("maker", "etl:run"),
        ("approver", "etl:review"),
        ("checker", "etl:review"),
        ("auditor", "etl:review"),
    ]
    existing_rc = {
        (row[0], row[1])
        for row in bind.execute(sa.text("SELECT role_code, capability_code FROM iam_role_capabilities")).fetchall()
    }
    rc_to_insert = [
        {"role_code": r, "capability_code": c}
        for r, c in role_cap_pairs
        if (r, c) not in existing_rc
    ]
    if rc_to_insert:
        op.bulk_insert(role_capabilities_table, rc_to_insert)

    # Link existing locations and users to HO branch if branch_id is null
    bind.execute(sa.text("UPDATE inv_locations SET branch_id = :ho_id WHERE branch_id IS NULL"), {"ho_id": ho_id})
    bind.execute(sa.text("UPDATE iam_users SET branch_id = :ho_id WHERE branch_id IS NULL"), {"ho_id": ho_id})


def downgrade():
    op.drop_table("iam_scope_grants")
    op.drop_column("iam_users", "auth_version")
    op.drop_column("iam_users", "invite_expires_at")
    op.drop_column("iam_users", "invite_token_hash")
    op.drop_column("iam_users", "must_change_password")
    op.drop_column("iam_users", "branch_id")
    op.drop_column("inv_locations", "branch_id")
    op.drop_table("org_branches")
