"""Align the migrated schema with the ORM schema (Alembic becomes the source of truth).

Revision ID: 026_schema_alignment
Revises: 025_expense_and_supplier
Create Date: 2026-10-20

Context
-------
Until now Alembic was *not* the source of truth for the application schema:
``app/database.py::init_db()`` created the schema with
``Base.metadata.create_all`` plus a list of ad-hoc ``ALTER TABLE`` statements.
The two paths therefore drifted apart and a database built by
``alembic upgrade head`` was **not** the database the application expects.

This migration closes that gap for everything that is still different on a
clean database. It is deliberately *additive*:

* columns the ORM expects but the chain never created
  (``inv_items.selling_price``, ``inv_items.min_stock``) are added;
* indexes/unique constraints the ORM expects are created;
* the two foreign keys of ``inv_stocktakes`` are recreated with the
  ``ON DELETE`` behaviour the ORM declares (they were created without one);
* a few ``TEXT`` columns are narrowed to the ``VARCHAR(n)`` the ORM declares
  (guarded so a value that would be truncated aborts the migration instead of
  being silently cut);
* ``expenses.expense_code`` / ``suppliers.code`` swap their *named unique
  constraint* for the *unique index* the ORM declares — the uniqueness
  guarantee is unchanged, only the object type matches the metadata now.

Nothing is dropped: the tables, columns and integrity indexes that Alembic
previously wanted to remove (``cash_boxes.branch_id``,
``cash_balances.created_at/updated_at``, ``uq_lot_balance_record``,
``uq_open_stocktake_shift``, the ETL/IAM/job indexes) are part of the
application schema and are now declared in the ORM metadata as well, so
autogenerate stops proposing to drop them.
"""

import sqlalchemy as sa

from alembic import op

revision = "026_schema_alignment"
down_revision = "025_expense_and_supplier"
branch_labels = None
depends_on = None


def _has_column(table: str, column: str) -> bool:
    inspector = sa.inspect(op.get_bind())
    if table not in inspector.get_table_names():
        return False
    return column in {c["name"] for c in inspector.get_columns(table)}


def _has_index(table: str, index: str) -> bool:
    inspector = sa.inspect(op.get_bind())
    if table not in inspector.get_table_names():
        return False
    return index in {i["name"] for i in inspector.get_indexes(table)}


def _has_constraint(table: str, constraint: str) -> bool:
    inspector = sa.inspect(op.get_bind())
    if table not in inspector.get_table_names():
        return False
    names = {c["name"] for c in inspector.get_unique_constraints(table)}
    names |= {c["name"] for c in inspector.get_foreign_keys(table)}
    return constraint in names


def _alter_text_to_varchar(table: str, column: str, length: int) -> None:
    """Narrow a TEXT column to VARCHAR(length), refusing to truncate data."""
    op.execute(
        sa.text(
            f"""
            DO $$
            BEGIN
                IF EXISTS (
                    SELECT 1 FROM {table}
                    WHERE {column} IS NOT NULL AND length({column}) > {length}
                ) THEN
                    RAISE EXCEPTION
                        '{table}.{column} contains values longer than {length} '
                        'characters; widen the column in the ORM model before '
                        'running this migration';
                END IF;
            END $$
            """
        )
    )
    op.execute(
        sa.text(
            f"ALTER TABLE {table} ALTER COLUMN {column} "
            f"TYPE VARCHAR({length}) USING {column}::VARCHAR({length})"
        )
    )


def upgrade() -> None:
    # --- inv_items: columns the ORM declares (create_all had them via ALTER) --
    if not _has_column("inv_items", "selling_price"):
        op.add_column(
            "inv_items",
            sa.Column("selling_price", sa.Numeric(precision=15, scale=2), nullable=True),
        )
    if not _has_column("inv_items", "min_stock"):
        op.add_column(
            "inv_items",
            sa.Column("min_stock", sa.Numeric(precision=12, scale=2), nullable=True),
        )

    # --- approval_decisions: one decision per subject ----------------------
    if not _has_constraint("approval_decisions", "uq_approval_final_per_subject"):
        op.create_unique_constraint(
            "uq_approval_final_per_subject",
            "approval_decisions",
            ["subject_type", "subject_id"],
        )

    # --- inv_movements: one movement per request line and location ---------
    if not _has_constraint("inv_movements", "uq_movement_request_line_location"):
        op.create_unique_constraint(
            "uq_movement_request_line_location",
            "inv_movements",
            ["request_id", "line_id", "location_id"],
        )

    # --- expenses / suppliers: unique constraint -> unique index ------------
    # The ORM declares ``unique=True, index=True`` which materialises as a
    # unique *index*; the chain created a named unique *constraint*. The
    # uniqueness guarantee stays, only the object type matches the metadata.
    if _has_constraint("expenses", "uq_expenses_expense_code"):
        op.drop_constraint("uq_expenses_expense_code", "expenses", type_="unique")
    if not _has_index("expenses", "ix_expenses_expense_code"):
        op.create_index("ix_expenses_expense_code", "expenses", ["expense_code"], unique=True)

    if _has_constraint("suppliers", "uq_suppliers_code"):
        op.drop_constraint("uq_suppliers_code", "suppliers", type_="unique")
    if not _has_index("suppliers", "ix_suppliers_code"):
        op.create_index("ix_suppliers_code", "suppliers", ["code"], unique=True)

    # --- inv_asset_logs: index on serial ------------------------------------
    if not _has_index("inv_asset_logs", "ix_inv_asset_logs_serial"):
        op.create_index("ix_inv_asset_logs_serial", "inv_asset_logs", ["serial"])

    # --- inv_lot_movements: indexes the ORM declares -----------------------
    if not _has_index("inv_lot_movements", "ix_inv_lot_movements_lot_no"):
        op.create_index("ix_inv_lot_movements_lot_no", "inv_lot_movements", ["lot_no"])
    if not _has_index("inv_lot_movements", "ix_inv_lot_movements_expiry_date"):
        op.create_index(
            "ix_inv_lot_movements_expiry_date", "inv_lot_movements", ["expiry_date"]
        )

    # --- inv_stocktakes: recreate FKs with the declared ON DELETE ----------
    op.drop_constraint(
        "fk_inv_stocktakes_location_id_inv_locations", "inv_stocktakes", type_="foreignkey"
    )
    op.create_foreign_key(
        "fk_inv_stocktakes_location_id_inv_locations",
        "inv_stocktakes",
        "inv_locations",
        ["location_id"],
        ["id"],
        ondelete="RESTRICT",
    )
    op.drop_constraint(
        "fk_inv_stocktakes_adjustment_request_id_inv_requests",
        "inv_stocktakes",
        type_="foreignkey",
    )
    op.create_foreign_key(
        "fk_inv_stocktakes_adjustment_request_id_inv_requests",
        "inv_stocktakes",
        "inv_requests",
        ["adjustment_request_id"],
        ["id"],
        ondelete="SET NULL",
    )

    # --- column types: TEXT -> VARCHAR(n) as declared by the ORM -----------
    _alter_text_to_varchar("cash_requests", "return_reason", 1024)
    _alter_text_to_varchar("inv_requests", "return_reason", 1024)
    _alter_text_to_varchar("inv_asset_logs", "notes", 1024)
    _alter_text_to_varchar("inv_stocktake_lines", "reason", 512)
    _alter_text_to_varchar("inv_stocktakes", "note", 512)


def downgrade() -> None:
    # --- column types: back to TEXT ----------------------------------------
    for table, column in (
        ("cash_requests", "return_reason"),
        ("inv_requests", "return_reason"),
        ("inv_asset_logs", "notes"),
        ("inv_stocktakes", "note"),
    ):
        op.execute(
            sa.text(
                f"ALTER TABLE {table} ALTER COLUMN {column} TYPE TEXT "
                f"USING {column}::TEXT"
            )
        )
    op.execute(
        sa.text(
            "ALTER TABLE inv_stocktake_lines ALTER COLUMN reason "
            "TYPE VARCHAR(256) USING reason::VARCHAR(256)"
        )
    )

    # --- inv_stocktakes: FKs back to their original definition -------------
    op.drop_constraint(
        "fk_inv_stocktakes_adjustment_request_id_inv_requests",
        "inv_stocktakes",
        type_="foreignkey",
    )
    op.create_foreign_key(
        "fk_inv_stocktakes_adjustment_request_id_inv_requests",
        "inv_stocktakes",
        "inv_requests",
        ["adjustment_request_id"],
        ["id"],
    )
    op.drop_constraint(
        "fk_inv_stocktakes_location_id_inv_locations", "inv_stocktakes", type_="foreignkey"
    )
    op.create_foreign_key(
        "fk_inv_stocktakes_location_id_inv_locations",
        "inv_stocktakes",
        "inv_locations",
        ["location_id"],
        ["id"],
    )

    # --- indexes / constraints created by this migration -------------------
    if _has_index("inv_lot_movements", "ix_inv_lot_movements_expiry_date"):
        op.drop_index("ix_inv_lot_movements_expiry_date", table_name="inv_lot_movements")
    if _has_index("inv_lot_movements", "ix_inv_lot_movements_lot_no"):
        op.drop_index("ix_inv_lot_movements_lot_no", table_name="inv_lot_movements")
    if _has_index("inv_asset_logs", "ix_inv_asset_logs_serial"):
        op.drop_index("ix_inv_asset_logs_serial", table_name="inv_asset_logs")

    if _has_index("suppliers", "ix_suppliers_code"):
        op.drop_index("ix_suppliers_code", table_name="suppliers")
    if not _has_constraint("suppliers", "uq_suppliers_code"):
        op.create_unique_constraint("uq_suppliers_code", "suppliers", ["code"])

    if _has_index("expenses", "ix_expenses_expense_code"):
        op.drop_index("ix_expenses_expense_code", table_name="expenses")
    if not _has_constraint("expenses", "uq_expenses_expense_code"):
        op.create_unique_constraint("uq_expenses_expense_code", "expenses", ["expense_code"])

    if _has_constraint("inv_movements", "uq_movement_request_line_location"):
        op.drop_constraint("uq_movement_request_line_location", "inv_movements", type_="unique")
    if _has_constraint("approval_decisions", "uq_approval_final_per_subject"):
        op.drop_constraint(
            "uq_approval_final_per_subject", "approval_decisions", type_="unique"
        )

    if _has_column("inv_items", "min_stock"):
        op.drop_column("inv_items", "min_stock")
    if _has_column("inv_items", "selling_price"):
        op.drop_column("inv_items", "selling_price")
