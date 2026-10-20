"""Schema-parity declarations for objects owned by other modules.

The migration chain (Alembic) and the ORM models must describe the *same*
database, otherwise ``alembic check`` reports drift and a database built by
``alembic upgrade head`` is not the database the application expects.

Two columns live in that intersection but their declarative model lives in
``app/models/cash_sim.py``, which is owned by another change stream and must
not be edited here:

* ``cash_boxes.branch_id`` — added by migration ``024_add_branch_id_to_cashbox``
  for branch-scoped cash isolation. The ORM class never declared it, so
  autogenerate saw the column as "unknown to the app" and wanted to DROP it.
* ``cash_balances.created_at`` / ``cash_balances.updated_at`` — created by
  migration ``002_idempotency_and_balances`` with a ``now()`` server default.
  ``CashBalance`` does not mix in ``TimestampMixin``, so the same drift
  appeared.

Both objects exist in the deployed schema and in the ORM's table metadata
after this module runs, so:

* autogenerate stops proposing to drop them, and
* ``Base.metadata.create_all`` keeps creating them for databases that are
  bootstrapped by the application instead of by Alembic.

The columns are appended to the mapped tables; the declarative classes are
intentionally left untouched (they are not the owner of these columns).
"""

from sqlalchemy import Column, DateTime, ForeignKey, Index, text
from sqlalchemy.dialects.postgresql import UUID

from app.models.cash_sim import CashBalance, CashBox

# --- cash_boxes.branch_id (migration 024) ---------------------------------
CashBox.__table__.append_column(
    Column(
        "branch_id",
        UUID(as_uuid=True),
        ForeignKey("org_branches.id", ondelete="SET NULL"),
        nullable=True,
    )
)
CashBox.__table__.append_constraint(
    Index("ix_cash_boxes_branch_id", "branch_id")
)

# --- cash_balances.created_at / updated_at (migration 002) ----------------
CashBalance.__table__.append_column(
    Column(
        "created_at",
        DateTime(timezone=True),
        nullable=False,
        server_default=text("now()"),
    )
)
CashBalance.__table__.append_column(
    Column(
        "updated_at",
        DateTime(timezone=True),
        nullable=False,
        server_default=text("now()"),
    )
)

__all__ = ["CashBalance", "CashBox"]
