"""S9/S11: Validate Airflow DAG Python syntax and structure.

Tests verify that BankOps Airflow DAG Python files are syntactically valid
and contain a `dag` assignment. These tests use ast.parse() to avoid
Airflow runtime import issues.
"""

import ast
import pytest
from pathlib import Path

# Base directory for DAG files: infra/airflow/dags relative to repo root.
REPO_ROOT = Path(__file__).resolve().parents[2]
DAGS_DIR = REPO_ROOT / "infra" / "airflow" / "dags"


def _has_dag_assignment(dag_file: Path) -> bool:
    """Return True if the DAG file has a `dag = ...` assignment."""
    try:
        source = dag_file.read_text(encoding="utf-8")
        tree = ast.parse(source)
        # Look for: dag = DAG(...) or dag = ... assignments
        for node in ast.walk(tree):
            if isinstance(node, ast.Assign):
                for target in node.targets:
                    if isinstance(target, ast.Name) and target.id == "dag":
                        return True
        return False
    except SyntaxError:
        return False


# One test per DAG file
for dag_file in sorted(DAGS_DIR.glob("*.py")):
    if dag_file.name.startswith("_") or dag_file.name.startswith("."):
        continue
    name = dag_file.stem
    exec(
        f"def test_{name}():\n"
        "    \"\"\"Validate {dag_file.name} has `dag` assignment.\"\"\"\n"
        "    valid = _has_dag_assignment(dag_file)\n"
        "    assert valid, f\"DAG file {dag_file.name} missing `dag` assignment\"\n",
    )
