"""Thư viện dùng chung cho các DAG ingest của QuanLyKho.

Gói này nằm *trong* thư mục ``dags/`` để Airflow tự thêm thư mục đó vào
``sys.path``.  Điều đó bắt buộc vì Airflow serialize DAG và worker chạy ở
process khác: ``python_callable`` phải import được bằng đường dẫn tuyệt đối
kiểu ``qlk_ingest.tasks.read_source`` (không dùng lambda/partial closure).

Module này cũng chèn ``backend/`` vào ``sys.path`` để DAG gọi được hàm thật
của ứng dụng (``app.services.etl_engine``, ``app.services.ml_training``,
``app.services.ml_registry``) mà không cần cài package riêng.
"""

from __future__ import annotations

import sys
from pathlib import Path

DAGS_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = DAGS_DIR.parents[2]
BACKEND_DIR = REPO_ROOT / "backend"

for _candidate in (str(DAGS_DIR), str(BACKEND_DIR)):
    if Path(_candidate).is_dir() and _candidate not in sys.path:
        sys.path.insert(0, _candidate)

__all__ = ["BACKEND_DIR", "DAGS_DIR", "REPO_ROOT"]
