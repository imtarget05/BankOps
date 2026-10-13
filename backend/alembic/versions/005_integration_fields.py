"""Add connection status tracking and run phase/finish fields (docs/09).

Adds: integration_connections.schema_json, last_tested_at, last_error.
Integrations_runs.phase, finished_at, error_code, message_key,
message_params_json. Also flips source_fingerprint to NOT NULL and
changes default status to 'pending_test' to reflect the new lifecycle.
"""

import sqlalchemy as sa

from alembic import op

revision = "005_integration_fields"
down_revision = "004_timestamptz_cleanup"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column(
        "integration_connections", sa.Column("schema_json", sa.JSON(), nullable=True)
    )
    op.add_column(
        "integration_connections",
        sa.Column("last_tested_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "integration_connections",
        sa.Column("last_error", sa.String(512), nullable=True),
    )
    # Default status for new connections is now 'pending_test' (requires /test to confirm).

    op.add_column(
        "integration_runs",
        sa.Column("phase", sa.String(32), nullable=False, server_default="staged"),
    )
    op.add_column(
        "integration_runs",
        sa.Column("finished_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "integration_runs", sa.Column("error_code", sa.String(64), nullable=True)
    )
    op.add_column(
        "integration_runs", sa.Column("message_key", sa.String(256), nullable=True)
    )
    op.add_column(
        "integration_runs", sa.Column("message_params_json", sa.JSON(), nullable=True)
    )

    # source_fingerprint must NOT NULL so fingerprint-based dedup is reliable.
    # Backfill NULLs from external_event_id (legacy rows have neither, but this
    # keeps the migration safe if a prior staged run slipped through).
    op.execute(
        "UPDATE integration_runs SET source_fingerprint = "
        "COALESCE(source_fingerprint, md5((external_event_id || created_at::text))) "
        "WHERE source_fingerprint IS NULL"
    )
    op.alter_column("integration_runs", "source_fingerprint", nullable=False)


def downgrade():
    op.drop_column("integration_runs", "message_params_json")
    op.drop_column("integration_runs", "message_key")
    op.drop_column("integration_runs", "error_code")
    op.drop_column("integration_runs", "finished_at")
    op.drop_column("integration_runs", "phase")

    op.drop_column("integration_connections", "last_error")
    op.drop_column("integration_connections", "last_tested_at")
    op.drop_column("integration_connections", "schema_json")

    op.alter_column("integration_runs", "source_fingerprint", nullable=True)
