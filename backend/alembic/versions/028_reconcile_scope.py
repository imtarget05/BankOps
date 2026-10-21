"""Add authorization-scope columns to reconciliation_exceptions (B2 follow-up).

Revision ID: 028_reconcile_scope
Revises: 027_idempotency_keys
Create Date: 2026-10-21

Context
-------
Reconciliation exceptions are created per-user scope (POST /reconciliations
already filters journals/balances by get_accessible_cashbox_ids /
get_accessible_location_ids), but the exception rows themselves carry no
scope column. The dashboard (GET /dashboard/summary) therefore lists every
run's exceptions regardless of the caller's branch — a scoped user can see
exception counts for cashboxes/locations outside their authorization.

This migration adds:

* ``cashbox_id`` — nullable FK to ``cash_boxes.id``, set for cash-scope
  exceptions so the dashboard can filter by the caller's accessible cashboxes.
* ``location_id`` — nullable FK to ``inv_locations.id``, set for inventory-
  scope exceptions so the dashboard can filter by the caller's accessible
  locations.
* ``resolved`` — boolean, default false, so the dashboard can report
  open vs. total exception counters.

All columns are nullable/additive: existing rows keep working, new rows
produced by POST /reconciliations populate the scope columns.
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision = "028_reconcile_scope"
down_revision = "027_idempotency_keys"
branch_labels = None
depends_on = None


def _has_column(table: str, column: str) -> bool:
    inspector = sa.inspect(op.get_bind())
    if table not in inspector.get_table_names():
        return False
    return column in {c["name"] for c in inspector.get_columns(table)}


def _has_foreign_key(table: str, column: str) -> bool:
    inspector = sa.inspect(op.get_bind())
    if table not in inspector.get_table_names():
        return False
    fks = inspector.get_foreign_keys(table)
    return any(
        column in (fk.get("column_names") or []) for fk in fks
    )


def upgrade() -> None:
    if not _has_column("reconciliation_exceptions", "cashbox_id"):
        op.add_column(
            "reconciliation_exceptions",
            sa.Column(
                "cashbox_id",
                postgresql.UUID(as_uuid=True),
                nullable=True,
            ),
        )
    if not _has_foreign_key("reconciliation_exceptions", "cashbox_id"):
        op.create_foreign_key(
            "fk_reconciliation_exceptions_cashbox_id_cash_boxes",
            "reconciliation_exceptions",
            "cash_boxes",
            ["cashbox_id"],
            ["id"],
            ondelete="SET NULL",
        )

    if not _has_column("reconciliation_exceptions", "location_id"):
        op.add_column(
            "reconciliation_exceptions",
            sa.Column(
                "location_id",
                postgresql.UUID(as_uuid=True),
                nullable=True,
            ),
        )
    if not _has_foreign_key("reconciliation_exceptions", "location_id"):
        op.create_foreign_key(
            "fk_reconciliation_exceptions_location_id_inv_locations",
            "reconciliation_exceptions",
            "inv_locations",
            ["location_id"],
            ["id"],
            ondelete="SET NULL",
        )

    if not _has_column("reconciliation_exceptions", "resolved"):
        op.add_column(
            "reconciliation_exceptions",
            sa.Column("resolved", sa.Boolean, nullable=False, server_default="false"),
        )


def downgrade() -> None:
    inspector = sa.inspect(op.get_bind())
    if "reconciliation_exceptions" not in inspector.get_table_names():
        return

    for fk_name, _cols in (
        ("fk_reconciliation_exceptions_cashbox_id_cash_boxes", ["cashbox_id"]),
        ("fk_reconciliation_exceptions_location_id_inv_locations", ["location_id"]),
    ):
        fks = inspector.get_foreign_keys("reconciliation_exceptions")
        if any(fk_name in (fk.get("name") or "") for fk in fks):
            op.drop_constraint(fk_name, "reconciliation_exceptions", type_="foreignkey")

    for column in ("resolved", "location_id", "cashbox_id"):
        if _has_column("reconciliation_exceptions", column):
            op.drop_column("reconciliation_exceptions", column)