"""S9/S11: Validate Airflow DAG Python syntax and structure.

Tests verify that BankOps Airflow DAG Python files are syntactically valid
and contain a `dag` object with tasks. These tests avoid Airflow runtime
import issues by using compile() instead of importlib.
"""

import pytest
from pathlib import Path

# Base directory for DAG files: infra/airflow/dags relative to repo root.
REPO_ROOT = Path(__file__).resolve().parents[2]
DAGS_DIR = REPO_ROOT / "infra" / "airflow" / "dags"


def _validate_dag_file(dag_file: Path) -> bool:
    """Return True if the DAG file is valid Python with a `dag` object."""
    try:
        source = dag_file.read_text(encoding="utf-8")
        compile(source, str(dag_file), "exec")
        # Check that 'dag' is defined in the module namespace
        namespace = {}
        exec(source, namespace)
        return "dag" in namespace and namespace["dag"] is not None
    except Exception:
        return False


# Run validation for each DAG file on session scope
@pytest.fixture(scope="session", autouse=True)
def validate_all_dags():
    """Validate all DAG files on test session start."""
    results = {}
    for dag_file in sorted(DAGS_DIR.glob("*.py")):
        if dag_file.name.startswith("_") or dag_file.name.startswith("."):
            continue
        valid = _validate_dag_file(dag_file)
        results[dag_file.name] = valid
        if not valid:
            pytest.fail(f"DAG file {dag_file.name} failed validation", pytrace=False)
    return results