# Supplier Ingestion DAG (Phase M — S2)
#
# Workflow: ingest → validate → normalize → dedup → transform → version → schedule
#
# Dependencies:
#   - app.models.supplier (Supplier)
#   - app.models.etl (EtlConnection, EtlPipeline, EtlMappingVersion, EtlRun)
#   - pandas
#

from airflow import DAG
from datetime import datetime
from airflow.operators.python import PythonOperator


dag = DAG(
    dag_id="supplier_ingestion",
    start_date=datetime(2024, 1, 1),
    schedule="@daily",
    catchup=False,
    tags=["phase-m", "supplier", "etl"],
)

ingest_csv = PythonOperator(
    task_id="ingest_csv",
    python_callable=lambda: None,
)

validate_schema = PythonOperator(
    task_id="validate_schema",
    python_callable=lambda: None,
)

normalize_data = PythonOperator(
    task_id="normalize_data",
    python_callable=lambda: None,
)

dedup_data = PythonOperator(
    task_id="dedup_data",
    python_callable=lambda: None,
)

transform_features = PythonOperator(
    task_id="transform_features",
    python_callable=lambda: None,
)

version_dataset = PythonOperator(
    task_id="version_dataset",
    python_callable=lambda: None,
)

schedule_batch = PythonOperator(
    task_id="schedule_batch",
    python_callable=lambda: None,
)