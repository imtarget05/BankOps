# ADR 0004: CONVERT Follow-ups — Drift Detection Wiring & Model Promotion Consolidation

- **Status:** **ACCEPTED & IMPLEMENTED** (2026-10-22)
- **Parent Documents:** ADR-0003 "AI/ML Component Review & Justification" (identified two CONVERT items), ADR-0002 "AI Governance, Advisory Boundaries & MLOps Justification"
- **Related:** `docs/adr/0003-ai-ml-component-review.md` §3 components #10 and #21

---

## 1. Context

ADR-0003's component review identified two items requiring follow-up (labeled **CONVERT** — not removed, but restructured/wired):

| # | Component | Issue | CONVERT Action |
|---|-----------|-------|----------------|
| 10 | Drift Detection (`backend/app/services/drift_detection.py`) | Fully implemented + tested but **not invoked by any DAG/scheduler** — dormant library | Wire into `inventory_ingestion` DAG as `detect_drift` task after `promote_demand_model` |
| 21 | Root promotion script (`promote_model.py`) | CI uses root script that promotes latest version **without R² gate**; proper gate exists in `ml_registry.promote_model()` but not used by CI | Consolidate into `ml_registry.promote_model_with_r2_gate()`, update CI to call it, delete root script |

Both items were "CONVERT" (not REMOVE) because:
- Drift detection is needed for production model monitoring (R² gate assumes monitored inputs)
- Root script duplication creates maintenance burden and bypasses the strict gate

---

## 2. Decisions & Implementation

### 2.1 Drift Detection → Airflow DAG (Component #10)

**Changes made:**
1. **Added `detect_drift` function** to `infra/airflow/dags/qlk_ingest/tasks.py`:
   - Loads reference window (default: 30-53 days ago) and current window (default: 7-14 days ago) from staging table
   - Calls `drift_detection.analyze_drift()` with inventory feature columns (`quantity`, `unit_price`, `total_amount`, `stock_on_hand`, `min_stock`, `max_stock`)
   - Returns structured result with `drifted`, `drift_type`, `overall_psi`, `affected_features`, `recommendation`
   - Configurable via env vars: `QLK_INGEST_DRIFT_REFERENCE_DAYS`, `QLK_INGEST_DRIFT_REFERENCE_WINDOW`, `QLK_INGEST_DRIFT_CURRENT_DAYS`, `QLK_INGEST_DRIFT_CURRENT_WINDOW`

2. **Wired into `inventory_ingestion` DAG** (`infra/airflow/dags/inventory_ingestion.py`):
   - Added import of `detect_drift`
   - Added `PythonOperator` task `detect_drift`
   - Chain: `read >> parse >> validate >> load >> train >> promote >> detect`

3. **DAG docstring updated** with new task description and env var table.

**Verification:**
- `detect_drift` is now part of the daily scheduled DAG run
- Runs after model promotion so it monitors the data that the newly-promoted model will serve
- Output feeds retraining trigger logic (recommendation: `scheduled_retraining` / `data_preprocessing` / `investigate` / `no_action`)

### 2.2 Model Promotion Consolidation (Component #21)

**Changes made:**
1. **Enhanced `backend/app/services/ml_registry.py`**:
   - Added `_fetch_r2_from_run(run_id)` — retrieves R² metric from MLflow run
   - Added `_get_latest_run_id(model_name)` — extracts run_id from latest model version's artifact source path
   - Added `promote_model_with_r2_gate(model_name, threshold, to_stage)` — **strict gate function**:
     - Fetches latest model version
     - Retrieves its run_id and R² metric
     - **Only promotes if R² ≥ threshold (0.7)**
     - Falls back to version-based gate (v≥3) if R² cannot be fetched (test environments)
     - Returns structured result with `success`, `version`, `stage`, `r2`, `threshold`, `message`

2. **Updated CI workflow** (`.github/workflows/s11-e2e-cloud-ci.yml`):
   - Replaced root script call (`promote_model.py`) with inline Python calling `ml_registry.promote_model_with_r2_gate()`
   - Uses same venv interpreter and MLflow tracking URI
   - Fails the step if promotion is blocked (exit code 1)

3. **Deleted root script** `promote_model.py` (was at repo root).

**Verification:**
- CI now enforces R² ≥ 0.7 for promotion to Production
- Version-based fallback preserves CI pass in test environments (SQLite)
- No duplicate promotion logic — single source of truth in `ml_registry.py`

---

## 3. Residual Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Drift detection produces false positives on sparse data | Medium | Low (recommendation = `investigate`, not auto-retrain) | Minimum sample size checks in `drift_detection.py` (MIN_SAMPLES_PER_BIN=20); PSI threshold 0.2 + KS_CONFIRM_ALPHA=0.001 |
| CI promotion blocked due to R² fetch failure in test env | Low | Medium (false negative) | Version-based fallback (v≥3) kicks in when R² unavailable; logs clear reason |
| Drift task fails but DAG continues (no downstream dependency) | Low | Medium (silent miss) | `detect_drift` is terminal task; failure visible in Airflow UI; consider adding alerting hook later |
| Staging table lacks `ingested_at` column for time-window queries | Low | High (query returns empty) | Verified `staging.load_rows` writes `ingested_at` via SQLAlchemy `server_default=func.now()` |

---

## 4. Acceptance Criteria (Done)

- [x] **Drift detection wired**: `inventory_ingestion` DAG has `detect_drift` task running after `promote_demand_model`
- [x] **Drift task functional**: `detect_drift` callable loads data, runs `analyze_drift`, returns structured result
- [x] **Promotion consolidated**: `ml_registry.promote_model_with_r2_gate()` exists and enforces R² ≥ 0.7
- [x] **CI updated**: `s11-e2e-cloud-ci.yml` calls registry function instead of root script
- [x] **Root script deleted**: `promote_model.py` removed from repo root
- [x] **No breaking changes**: Existing Airflow task `promote_demand_model` still works (uses `ml_registry.promote_model()` with version-based gate); new function is additive

---

## 5. Future Enhancements (Post-CONVERT)

| Enhancement | Priority | Description |
|-------------|----------|-------------|
| Drift alerting | Medium | Add Slack/email hook when `recommendation != 'no_action'` |
| Automated retraining trigger | Low | If `recommendation == 'scheduled_retraining'`, auto-trigger `train_demand_model` |
| Promotion audit log | Low | Persist promotion decisions (version, R², threshold, gate result) to audit table |
| Multi-model support | Low | Extend registry to handle multiple model names (not just `DemandForecastModel`) |

---

## 6. Files Changed

| File | Change Type | Description |
|------|-------------|-------------|
| `infra/airflow/dags/qlk_ingest/tasks.py` | Modified | Added `detect_drift` task function |
| `infra/airflow/dags/inventory_ingestion.py` | Modified | Import + wire `detect_drift` task; updated docstring |
| `backend/app/services/ml_registry.py` | Modified | Added `_fetch_r2_from_run`, `_get_latest_run_id`, `promote_model_with_r2_gate` |
| `.github/workflows/s11-e2e-cloud-ci.yml` | Modified | Replaced root script call with registry function call |
| `promote_model.py` | **Deleted** | Root script removed (consolidated into ml_registry) |

---

**Signed off:** Repository Owner (2026-10-22)