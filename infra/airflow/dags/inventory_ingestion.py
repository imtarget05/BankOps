"""Inventory Ingestion DAG (Phase M — S2).

Chuỗi ingest thật (không có stub rỗng):

    read_source → parse_rows → validate_rows → load_staging
                → train_demand_model → promote_demand_model → detect_drift

* ``read_source``        – đọc file nguồn (mặc định ``backend/sample-data/inventory.json``).
* ``parse_rows``         – parse bằng ``app.services.etl_engine.parse_raw_source`` (hàm thật).
* ``validate_rows``      – kiểm tra trường bắt buộc + fingerprint SHA-256 (idempotency key).
* ``load_staging``       – ghi dòng vào bảng staging ``qlk_ingest_staging`` (idempotent).
* ``train_demand_model`` – gọi ``app.services.ml_training.run_full_pipeline`` (MLflow thật).
* ``promote_demand_model`` – gọi ``app.services.ml_registry.promote_model``, chỉ promote
  khi R² ≥ ngưỡng (0.7).
* ``detect_drift``       – gọi ``app.services.drift_detection.analyze_drift``, so sánh
  phân phối features cửa sổ tham chiếu vs hiện tại; output recommendation
  (no_action / scheduled_retraining / data_preprocessing / investigate).

Cấu hình qua biến môi trường (không hardcode path tuyệt đối):

===========================  ====================================================
``QLK_INGEST_INVENTORY_SOURCE``  file nguồn (mặc định ``backend/sample-data/inventory.json``)
``QLK_INGEST_SOURCE_DIR``        thư mục nguồn dùng chung
``QLK_INGEST_DATABASE_URL``      database đích cho bảng staging (mặc định ``DATABASE_URL``)
``QLK_INGEST_STAGING_TABLE``     tên bảng staging (mặc định ``qlk_ingest_staging``)
``MLFLOW_TRACKING_URI``          tracking store MLflow
``QLK_INGEST_ML_N_PERIODS``      số kỳ huấn luyện (mặc định 120)
``QLK_INGEST_DRIFT_REFERENCE_DAYS``    ngày lùi cho cửa sổ tham chiếu (mặc định 30)
``QLK_INGEST_DRIFT_REFERENCE_WINDOW``  kích thước cửa sổ tham chiếu (mặc định 23)
``QLK_INGEST_DRIFT_CURRENT_DAYS``      ngày lùi cho cửa sổ hiện tại (mặc định 7)
``QLK_INGEST_DRIFT_CURRENT_WINDOW``    kích thước cửa sổ hiện tại (mặc định 7)
===========================  ====================================================
"""

from __future__ import annotations

import sys
from datetime import datetime, timedelta
from pathlib import Path

# Airflow thêm DAGS_FOLDER vào sys.path, nhưng `airflow dags test --dagfile-path`
# và môi trường khác có thể không làm vậy → tự chèn để chắc chắn import được.
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
    promote_demand_model,
    read_source,
    train_demand_model,
    validate_rows,
    detect_drift,
)

DATASET = "inventory"

DEFAULT_ARGS = {
    "owner": "data-platform@quanlykho.local",
    "depends_on_past": False,
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
    "start_date": datetime(2024, 1, 1),
}

with DAG(
    dag_id="inventory_ingestion",
    description="Ingest catalog tồn kho vào bảng staging, huấn luyện + promote model nhu cầu (MLflow).",
    default_args=DEFAULT_ARGS,
    schedule="@daily",
    catchup=False,
    max_active_runs=1,
    tags=["phase-m", "inventory", "etl", "ml"],
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
    train = PythonOperator(
        task_id="train_demand_model",
        python_callable=train_demand_model,
    )
    promote = PythonOperator(
        task_id="promote_demand_model",
        python_callable=promote_demand_model,
    )
    detect = PythonOperator(
        task_id="detect_drift",
        python_callable=detect_drift,
    )

    read >> parse >> validate >> load >> train >> promote >> detect
