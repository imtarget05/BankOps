"""Add ETL pipeline 4-layer tables: connections, pipelines, mapping versions, runs, run rows.

Revision ID: 014_etl_pipeline_models
Revises: 013_iam_scopes_and_branches
"""
import uuid

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

from alembic import op

revision = "014_etl_pipeline_models"
down_revision = "013_iam_scopes_and_branches"
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    existing_tables = set(inspector.get_table_names())

    # 1. etl_connections
    if "etl_connections" not in existing_tables:
        op.create_table(
            "etl_connections",
            sa.Column("id", UUID(as_uuid=True), primary_key=True, default=uuid.uuid4),
            sa.Column("name", sa.String(length=256), nullable=False),
            sa.Column("type", sa.String(length=64), nullable=False),
            sa.Column("status", sa.String(length=32), nullable=False, server_default="active"),
            sa.Column("secret_ref", sa.String(length=256), nullable=True),
            sa.Column("allowlist_sheets", sa.JSON(), nullable=True),
            sa.Column("config_json", sa.JSON(), nullable=True),
            sa.Column("branch_id", UUID(as_uuid=True), sa.ForeignKey("org_branches.id", ondelete="SET NULL"), nullable=True),
            sa.Column("owner_id", UUID(as_uuid=True), sa.ForeignKey("iam_users.id", ondelete="SET NULL"), nullable=True),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        )
        op.create_index("ix_etl_connections_branch_id", "etl_connections", ["branch_id"])

    # 2. etl_pipelines
    if "etl_pipelines" not in existing_tables:
        op.create_table(
            "etl_pipelines",
            sa.Column("id", UUID(as_uuid=True), primary_key=True, default=uuid.uuid4),
            sa.Column("name", sa.String(length=256), nullable=False),
            sa.Column("target", sa.String(length=64), nullable=False),
            sa.Column("connection_id", UUID(as_uuid=True), sa.ForeignKey("etl_connections.id", ondelete="CASCADE"), nullable=False),
            sa.Column("branch_id", UUID(as_uuid=True), sa.ForeignKey("org_branches.id", ondelete="SET NULL"), nullable=True),
            sa.Column("location_id", UUID(as_uuid=True), sa.ForeignKey("inv_locations.id", ondelete="SET NULL"), nullable=True),
            sa.Column("destination_location_id", UUID(as_uuid=True), sa.ForeignKey("inv_locations.id", ondelete="SET NULL"), nullable=True),
            sa.Column("schedule_cron", sa.String(length=128), nullable=True),
            sa.Column("status", sa.String(length=32), nullable=False, server_default="active"),
            sa.Column("owner_id", UUID(as_uuid=True), sa.ForeignKey("iam_users.id", ondelete="SET NULL"), nullable=True),
            sa.Column("config_json", sa.JSON(), nullable=True),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        )
        op.create_index("ix_etl_pipelines_branch_id", "etl_pipelines", ["branch_id"])
        op.create_index("ix_etl_pipelines_target", "etl_pipelines", ["target"])

    # 3. etl_mapping_versions
    if "etl_mapping_versions" not in existing_tables:
        op.create_table(
            "etl_mapping_versions",
            sa.Column("id", UUID(as_uuid=True), primary_key=True, default=uuid.uuid4),
            sa.Column("pipeline_id", UUID(as_uuid=True), sa.ForeignKey("etl_pipelines.id", ondelete="CASCADE"), nullable=False),
            sa.Column("version", sa.Integer(), nullable=False, server_default="1"),
            sa.Column("status", sa.String(length=32), nullable=False, server_default="draft"),
            sa.Column("mapping_json", sa.JSON(), nullable=False),
            sa.Column("validation_rules_json", sa.JSON(), nullable=True),
            sa.Column("duplicate_policy", sa.String(length=32), nullable=False, server_default="reject"),
            sa.Column("created_by", UUID(as_uuid=True), sa.ForeignKey("iam_users.id", ondelete="SET NULL"), nullable=True),
            sa.Column("published_at", sa.DateTime(timezone=True), nullable=True),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.UniqueConstraint("pipeline_id", "version", name="uq_etl_mapping_pipeline_version"),
        )

    # 4. etl_runs
    if "etl_runs" not in existing_tables:
        op.create_table(
            "etl_runs",
            sa.Column("id", UUID(as_uuid=True), primary_key=True, default=uuid.uuid4),
            sa.Column("pipeline_id", UUID(as_uuid=True), sa.ForeignKey("etl_pipelines.id", ondelete="CASCADE"), nullable=False),
            sa.Column("mapping_version_id", UUID(as_uuid=True), sa.ForeignKey("etl_mapping_versions.id", ondelete="SET NULL"), nullable=True),
            sa.Column("mapping_version_num", sa.Integer(), nullable=False, server_default="1"),
            sa.Column("runner_id", UUID(as_uuid=True), sa.ForeignKey("iam_users.id", ondelete="SET NULL"), nullable=False),
            sa.Column("status", sa.String(length=32), nullable=False, server_default="staged"),
            sa.Column("progress_pct", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("total_rows", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("valid_rows", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("invalid_rows", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("source_fingerprint", sa.String(length=128), nullable=False),
            sa.Column("external_event_id", sa.String(length=256), nullable=True),
            sa.Column("single_admin_override", sa.Boolean(), nullable=False, server_default=sa.text("false")),
            sa.Column("reviewer_id", UUID(as_uuid=True), sa.ForeignKey("iam_users.id", ondelete="SET NULL"), nullable=True),
            sa.Column("review_decision", sa.String(length=32), nullable=True),
            sa.Column("review_note", sa.String(length=512), nullable=True),
            sa.Column("posted_at", sa.DateTime(timezone=True), nullable=True),
            sa.Column("generated_reference_type", sa.String(length=64), nullable=True),
            sa.Column("generated_reference_id", sa.String(length=128), nullable=True),
            sa.Column("error_code", sa.String(length=64), nullable=True),
            sa.Column("error_message", sa.String(length=512), nullable=True),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        )
        op.create_index("ix_etl_runs_pipeline_id", "etl_runs", ["pipeline_id"])
        op.create_index("ix_etl_runs_source_fingerprint", "etl_runs", ["source_fingerprint"])
        op.create_index("ix_etl_runs_status", "etl_runs", ["status"])

    # 5. etl_run_rows
    if "etl_run_rows" not in existing_tables:
        op.create_table(
            "etl_run_rows",
            sa.Column("id", UUID(as_uuid=True), primary_key=True, default=uuid.uuid4),
            sa.Column("run_id", UUID(as_uuid=True), sa.ForeignKey("etl_runs.id", ondelete="CASCADE"), nullable=False),
            sa.Column("row_number", sa.Integer(), nullable=False),
            sa.Column("source_row_key", sa.String(length=256), nullable=True),
            sa.Column("raw_data_json", sa.JSON(), nullable=False),
            sa.Column("canonical_data_json", sa.JSON(), nullable=True),
            sa.Column("valid", sa.Boolean(), nullable=False, server_default=sa.text("true")),
            sa.Column("errors_json", sa.JSON(), nullable=True),
            sa.Column("action_preview", sa.JSON(), nullable=True),
        )
        op.create_index("ix_etl_run_rows_run_number", "etl_run_rows", ["run_id", "row_number"])


def downgrade():
    op.drop_table("etl_run_rows")
    op.drop_table("etl_runs")
    op.drop_table("etl_mapping_versions")
    op.drop_table("etl_pipelines")
    op.drop_table("etl_connections")
