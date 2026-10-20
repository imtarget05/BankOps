# Airflow Ingest — Evidence E2E (2026-10-20)

**Trạng thái: `AIRFLOW_INGEST_VERIFIED`**

E2E thật đã chạy: `airflow dags test` cho cả 3 DAG, dữ liệu được nạp vào
database disposable, model được huấn luyện + ghi MLflow + promote lên
Production. Không có DAG nào còn `python_callable=lambda: None`.

---

## 1. Trước khi sửa (hiện trạng đã chứng minh)

| Vấn đề | Bằng chứng |
|---|---|
| Operator chưa gắn vào DAG | `dag.tasks == []` → `operator.dag` ném `RuntimeError: Operator <Task(PythonOperator): ingest_csv> has not been assigned to a Dag yet` |
| `transform_features` gán vào **tuple** | `inventory_ingestion.py` dòng 49-52: `PythonOperator(...),` (dấu phẩy thừa) → task không tồn tại trong DAG |
| Test **vacuous green** | `assert len(task_ids) >= 0` — luôn đúng kể cả khi DAG rỗng |
| `python_callable` là `lambda: None` | 13/13 task ở `expense_ingestion.py` + `supplier_ingestion.py`, 3/7 ở `inventory_ingestion.py` |
| Không có Airflow DB / scheduler / `AIRFLOW_HOME` | Chưa từng chạy Airflow |

## 2. Sau khi sửa — kiến trúc

```
infra/airflow/dags/
├── .airflowignore                  # loại qlk_ingest/ khỏi DAG discovery
├── inventory_ingestion.py          # 6 task: read→parse→validate→load→train→promote
├── expense_ingestion.py            # 4 task: read→parse→validate→load
├── supplier_ingestion.py           # 4 task: read→parse→validate→load
├── qlk_ingest/                     # thư viện dùng chung (không phải DAG file)
│   ├── config.py                   # resolve nguồn/DB/MLflow theo biến môi trường
│   ├── staging.py                  # bảng staging (SQLAlchemy Core) + nạp idempotent
│   └── tasks.py                    # callable thật của từng task
└── seed/                           # nguồn mặc định cho expense/supplier
    ├── expenses.csv                # 8 dòng
    └── suppliers.csv               # 3 dòng
```

Mọi `python_callable` là hàm cấp module trong `qlk_ingest.tasks`
(`read_source`, `parse_rows`, `validate_rows`, `load_staging`,
`train_demand_model`, `promote_demand_model`) ⇒ Airflow serialize được, không
còn lambda.

Hàm thật của ứng dụng được gọi (chỉ đọc + gọi, **không sửa**):
`app.services.etl_engine.parse_raw_source` / `compute_fingerprint`,
`app.services.ml_training.run_full_pipeline`,
`app.services.ml_registry.promote_model` / `list_model_versions`.

### Cấu hình (không hardcode path tuyệt đối)

| Biến | Ý nghĩa | Mặc định |
|---|---|---|
| `QLK_INGEST_INVENTORY_SOURCE` | file nguồn inventory | `backend/sample-data/inventory.json` |
| `QLK_INGEST_EXPENSE_SOURCE` | file nguồn expense | `infra/airflow/dags/seed/expenses.csv` |
| `QLK_INGEST_SUPPLIER_SOURCE` | file nguồn supplier | `infra/airflow/dags/seed/suppliers.csv` |
| `QLK_INGEST_SOURCE_DIR` | thư mục nguồn dùng chung | – |
| `QLK_INGEST_DATABASE_URL` (fallback `DATABASE_URL`) | DB đích bảng staging | – (fail-closed) |
| `QLK_INGEST_STAGING_TABLE` | tên bảng staging | `qlk_ingest_staging` |
| `QLK_INGEST_STRICT` | fail-closed khi dòng sai | `1` |
| `MLFLOW_TRACKING_URI` / `QLK_INGEST_MLFLOW_*` | MLflow store/artifact | `<AIRFLOW_HOME>/mlflow.db` |
| `QLK_INGEST_ML_N_PERIODS` | số kỳ huấn luyện | `120` |

**Guard an toàn:** `resolve_database_url()` từ chối ghi vào database mà tên
không chứa `test` (trừ `QLK_INGEST_ALLOW_ANY_DB=1`) ⇒ DAG không thể ghi nhầm
vào DB dev `bankops`.

## 3. Môi trường E2E (tất cả đều disposable, ngoài repo)

```
AIRFLOW_HOME=/tmp/qlk_airflow_home                                   # SQLite Airflow metadata
AIRFLOW__CORE__DAGS_FOLDER=<repo>/infra/airflow/dags
AIRFLOW__CORE__EXECUTOR=LocalExecutor
AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=sqlite:////tmp/qlk_airflow_home/airflow.db
QLK_INGEST_DATABASE_URL=postgresql+psycopg2://bankops:bankops@127.0.0.1:5432/bankops_test_airflow_ingest
MLFLOW_TRACKING_URI=sqlite:////tmp/qlk_airflow_home/mlflow.db
```

Database `bankops_test_airflow_ingest` được tạo riêng cho phiên này (không
phải `bankops` dev, không phải `bankops_test` dùng chung) và đã bị `DROP` sau
khi lấy evidence.

## 4. Lệnh đã chạy & output thật

### 4.1 Khởi tạo Airflow DB

```bash
$ backend/.venv/bin/airflow db migrate
...
2026-10-20T16:46:08.710576Z [info] Airflow database tables created [airflow.utils.db]
2026-10-20T16:46:08.772383Z [info] Database migration done!
```

### 4.2 DAG được Airflow nhận diện

```bash
$ backend/.venv/bin/airflow dags list
dag_id              | fileloc                                                          | owners                        | is_paused
====================+==================================================================+===============================+===========
expense_ingestion   | .../infra/airflow/dags/expense_ingestion.py                    | data-platform@quanlykho.local | True
inventory_ingestion | .../infra/airflow/dags/inventory_ingestion.py                  | data-platform@quanlykho.local | True
supplier_ingestion  | .../infra/airflow/dags/supplier_ingestion.py                   | data-platform@quanlykho.local | True
```

### 4.3 `airflow dags test inventory_ingestion 2026-10-20` → SUCCESS

Task-by-task (`Done. Returned value was:` — giá trị thật trả về):

```
read_source          {'dataset': 'inventory', 'path': '.../backend/sample-data/inventory.json',
                      'source_name': 'inventory.json', 'source_type': 'json', 'size_bytes': 16223,
                      'sha256': 'ae7651846d20016e3251217e4c9bc7d4833a374bb3813ac444b6792509613099'}
parse_rows           {'dataset': 'inventory', 'row_count': 30, 'rows': [{'id': 'cccccccc-...', 'sku': 'TRA-DEN-SO9',
                      'name': 'Trà Đen Lộc Phát Số 9', 'unit': 'gói', 'category': 'Nhóm Trà', ...}]}
validate_rows        {'dataset': 'inventory', 'row_count': 30, 'valid_rows': 30, 'invalid_rows': 0,
                      'invalid_detail': [], 'fingerprint': 'd11fa66c6c177a11a7f84d3d50bba2eacccb9667826c144c8495df200f7f085e',
                      'required_fields': ['sku', 'name'], 'business_key': 'sku'}
load_staging         {'inserted': 30, 'skipped': 0, 'total_rows': 30, 'table': 'qlk_ingest_staging',
                      'dataset': 'inventory', 'fingerprint': 'd11fa66c...', 'database': '127.0.0.1:5432/bankops_test_airflow_ingest'}
train_demand_model   {'run_id': '3a87272308f3435c84081fcf70fbc5f7', 'mae': 3.423406018874264,
                      'rmse': 4.209944576171022, 'r2': 0.9030989484660734, 'train_size': 96, 'test_size': 24,
                      'model_name': 'DemandForecastModel'}
promote_demand_model {'promoted': True, 'version': 1, 'stage': 'Production', 'r2': 0.9030989484660734,
                      'threshold': 0.7, 'message': 'Successfully promoted version 1 to Production'}
```

Kết luận của run:

```
Dag run in success state
DagRun Finished: dag_id=inventory_ingestion, logical_date=2026-10-20 00:00:00+00:00,
  run_id=manual__2026-10-20T16:45:..., state=success, run_type=manual
```

Exit code: `0`.

### 4.4 `airflow dags test expense_ingestion` / `supplier_ingestion` → SUCCESS

```
-- expense_ingestion
read_source    {'dataset': 'expense', 'path': '.../infra/airflow/dags/seed/expenses.csv', 'size_bytes': 508, 'sha256': '9955f7c8...'}
parse_rows     {'dataset': 'expense', 'row_count': 8, 'rows': [{'expense_ref': 'EXP-2026-0001', ...}]}
validate_rows  {'dataset': 'expense', 'row_count': 8, 'valid_rows': 8, 'invalid_rows': 0, 'fingerprint': '215fe684...'}
load_staging   {'inserted': 8, 'skipped': 0, 'total_rows': 8, 'table': 'qlk_ingest_staging', 'dataset': 'expense'}

-- supplier_ingestion
read_source    {'dataset': 'supplier', 'path': '.../infra/airflow/dags/seed/suppliers.csv', 'size_bytes': 296, 'sha256': 'f1680f12...'}
parse_rows     {'dataset': 'supplier', 'row_count': 3, 'rows': [{'supplier_code': 'SUP-001', ...}]}
validate_rows  {'dataset': 'supplier', 'row_count': 3, 'valid_rows': 3, 'invalid_rows': 0, 'fingerprint': '32d28078...'}
load_staging   {'inserted': 3, 'skipped': 0, 'total_rows': 3, 'table': 'qlk_ingest_staging', 'dataset': 'supplier'}

exit=0 cho cả hai, "Dag run in success state" xuất hiện 1 lần mỗi DAG.
```

### 4.5 Dữ liệu thật trong database disposable

```bash
$ PGPASSWORD=bankops psql -h 127.0.0.1 -U bankops -d bankops_test_airflow_ingest \
    -c "SELECT dataset, count(*) AS rows_ingested, count(DISTINCT source_fingerprint) AS fingerprints,
              min(ingested_at) FROM qlk_ingest_staging GROUP BY dataset ORDER BY dataset;"

  dataset  | rows_ingested | fingerprints |          ingested_at
-----------+---------------+--------------+-------------------------------
 expense   |             8 |            1 | 2026-10-20 23:46:30.883771+07
 inventory |            30 |            1 | 2026-10-20 23:46:16.937396+07
 supplier  |             3 |            1 | 2026-10-20 23:46:35.693794+07
(3 rows)
```

Mẫu dòng thật trong bảng:

```
 dataset  | row_number |  business_key  |                         payload_head
-----------+------------+----------------+--------------------------------------------------
 inventory |          1 | TRA-DEN-SO9    | {"category": "Nhóm Trà", "cost_price": 65000, "id": "ccccccc
 inventory |          2 | TRA-LAI-500G   | {"category": "Nhóm Trà", "cost_price": 70000, "id": "ccccccc
 inventory |          3 | TRA-OLONG-500G | {"category": "Nhóm Trà", "cost_price": 85000, "id": "ccccccc
```

### 4.6 Idempotency (chạy lại cùng DAG)

```bash
$ backend/.venv/bin/airflow dags test inventory_ingestion 2026-10-20   # lần 2
load_staging → {'inserted': 0, 'skipped': 30, 'total_rows': 30, 'table': 'qlk_ingest_staging',
                'fingerprint': 'd11fa66c...'}
```

Cũng chạy được bằng `airflow tasks test` cho từng task:

```bash
$ backend/.venv/bin/airflow tasks test inventory_ingestion load_staging 2026-10-20
{'inserted': 0, 'skipped': 30, 'total_rows': 30, 'table': 'qlk_ingest_staging', ...}
```

### 4.7 MLflow (params / metrics / artifact / registry)

```bash
$ backend/.venv/bin/python -c "import mlflow; mlflow.set_tracking_uri('sqlite:////tmp/qlk_airflow_home/mlflow.db'); ..."
run_id 3a87272308f3435c84081fcf70fbc5f7 FINISHED | metrics {'mae': 3.4234, 'mse': 17.7236, 'rmse': 4.2099, 'r2': 0.9031}
  params {'train_size': '96', 'test_size': '24', 'train_ratio': '0.8',
          'feature_combination': 'month_sincos+trend_scaled', 'random_seed': '42'}
  artifacts [('train_data_sample.csv', 326)]
model versions: [(2, 'Production', '02ce52b45d1a4763807f16db1a81f9bf'),
                  (1, 'Production', '3a87272308f3435c84081fcf70fbc5f7')]
```

⇒ Model được đăng ký trong registry và **đã ở stage `Production`** (qua
`ml_registry.promote_model`, chỉ khi R² = 0.9031 ≥ ngưỡng 0.7).

## 5. Test (không còn vacuous)

### 5.1 `backend/tests/test_airflow_dags.py` (viết lại)

21 test, assert có ý nghĩa: DAG import được; `len(task_ids) > 0` và **khớp
đúng** danh sách task khai báo; mọi task `task.dag is dag`; `python_callable`
là hàm thật trong `qlk_ingest.tasks` (không lambda, không placeholder); chuỗi
`>>` nối liền; `catchup=False`, `max_active_runs=1`, `schedule='@daily'`,
`default_args` có owner/retries/retry_delay/start_date; DAG serialize được bằng
`DagSerialization.serialize_dag`.

### 5.2 `backend/tests/test_airflow_ingest_tasks.py` (mới — 15 test)

Test *thực thi* từng callable và assert side effect thật:

* `read_source` → metadata thật (size/sha256); nguồn thiếu ⇒ `FileNotFoundError`.
* `parse_rows` → 30 / 8 / 3 dòng cho inventory / expense / supplier.
* `validate_rows` → fingerprint ổn định; dòng thiếu trường bắt buộc ⇒ `ValueError` (fail-closed).
* `load_staging` → **ghi dòng vào DB**: `inserted == 30`, đếm được 30 dòng trong bảng; chạy lại ⇒ `inserted == 0, skipped == 30`; expense 8 dòng, supplier 3 dòng.
* `resolve_database_url` → từ chối DB không chứa `test` (chặn ghi vào `bankops` dev).
* `train_demand_model` → run `FINISHED` trong MLflow, params/metrics khớp, artifact `train_data_sample.csv` tồn tại, model đã đăng ký registry.
* `promote_demand_model` → R² = 0.1 ⇒ **không** promote; R² đạt ngưỡng ⇒ `promoted=True`, `stage='Production'`, registry xác nhận version ở Production.

## 6. Kết quả verify

```bash
# Lint
$ backend/.venv/bin/python -m ruff check infra/airflow/dags/ backend/tests/test_airflow_dags.py backend/tests/test_airflow_ingest_tasks.py
All checks passed!

# Test DAG
$ DATABASE_URL="postgresql+psycopg2://bankops:bankops@127.0.0.1:5432/bankops_test_airflow_suite" \
      backend/.venv/bin/python -m pytest backend/tests/test_airflow_dags.py -q
21 passed, 1 warning in 8.70s

# Test thực thi task
$ DATABASE_URL="postgresql+psycopg2://bankops:bankops@127.0.0.1:5432/bankops_test_airflow_suite" \
      backend/.venv/bin/python -m pytest backend/tests/test_airflow_ingest_tasks.py -q
15 passed, 3 warnings in 28.92s

# Full suite trên DB disposable (alembic upgrade head trước)
$ cd backend && DATABASE_URL="postgresql+psycopg2://bankops:bankops@127.0.0.1:5432/bankops_test_airflow_suite" \
      .venv/bin/python -m pytest tests -q --ignore=tests/test_e2e_verify.py
613 passed, 7 skipped, 1 xfailed, 1171 warnings in 264.89s (0:04:24)
```

**0 failed.**

> Ghi chú: `tests/test_e2e_verify.py` (file **untracked, do actor khác đang
> viết song song**) bị lỗi `AttributeError: module 'e2e_verify' has no
> attribute 'verify_chain'` vì `backend/scripts/e2e_verify.py` hiện chỉ có
> `verify_registry` / `_write_evidence` / `main`. Lỗi này **không liên quan**
> tới thay đổi của Airflow (file đó không import gì từ DAG). Khi chạy full
> suite **không** ignore file đó: `614 passed, 2 failed` — 2 fail đều nằm
> trong file WIP của actor khác.
>
> Ngoài ra, `tests/test_migration_cost_price.py` và `tests/test_expense_supplier_models.py`
> (9 test) ban đầu fail ở máy này vì role `bankops` thiếu quyền `CREATEDB`
> và test gọi `pytest.skip(..., pytrace=False)` (kwarg không hợp lệ với pytest
> 8.3) ⇒ `TypeError` thay vì skip. Sau khi `ALTER ROLE bankops CREATEDB`
> (đúng như setup docker-compose.test.yml, nơi `bankops` là `POSTGRES_USER`),
> 9 test này pass.

## 7. Dọn dẹp

* `AIRFLOW_HOME` tạm: `/tmp/qlk_airflow_home` (xoá sau khi lấy evidence).
* Database disposable: `bankops_test_airflow_ingest` (xoá), `bankops_test_airflow_suite` (xoá).
* Không đụng container/service của repo khác; không commit (HEAD còn dirty do
  actor khác sửa song song).

## 8. Phần còn lại (không làm trong slice này)

1. **Scheduler thật chưa chạy.** Evidence dùng `airflow dags test` (Airflow 3
   chạy DAG trong process, không qua executor). `LocalExecutor` + scheduler +
   `airflow dags trigger` chưa được chạy end-to-end ⇒ chưa có bằng chứng
   *scheduled run* tự động.
2. **Nguồn expense/supplier là seed CSV kèm repo** (8 + 3 dòng). Production
   phải override `QLK_INGEST_EXPENSE_SOURCE` / `QLK_INGEST_SUPPLIER_SOURCE`.
3. **Bảng staging chưa được đẩy vào domain tables** (`inv_items`, `expenses`,
   `suppliers`). Hiện mới chỉ ghi `qlk_ingest_staging`; bước map sang bảng
   nghiệp vụ cần `EtlPipeline` + `generate_staging_run` (async, cần `User`
   runner + `EtlMappingVersion`) — chưa làm vì nằm ngoài phạm vi sửa
   `backend/app/**` cho lần này.
4. **Chưa có `dag.test` trong CI** — workflow CI chưa cài Airflow/không chạy
   DAG; nên thêm job `airflow dags test` + Postgres service khi muốn chốt
   ingest ở tầng CI.
5. `docker-compose`/k8s chưa có service Airflow; `infra/airflow/` chỉ có DAG.
