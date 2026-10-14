"""Persist worker leases and retry scheduling for durable background jobs.

Revision ID: 012_job_leases
Revises: 011_inventory_adjustment_dir
"""

import sqlalchemy as sa

from alembic import op

revision = "012_job_leases"
down_revision = "011_inventory_adjustment_dir"
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    columns = {column["name"] for column in inspector.get_columns("jobs")}

    additions = (
        ("lease_owner", sa.Column("lease_owner", sa.String(length=128), nullable=True)),
        ("lease_token", sa.Column("lease_token", sa.String(length=64), nullable=True)),
        ("lease_until", sa.Column("lease_until", sa.DateTime(timezone=True), nullable=True)),
        ("heartbeat_at", sa.Column("heartbeat_at", sa.DateTime(timezone=True), nullable=True)),
        (
            "retry_count",
            sa.Column(
                "retry_count",
                sa.Integer(),
                nullable=False,
                server_default=sa.text("0"),
            ),
        ),
        ("next_attempt", sa.Column("next_attempt", sa.DateTime(timezone=True), nullable=True)),
    )
    for name, column in additions:
        if name not in columns:
            op.add_column("jobs", column)

    indexes = {index["name"] for index in inspector.get_indexes("jobs")}
    if "ix_jobs_claimable" not in indexes:
        op.create_index(
            "ix_jobs_claimable",
            "jobs",
            ["status", "next_attempt", "lease_until"],
            unique=False,
        )

    unique_constraints = {
        constraint["name"]
        for constraint in inspector.get_unique_constraints("activity_events")
    }
    if "uq_activity_events_outbox_event_id" not in unique_constraints:
        op.create_unique_constraint(
            "uq_activity_events_outbox_event_id",
            "activity_events",
            ["outbox_event_id"],
        )


def downgrade():
    op.drop_constraint(
        "uq_activity_events_outbox_event_id",
        "activity_events",
        type_="unique",
    )
    op.drop_index("ix_jobs_claimable", table_name="jobs")
    for name in (
        "next_attempt",
        "retry_count",
        "heartbeat_at",
        "lease_until",
        "lease_token",
        "lease_owner",
    ):
        op.drop_column("jobs", name)
