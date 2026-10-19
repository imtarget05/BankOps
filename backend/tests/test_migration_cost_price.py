"""Regression coverage for the fresh-database Alembic chain."""

import os
import subprocess
import sys
from pathlib import Path

import psycopg2


BACKEND_ROOT = Path(__file__).resolve().parents[1]
TEST_DATABASE_URL = "postgresql+psycopg2://bankops:bankops@localhost:15432/bankops"


def test_fresh_migration_chain_supports_lot_backfill_cost_price() -> None:
    """A clean database must reach head without querying a missing cost_price column."""
    with psycopg2.connect(TEST_DATABASE_URL.replace("+psycopg2", "")) as connection:
        connection.autocommit = True
        with connection.cursor() as cursor:
            cursor.execute("DROP SCHEMA public CASCADE")
            cursor.execute("CREATE SCHEMA public")

    result = subprocess.run(
        [sys.executable, "-m", "alembic", "upgrade", "head"],
        cwd=BACKEND_ROOT,
        env={**os.environ, "DATABASE_URL": TEST_DATABASE_URL},
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stdout + result.stderr
