# Airflow Ingest — Evidence E2E (2026-10-20, cập nhật CI 2026-10-21)

**Trạng thái: `AIRFLOW_INGEST_VERIFIED`**

> Phạm vi claim (2026-10-21, sau khi sửa CI): claim này khẳng định **chuỗi
> ingest thật sự chạy** (read → parse → validate → load staging → train ML →
> promote) với **Airflow 3.3.2**. Bằng chứng runtime có ở **local** (2026-10-20
> và tái lập lại 2026-10-21 trên worktree branch) **và** ở **CI** — workflow
> `s11-e2e-cloud-ci.yml` nay chạy `airflow dags test` thật, đã **kiểm chứng từng
> lệnh** trên máy (xem §6). Lần chạy GitHub Actions đầu tiên của branch
> `recovery/g2-20261020` **chưa diễn ra** (branch chưa push) ⇒ phần bằng chứng
> CI hiện là *"bước CI đã dựng và đã kiểm chứng cục bộ"*, chưa phải *"artifact
> CI đã sinh"*. Chi tiết và phần **chưa** verify: bảng ở §7.
>
> Airflow **2.10.4** (version branch từng pin) **không** chạy được chuỗi
> ingest: nó yêu cầu `sqlalchemy<2.0` trong khi backend yêu cầu
> `sqlalchemy>=2.0.35,<2.1` (ORM dùng `Mapped[]`) ⇒ hai môi trường **không thể
> chung venv**. Vì vậy CI dùng **Airflow 3.3.2** để chạy DAG thật, và giữ
> **Airflow 2.10.4** làm *cổng tương thích* cho test cấu trúc DAG. Lý do chi
> tiết: §5.

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
4. ~~**Chưa có `dag.test` trong CI**~~ — **ĐÃ ĐÓNG (2026-10-21)**: workflow
   `s11-e2e-cloud-ci.yml` nay chạy `airflow dags test` thật cho cả 3 DAG với
   Postgres service của CI. Xem §9.
5. `docker-compose`/k8s chưa có service Airflow; `infra/airflow/` chỉ có DAG.
6. **Lần chạy GitHub Actions đầu tiên của branch `recovery/g2-20261020` chưa
   diễn ra** (branch chưa push) ⇒ artifact CI (`dag-run.json`, log từng DAG)
   chưa tồn tại. Bước CI đã dựng và đã kiểm chứng từng lệnh cục bộ (§10),
   nhưng chưa có *artifact CI* ⇒ phần đó vẫn là **NOT VERIFIED (CI)**.

---

## 9. CI reproducibility (2026-10-21) — `.github/workflows/s11-e2e-cloud-ci.yml`

### 9.1. Ba lỗi CI đã sửa (G2 verifier chỉ ra)

| # | Lỗi | Nguyên nhân | Sửa ở đâu |
|---|---|---|---|
| 1 | `poetry install` nằm **sau** step chạy test | `poetry run python -m pytest` chạy trong venv **chưa có** dependency | `s11-e2e-cloud-ci.yml:69` — "Install backend dependencies (Poetry venv)" chuyển lên **ngay sau** "Install Poetry", trước mọi step test |
| 2 | Workflow gọi `tests/test_e2e_verify.py` — **file không tồn tại trên branch** | file này chỉ có trên `main` (và bản trên `main` gọi `e2e_verify.verify_chain()` — hàm **không tồn tại** trong `backend/scripts/e2e_verify.py` của branch ⇒ mang sang là test đỏ) | đã **gỡ** reference khỏi step "Drift Detection Check" và khỏi `on.push.paths`; **không** mang file từ `main` sang vì chưa ổn định (xem ghi chú bên dưới) |
| 3 | `backend/tests/test_airflow_dags.py` fail 6/21 với Airflow 2.10.4, hoặc **bị skip** (Airflow cài ở *system python* còn pytest chạy trong venv Poetry) ⇒ CI xanh **vacuous** | `dag.schedule` (chỉ có ở Airflow 3.x) và `DagSerialization` (chỉ có ở 3.x; 2.10.4 tên là `SerializedDAG`) | `backend/tests/test_airflow_dags.py` viết lại: đọc `schedule`/`schedule_interval` theo version, dò class serializer theo tên, và **không còn `importorskip` im lặng** |

### 9.2. Ba lỗi CI **phát hiện thêm** khi sửa (không nằm trong báo cáo G2)

| Lỗi | Ảnh hưởng | Sửa |
|---|---|---|
| Step "E2E Verification Summary" đọc `$RUNNER_TEMP/s11-evidence/e2e-chain.json` — **file này không bao giờ được tạo** (`scripts/e2e_verify.py` ghi `e2e-registry.json`) | `cat` fail ⇒ **step đỏ** ⇒ workflow đỏ | thêm step "MLflow registry gate (fail-closed)" chạy `scripts/e2e_verify.py` với `E2E_EVIDENCE_PATH=…/e2e-registry.json`; summary đọc file này |
| Step "Promote model to Production" chạy `poetry run python promote_model.py` với `working-directory: backend`, nhưng file nằm ở **gốc repo** | `No such file` ⇒ **step đỏ** | chạy `$(poetry env info --path)/bin/python "$GITHUB_WORKSPACE/promote_model.py"` với cwd = thư mục MLflow store của CI (`promote_model.py` dùng tracking URI tương đối `./mlflow.db`) |
| Step "FastAPI Serving Smoke Test" chạy `poetry run python scripts/smoke_test.py` — file nằm ở **gốc repo** (`scripts/smoke_test.py`), không phải `backend/scripts/` | `No such file` ⇒ **step đỏ** | sửa thành `"$GITHUB_WORKSPACE/scripts/smoke_test.py"` + `PYTHONPATH=${{ github.workspace }}/backend` (script import `app.*`) + trỏ `MLFLOW_TRACKING_URI` vào store của CI |

### 9.3. Vì sao Airflow phải nằm ở môi trường riêng (và vì sao pin 2.10.4 không dùng được cho DAG thật)

| Yêu cầu | Airflow 2.10.4 | Airflow 3.3.2 | Backend |
|---|---|---|---|
| SQLAlchemy | `>=1.4.36,<2.0` | `>=2.0.50` | `>=2.0.35,<2.1` (ORM `Mapped[]`) |
| FastAPI | (không yêu cầu) | `>=0.129` | `>=0.115,<0.116` |

* **Airflow 2.10.4 + backend ⇒ không thể chung venv.** Cài Airflow 2.10.4 vào venv
  của backend sẽ kéo `sqlalchemy` xuống **1.4.54**, vi phạm
  `sqlalchemy>=2.0.35,<2.1` ⇒ app code (`app.db.base` dùng `Mapped[]`) **không
  import được**. Ngược lại, để Airflow 2.10.4 chạy với SQLAlchemy 2.0.55 thì
  **Airflow tự hỏng** (`sqlalchemy.orm.exc.MappedAnnotationError` khi dựng model
  `TaskInstance`). Cả hai hướng đều đã **kiểm chứng thực tế** trên máy.
* ⇒ **Airflow chạy ở venv riêng**, dựng từ **đúng bộ dependency đã khoá** của
  backend (`poetry export --without-hashes --with dev`), cộng Airflow. Với
  Airflow 3.3.2, venv này có `sqlalchemy 2.0.55` ⇒ **chạy được cả DAG thật**.
* ⇒ **Cổng tương thích 2.10.4 được giữ lại**: một venv riêng chỉ có
  `apache-airflow==2.10.4` + `pytest`, chạy **cùng** file test DAG để bảo đảm
  test không phụ thuộc version Airflow.
* **Không thêm `apache-airflow` vào `pyproject.toml`/`poetry.lock`**: thêm
  `airflow==2.10.4` sẽ phình lock thêm hàng trăm gói **và** mâu thuẫn với
  `sqlalchemy<2.1` (không resolve được); thêm Airflow 3.x thì kéo
  `fastapi>=0.129` vượt cap `<0.116`. Vì vậy CI dùng `pip install` trong venv
  tách biệt, **không** chạm `poetry.lock` (canonical) ⇒ `poetry check --lock`
  vẫn sạch.

### 9.4. Thứ tự step trong CI (sau khi sửa)

```
Install Poetry
→ Install backend dependencies (Poetry venv)        ← FIX 1 (trước mọi test)
→ Export backend requirements (locked)
→ Create isolated Airflow runtime venv (3.3.2)
→ Create Airflow 2.10.4 compatibility venv
→ Create Airflow metadata DB (Postgres service, DB riêng bankops_test_airflow)
→ Initialise Airflow metadata DB (airflow db migrate)
→ Airflow DAG structure tests (3.3.2)   QLK_REQUIRE_AIRFLOW=1
→ Airflow DAG structure tests (2.10.4)  QLK_REQUIRE_AIRFLOW=1   ← cổng tương thích
→ Airflow ingest task tests (side effect thật: DB + MLflow)
→ Run Alembic migrations → Seed database
→ Airflow DAG run thật (airflow dags test × 3)     ← FIX 3
→ Ghi bằng chứng DAG run (machine-readable)
→ Run ML Training → Promote model → MLflow registry gate (fail-closed)
→ FastAPI Serving Smoke Test → Drift Detection Check
→ E2E Verification Summary → Upload artifacts
```

**Không vacuous:** mọi job Airflow đặt `QLK_REQUIRE_AIRFLOW=1`. Khi đó
`backend/tests/test_airflow_dags.py` **fail** (collection error) nếu Airflow
không import được trong đúng venv đang chạy pytest — không còn đường
`importorskip` để CI xanh trong khi không kiểm chứng gì.

**Ghi chú về `backend/tests/test_e2e_verify.py`:** file này tồn tại trên
`main` nhưng **không** có trên branch, và bản trên `main` gọi
`e2e_verify.verify_chain()` — hàm không tồn tại trong
`backend/scripts/e2e_verify.py` của branch (file này chỉ có `verify_registry`).
Vì vậy **không** mang file sang branch (sẽ đỏ ngay), và workflow **không**
còn tham chiếu file không tồn tại. Việc đồng bộ `verify_chain` giữa `main` và
branch là việc khác, cần người phụ trách actor `main` hoàn tất.

---

## 10. Kết quả verify cục bộ (2026-10-21, worktree branch)

Tất cả lệnh dưới đây chạy trong worktree cô lập của branch
`recovery/g2-20261020` (tip `9e85dd5` → HEAD sau khi sửa), với PostgreSQL
disposable `qlk-ci-fix-pg` (`127.0.0.1:55440`, DB `bankops_test` +
`bankops_test_airflow`).

### 10.1. Test DAG — Airflow **2.10.4** (đúng version branch từng pin)

```console
$ QLK_REQUIRE_AIRFLOW=1 venv-af2104/bin/python -m pytest tests/test_airflow_dags.py -q --no-header
.....................                                                    [100%]
21 passed, 1 warning in 0.85s
```

(`venv-af2104` = venv tạm **ngoài repo**: `apache-airflow==2.10.4` theo
`constraints-2.10.4/constraints-3.11.txt` + `pytest==8.3.5`; `sqlalchemy 1.4.54`
do Airflow kéo theo.)

### 10.2. Test DAG — Airflow **3.3.2** (môi trường runtime của CI)

```console
$ QLK_REQUIRE_AIRFLOW=1 venv-e2e/bin/python -m pytest tests/test_airflow_dags.py -q --no-header
.....................                                                    [100%]
21 passed, 1 warning in 1.29s
```

### 10.3. Test DAG — **không có Airflow** ⇒ fail (không xanh vacuous)

```console
$ QLK_REQUIRE_AIRFLOW=1 backend/.venv/bin/python -m pytest tests/test_airflow_dags.py -q
ERROR collecting tests/test_airflow_dags.py
E   RuntimeError: Airflow chưa dùng được trong môi trường này ... import `airflow` lỗi:
    No module named 'airflow'. ...
!!!! Interrupted: 1 error during collection !!!!
```

Không đặt `QLK_REQUIRE_AIRFLOW` (ví dụ job `ci.yml` không cài Airflow) thì
module bị **skip kèm lý do rõ ràng** (không phải skip im lặng):

```console
$ backend/.venv/bin/python -m pytest tests/test_airflow_dags.py -q -rs
SKIPPED [1] tests/test_airflow_dags.py:138: Airflow chưa dùng được trong môi trường này ...
1 skipped in 0.01s
```

### 10.4. DAG thật trong CI — `airflow dags test` (Airflow 3.3.2)

```console
$ airflow dags test inventory_ingestion 2026-10-21
... Done. Returned value was: {'dataset': 'inventory', ..., 'size_bytes': 16223,
    'sha256': 'ae7651846d20016e3251217e4c9bc7d4833a374bb3813ac444b6792509613099'}
... Done. Returned value was: {'dataset': 'inventory', 'row_count': 30, ...}
... Done. Returned value was: {'dataset': 'inventory', 'row_count': 30, 'valid_rows': 30,
    'invalid_rows': 0, 'fingerprint': 'd11fa66c6c177a11a7f84d3d50bba2eacccb9667826c144c8495df200f7f085e'}
... Done. Returned value was: {'inserted': 30, 'skipped': 0, 'total_rows': 30,
    'table': 'qlk_ingest_staging', 'dataset': 'inventory', 'database': '127.0.0.1:55440/bankops_test'}
... Done. Returned value was: {'run_id': '56bb2f72c6db43ddaf0ab8fbd2063a08', 'mae': 3.4234,
    'rmse': 4.2099, 'r2': 0.9030989484660734, 'train_size': 96, 'test_size': 24,
    'model_name': 'DemandForecastModel'}
... Done. Returned value was: {'promoted': True, 'version': 1, 'stage': 'Production',
    'r2': 0.9030989484660734, 'threshold': 0.7}
DagRun Finished: dag_id=inventory_ingestion, ..., state=success, run_type=manual

$ airflow dags test expense_ingestion 2026-10-21
... {'inserted': 8, 'skipped': 0, 'total_rows': 8, 'table': 'qlk_ingest_staging', 'dataset': 'expense'}
DagRun Finished: dag_id=expense_ingestion, ..., state=success

$ airflow dags test supplier_ingestion 2026-10-21
... {'inserted': 3, 'skipped': 0, 'total_rows': 3, 'table': 'qlk_ingest_staging', 'dataset': 'supplier'}
DagRun Finished: dag_id=supplier_ingestion, ..., state=success
```

### 10.5. Các bước CI còn lại (chạy tuần tự như trong workflow)

```console
$ pytest tests/test_airflow_ingest_tasks.py -q --no-header
15 passed, 11 warnings in 29.64s

$ pytest tests/test_ml_training.py tests/test_ml_registry.py -q --no-header
17 passed, 13 warnings in 36.09s

$ python "$GITHUB_WORKSPACE/promote_model.py"      # cwd = thư mục MLflow store của CI
Promoted version 7 to Production

$ python scripts/e2e_verify.py
{"model_name": "DemandForecastModel", "production_version": 7, "status": "passed"}

$ pytest tests/test_drift_detection.py -q --no-header
5 passed, 1 warning in 1.65s
```

### 10.6. Toàn bộ suite backend + lint + schema

```console
$ pytest tests -q --no-header          # DB disposable sạch
592 passed, 8 skipped, 1 xfailed, 22 warnings in 258.88s (0:04:18)     # 0 failed

$ ruff check backend/                    # ruff 0.17.0 (đúng version CI)
All checks passed!

$ poetry check --lock
rc=0                                    # poetry.lock không bị đụng

$ alembic check                          # DB sạch (đã alembic upgrade head)
No new upgrade operations detected.

$ flutter test                           # frontend
00:33 +195: All tests passed!
```

> Chênh lệch so với con số ghi trong bản evidence 2026-10-20
> (`613 passed`): chính là **21 test DAG** — ở `main` chúng chạy được vì venv
> `backend/.venv` của máy dev có sẵn Airflow 3.3.2; ở branch (venv sạch theo
> lock) chúng **skip** (đúng lý do) và **pass** trong venv có Airflow (§10.1,
> §10.2). Không có test nào fail.

---

## 11. Bảng trạng thái claim (2026-10-21)

| Hạng mục | Trạng thái | Bằng chứng |
|---|---|---|
| DAG import được, `task_ids` khớp, `task.dag is dag`, `python_callable` là hàm thật | **RUNTIME-PROVEN** | 21 test DAG pass trên **Airflow 2.10.4** (§10.1) và **Airflow 3.3.2** (§10.2) |
| CI không xanh vacuous (thiếu Airflow ⇒ FAIL) | **RUNTIME-PROVEN** | `QLK_REQUIRE_AIRFLOW=1` → collection error (§10.3) |
| Task callable chạy thật: đọc nguồn, parse, validate (fail-closed), load staging vào DB, idempotent, train MLflow, promote | **RUNTIME-PROVEN** | 15 test `test_airflow_ingest_tasks.py` (§10.5) |
| DAG thật (`airflow dags test`) chạy trọn chuỗi, nạp 30/8/3 dòng, train R²=0.9031, promote Production | **RUNTIME-PROVEN (local) + CI-STEP ĐÃ KIỂM CHỨNG** | §10.4 (Airflow 3.3.2, DB disposable của CI). **Chưa** có artifact từ GitHub Actions vì branch chưa push |
| Bằng chứng CI dạng artifact (`dag-run.json`, log từng DAG) | **NOT VERIFIED (CI)** | cần push branch + chạy workflow `s11-e2e-cloud-ci.yml`; bước CI đã dựng và đã kiểm chứng từng lệnh cục bộ |
| Scheduled run (scheduler/LocalExecutor, `airflow dags trigger`) | **NOT VERIFIED** | chưa chạy; mọi bằng chứng dùng `airflow dags test` (chạy trong process) |
| Bảng staging → bảng nghiệp vụ (`inv_items`, `expenses`, `suppliers`) | **NOT VERIFIED** | xem §8 mục 3 |
| Airflow 2.10.4 chạy được **chuỗi ingest** | **KHÔNG THỂ** (không phải "chưa verify") | xung đột `sqlalchemy<2.0` vs `sqlalchemy>=2.0.35` (§9.3) |
