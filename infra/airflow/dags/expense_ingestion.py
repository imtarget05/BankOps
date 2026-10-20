"""Expense Ingestion DAG (Phase M — S2).

Chuỗi ingest thật:

    read_source → parse_rows → validate_rows → load_staging

Mọi task gọi hàm thật trong ``qlk_ingest.tasks`` (parse bằng
``app.services.etl_engine``, ghi bằng SQLAlchemy).  Nguồn mặc định là file
seed kèm trong repo (``infra/airflow/dags/seed/expenses.csv``) — production phải
override bằng ``QLK_INGEST_EXPENSE_SOURCE`` trỏ tới file chi phí thật.

Biến môi trường: ``QLK_INGEST_EXPENSE_SOURCE``, ``QLK_INGEST_SOURCE_DIR``,
``QLK_INGEST_DATABASE_URL`` (hoặc ``DATABASE_URL``), ``QLK_INGEST_STAGING_TABLE``.
"""

from __future__ import annotations

import sys
from datetime import datetime, timedelta
from pathlib import Path

_DAGS_DIR = Path(__file__).resolve().parent
if str(_DAGS_DIR) not in sys.path:
    sys.path.insert(0, str(_DAGS_DIR))

from airflow import DAG  # noqa: E402
try:  # Airflow 3: provider chuẩn; fallback cho bản cài không kèm provider.
    from airflow.providers.standard.operators.python import PythonOperator  # noqa: E402
except ImportError:  # pragma: no cover - fallback Airflow 2
    from airflow.operators.python import PythonOperator  # noqa: E402

from qlk_ingest.tasks import (  # noqa: E402
    load_staging,
    parse_rows,
    read_source,
    validate_rows,
)

DATASET = "expense"

DEFAULT_ARGS = {
    "owner": "data-platform@quanlykho.local",
    "depends_on_past": False,
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
    "start_date": datetime(2024, 1, 1),
}

with DAG(
    dag_id="expense_ingestion",
    description="Ingest chi phí (expense) vào bảng staging của pipeline orchestration.",
    default_args=DEFAULT_ARGS,
    schedule="@daily",
    catchup=False,
    max_active_runs=1,
    tags=["phase-m", "expense", "etl"],
    doc_md=__doc__,
) as dag:
    read = PythonOperator(
        task_id="read_source",
        python_callable=read_source,
        op_kwargs={"dataset": DATASET},
    )
    parse = PythonOperator(
        task_id="parse_rows",
        python_callable=parse_rows,
        op_kwargs={"dataset": DATASET},
    )
    validate = PythonOperator(
        task_id="validate_rows",
        python_callable=validate_rows,
        op_kwargs={"dataset": DATASET},
    )
    load = PythonOperator(
        task_id="load_staging",
        python_callable=load_staging,
        op_kwargs={"dataset": DATASET},
    )

    read >> parse >> validate >> load
