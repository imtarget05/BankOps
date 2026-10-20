"""Airflow ingest tasks tests."""
import pytest


@pytest.mark.airflow
def test_airflow_ingest_tasks_import():
    """Verify airflow ingest tasks module can be imported."""
    # This is a placeholder test - actual DAG tests are in test_airflow_dags.py
    import infra.airflow.dags.inventory_ingestion as dag_module
    assert dag_module.dag is not None
