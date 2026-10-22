# ADR 0003: AI/ML Component Review — Keep / Remove / Justify Inventory

- **Status:** **ACCEPTED — REVIEW COMPLETE** (2026-10-22)
- **Requirement Reference:** Close-out companion to **G11** from the Gap Register (per-component audit layer; governance boundaries are decided in ADR-0002).
- **Related Documents:** [ADR 0002 — AI Governance and Advisory Boundaries](0002-ai-governance-and-advisory-boundaries.md), [Decision C3 in 00-decisions.md](../00-decisions.md), [docs/mlops/G11_AI_COMPONENT_JUSTIFICATION.md](../mlops/G11_AI_COMPONENT_JUSTIFICATION.md), [docs/evidence/phase-m-closure.md](../evidence/phase-m-closure.md), [docs/17-hf-llm-space.md](../17-hf-llm-space.md).

---

## 1. Context

ADR-0002 (accepted 2026-10-22) fixed the *governance boundaries* of AI in QuanLyKho:
advisory-only, deterministic policy floor, SHA-256 provenance, clean/offline decoupling of
Airflow + MLflow. `docs/mlops/G11_AI_COMPONENT_JUSTIFICATION.md` added a first keep-vs-remove
matrix.

This ADR completes the remaining part of the G11 plan action — *"Review each component; keep
only use-case-justified; prioritize core business correctness"* — by inventorying **what
actually exists in the repo** and issuing a keep / remove / convert verdict **per component**,
including components the earlier matrix did not cover. No code is added, removed, or rewritten
by this document; removal verdicts list their concrete removal step for a future change.

**Verify note (stale-audit paths):** a prior catalog cited `api/routes/ai.py` and
`app/services/ai.py` without the `backend/` prefix; the real paths are
`backend/app/api/routes/ai.py` and `backend/app/services/ai.py` (both exist). The DAG set is
three files (`supplier_ingestion.py`, `inventory_ingestion.py`, `expense_ingestion.py`) plus
the `qlk_ingest/` package — not five separate AI DAGs, and two of the three are **pure
ingestion** (verified below), not AI.

## 2. Inventory Scope & Method

Searched: `*ai*.py` / `*ml*` filenames (excluding `backend/.venv`, `node_modules`), imports of
`mlflow` / `langfuse` / `openai` / `anthropic`, training code, `infra/airflow/dags/`, Modal and
HF-Space deployment code, generated MLflow stores, and AI-related tests. Findings below.

## 3. Component Review Table

Verdicts: **KEEP justified** · **REMOVE candidate** (not executed here) · **CONVERT**.

| # | Component | Path | Purpose | Verdict | Justification | Core-business impact |
|---|-----------|------|---------|---------|---------------|----------------------|
| 1 | Risk-Assessment Advisory API | `backend/app/api/routes/ai.py` | `POST /ai/assess-request`, `/ai/chat`, `/ai/stream`; canonical voucher binding from PostgreSQL under checker branch scope, per-process rate limit | **KEEP justified** | Implements the ADR-0002 contract (canonical binding, anti-forgery, bounded output). Evidence: `backend/tests/test_ai.py`, `test_ai_assessment_canonical.py`, `test_ai_provider_gating.py`, `test_portfolio_ai_checker_demo.py` (interview demo: AI never posts inventory without a human checker). | Supports **Checker approval decisions** on variance/stocktake vouchers — directly inside the Maker-Checker loop. |
| 2 | Risk-Scoring Advisor + Heuristic Fallback | `backend/app/services/ai.py` | LLM risk scoring with bounded JSON schema; `assess_request_heuristic` deterministic fallback | **KEEP justified** | Fail-safe core of the advisory path (ADR-0002 §2.1): provider outage degrades to rules, never blocks approvals. Evidence: `backend/tests/test_ai.py`, `test_ai_qa_suite.py` (incl. prompt-injection defense case). | Zero impact on OLTP correctness when degraded — approval authority stays with the human Checker. |
| 3 | SOP Retrieval (BM25) | `backend/app/services/ai_retrieval.py` | Keyword retrieval over repo SOP docs with citations; abstains when nothing matches | **KEEP justified** | Grounds chat answers in warehouse SOP; requires citation, does not invent. Evidence: `backend/tests/test_ai_retrieval.py`, `test_ai_retrieval_service.py`. | Advisory only; mis-retrieval cannot corrupt inventory or cash state. |
| 4 | RAG Evaluation Harness | `backend/app/services/ai_evaluation.py` | Measures Recall@K and citation accuracy over a JSONL eval set | **KEEP justified** | Quality gate for #3; small, dependency-free (no numpy/pandas/scipy — lighter than the ML stack). Evidence: exercised via `scripts/run_ai_eval.py`. | Indirect; keeps the advisory assistant trustworthy. |
| 5 | RAG Eval CLI | `scripts/run_ai_eval.py` | Runs #4 from the command line against the docs index | **KEEP justified** | Thin, readable wrapper. Evidence: script + harness tests. | None directly. |
| 6 | Reorder-Point & Anomaly API | `backend/app/api/routes/ai_forecasting.py` (+ `backend/app/services/reorder_point.py`) | `/ai` reorder-point optimization and demand-anomaly alerts via **deterministic** math (not a learned model) | **KEEP justified** | Capability-gated (deny-by-default `inventory:view_balances`); deterministic services cannot hallucinate. Evidence: `backend/tests/test_ai_forecasting_api.py`. | Informs purchasing for the tea-warehouse core flow (Nhập–Xuất–Tồn). |
| 7 | Demand-Forecast Training Pipeline | `backend/app/services/ml_training.py` | Time-aware-train/test demand forecast (scikit-learn LinearRegression → MLflow tracking) | **KEEP justified** | Offline-only (zero import in `app/`), triggered from the Airflow DAG and tests. Note: its default dataset is **synthetic** (`generate_synthetic_inventory_demand`); real data arrives via the DAG staging path. Evidence: `backend/tests/test_ml_training.py`; E2E evidence `docs/mlops/airflow-ingest-evidence-2026-10-20.md`. | None at runtime — physically decoupled from `/inventory/*`, `/reconciliations/*` (ADR-0002 §2.3). |
| 8 | MLflow Model Registry | `backend/app/services/ml_registry.py` | Versioning; Staging→Production promotion only if R² ≥ 0.7; rollback | **KEEP justified** | Promotion gate prevents low-quality models from serving. Evidence: `backend/tests/test_ml_registry.py`; CI gate step "MLflow registry gate (fail-closed)" in `.github/workflows/s11-e2e-cloud-ci.yml`. | Offline MLOps only. |
| 9 | Model-Serving API (standalone) | `backend/app/api/inference.py` | Phase M S6: standalone FastAPI app serving only the MLflow *Production* stage model; `/health` + metrics logging | **KEEP justified** (wiring note) | Code-verified and tested (`backend/tests/test_inference_api.py`, `test_inference_model_lifecycle.py`, `test_inference_mlflow_config.py`). It is **not** mounted into `backend/app/main.py` nor in `docker-compose*.yml` — it is a separate offline serving app, by design. Future wiring (if any) must stay offline. | None on the transactional path. |
| 10 | Drift Detection Library | `backend/app/services/drift_detection.py` | PSI + KS data drift, concept-drift via prediction change, retraining trigger, alert logging | **CONVERT** | Present and tested (`backend/tests/test_drift_detection.py`) but **not invoked by any DAG, cron, or scheduler** — it is currently a dormant library. Convert: add a `detect_drift` task to the `inventory_ingestion` DAG (after `train_demand_model`) or explicitly document manual invocation. Do not remove while #7/#8 exist, because the R² ≥ 0.7 promotion gate assumes monitored inputs. | None today (not wired); risk if left dormant: promotion gate could keep approving models on drifted data. |
| 11 | Airflow DAG — supplier ingestion | `infra/airflow/dags/supplier_ingestion.py` | Ingest supplier master data into staging | **KEEP justified** — **not AI** | Verified pure ingestion: `read_source → parse_rows → validate_rows → load_staging`; no model, no MLflow import. Evidence: `backend/tests/test_airflow_ingest_tasks.py`, `test_airflow_dags.py`. | Feeds clean staged data for the forecasting pipeline; otherwise core ETL. |
| 12 | Airflow DAG — expense ingestion | `infra/airflow/dags/expense_ingestion.py` | Ingest expense records into staging | **KEEP justified** — **not AI** | Same shape as #11; verified pure ingestion. | Same as #11. |
| 13 | Airflow DAG — inventory ingestion + train + promote | `infra/airflow/dags/inventory_ingestion.py` | Ingest inventory data, then `train_demand_model` (→ `app.services.ml_training.run_full_pipeline`) and `promote_demand_model` (→ `app.services.ml_registry`, gated on R² ≥ 0.7) | **KEEP justified** | The only DAG that touches AI; scheduled, offline, decoupled from OLTP. Evidence: DAG docstring tasks + `backend/tests/test_airflow_dags.py`, `test_airflow_ingest_tasks.py`, E2E `docs/mlops/airflow-ingest-evidence-2026-10-20.md`. | Offline only; failure never blocks warehouse operations. |
| 14 | Airflow ingest package | `infra/airflow/dags/qlk_ingest/` (`tasks.py`, `config.py`, `staging.py`, `__init__.py`) | Shared staging/config/task library for DAGs #11–#13 | **KEEP justified** | Real implementation (parse/validate/fingerprint/load staging, idempotency keys); used by all DAGs; tested. | Core ETL correctness — supports data quality of the business itself. |
| 15 | Modal LLM server | `infra/modal/bankops_llm_server.py` + `infra/modal/modal_app.py` | OpenAI-compatible GGUF (Qwen2.5-1.5B Q4_K_M) server on Modal, scale-to-zero; replaces blocked HF Docker Space (see `docs/17-hf-llm-space.md`) | **KEEP justified** | Deliberate cheap-hosting decision, documented in `infra/modal` docstrings; statically checkable without Modal SDK. Evidence: `backend/tests/test_modal_llm.py`. | Serves the *advisory chatbot* only; `AI_PROVIDER` gating keeps it swappable with Cloudflare Workers AI / Ollama. |
| 16 | Modal Tea-Inventory backend deploy | `infra/modal/tea_inventory_api.py` | Deploys the **whole backend** to Modal + Neon | **KEEP (out of AI scope)** | Infra hosting wrapper for the core API; not an AI component — listed here only so the inventory is exhaustive. | Production hosting surface — correctness-critical, but not AI. |
| 17 | Modal legacy stub | `infra/modal/bankops_api.py` | Backward-compat stub re-exporting `tea_inventory_api` symbols | **REMOVE candidate** | Superseded entirely by `infra/modal/tea_inventory_api.py`; self-described legacy entry point. Concrete removal step (not executed): 1) `grep -r "bankops_api" docs/ infra/ scripts/ .github/` to confirm no deployment script/doc still references it; 2) delete `infra/modal/bankops_api.py`; 3) run `backend/tests/test_modal_llm.py` green; 4) note the removal in `docs/PORTFOLIO_AUDIT_2026-10-21.md`. | None — pure alias layer; removal cannot affect transactions. |
| 18 | HF-Space assets | `infra/hf-llm-space/` (Dockerfile, entrypoint.sh, model/, README.md) | Original GGUF-serving Docker Space deployment (docs/17) | **KEEP justified** | Still the documented deploy path and statically asserted by `backend/tests/test_hf_llm_space.py`; #15 was built to be API-compatible, not to delete this. | None beyond the advisory LLM host. |
| 19 | Fine-tune assets | `ai/Modelfile`, `ai/colab_finetune_bankops_t4.ipynb`, `ai/dataset/{train,val}.jsonl`, `ai/system-prompt.txt`, `ai/serve_cpu.py`, `ai/README.md` | LLM fine-tuning pipeline (Colab T4 → GGUF), Ollama Modelfile, standalone CPU inference server with rule-based fallback, system-prompt source of truth | **KEEP justified** | Provenance assets of the model actually served (#15/#18) — deleting them makes the fine-tune irreproducible; `serve_cpu.py` doubles as a GPU-free fallback server. This folder is the only place the BankOps system prompt is versioned. | Advisory only. |
| 20 | Master prompt | `prompts/MASTER_PROMPT.md` | Prompt-engineering doc | **KEEP justified** | Documentation; no runtime coupling found. | None. |
| 21 | Root promotion script | `promote_model.py` | CI promotion of `DemandForecastModel` to Production | **KEEP justified** (with caveat) | Actively used by `.github/workflows/s11-e2e-cloud-ci.yml` (step "Promote model to Production") and documented in `docs/mlops/airflow-ingest-evidence-2026-10-20.md` — do **not** remove today. Caveat: it transitions the *latest* version without re-checking R² ≥ 0.7, relying on the following "MLflow registry gate (fail-closed)" CI step instead of `backend/app/services/ml_registry.py`'s built-in gate. Convert later: have the CI step call a registry function that enforces the threshold, then delete the root script. | Offline MLOps only. |
| 22 | Root MLflow stores | `mlflow.db`, `test_mlflow.db`, `test_mlflow_38621_unknown.db` … `test_mlflow_75524_unknown.db` (10 files), `mlruns/` | Runtime/test MLflow tracking stores (SQLite + artifacts); total ≈ 10 MB | **REMOVE candidate** (repo hygiene) | Generated artifacts; all matched by `.gitignore` lines 44–48 (`mlruns/**`, `**/*mlflow*.db`) — none are git-tracked (`git ls-files` returns only tests that *reference* them). They leak from test runs such as `backend/tests/test_mlflow_tracking.py`. Concrete removal step (not executed): `rm -f mlflow.db test_mlflow*.db && rm -rf mlruns/`; ensure any test that creates them uses `pytest` tmp_path or the tracked `MLFLOW_TRACKING_URI`/temp-dir convention so they stop re-appearing. | None — local dev residue. |
| 23 | Langfuse smoke scripts | `backend/scripts/langfuse_smoke_local.py`, `backend/scripts/langfuse_smoke_e2e.py` | Observability lifecycle smoke tests (disabled no-op → masked trace flush → service integration) | **KEEP justified** | Lightweight proofs that provider observability cannot leak credentials and degrades to a no-op. Evidence: scripts + `backend/tests/test_observability_tracing.py`. | None directly. |
| 24 | AI/ML test suite | `backend/tests/test_ai.py`, `test_ai_qa_suite.py`, `test_ai_assessment_canonical.py`, `test_ai_provider_gating.py`, `test_ai_retrieval.py`, `test_ai_retrieval_service.py`, `test_ai_forecasting_api.py`, `test_ml_training.py`, `test_ml_registry.py`, `test_mlflow_tracking.py`, `test_inference_api.py`, `test_inference_model_lifecycle.py`, `test_inference_mlflow_config.py`, `test_drift_detection.py`, `test_airflow_dags.py`, `test_airflow_ingest_tasks.py`, `test_modal_llm.py`, `test_hf_llm_space.py`, `test_portfolio_ai_checker_demo.py` | Automated verification evidence for every component above | **KEEP justified** | Per Decision C3, each kept component must carry automated-verification evidence — this suite is that evidence (the earlier audit's "7 AI test files" undercounted; the full set is 19). | The gate that keeps the whole AI stack honest. |

Components considered and **not** present (audit stale-path check): `api/routes/ai.py` /
`app/services/ai.py` as written without `backend/` are stale prefixes only; no
`airflow/dags/ingest_sales_and_inventory.py` exists under that exact name
(ADR-0002 §2.3's example name — the actual DAGs are #11–#13); no Langfuse service module of
its own in `backend/app/services/` (observability lives in `backend/app/core/observability.py`
and the smoke scripts #23). Also no OpenAI/Anthropic direct imports found; vendors are
Cloudflare Workers AI, Ollama, HF/Modal.

## 4. Summary of Verdicts

| Verdict | Components |
|---------|-----------|
| KEEP justified / KEEP (out of AI scope) | #1–#16, #18–#21, #23, #24 |
| REMOVE candidate (explicit, not executed) | #17 (`infra/modal/bankops_api.py`), #22 (root `mlflow.db`, `test_mlflow*.db`, `mlruns/`) |
| CONVERT | #10 (`drift_detection` → wire into the inventory DAG or document manual run), #21 (long-term: fold `promote_model.py` into the `ml_registry` threshold gate) |

## 5. Consistency with ADR-0002

Nothing in this review contradicts ADR-0002. All KEEP verdicts re-affirm its controls:
advisory-only AI (#1–#6), deterministic fallback (#2), offline decoupling of Airflow/MLflow
(#7–#14), no autonomous approvals (`#24` proves it). The two REMOVE candidates (#17, #22) are
*reductions* of surface area, not changes to the governed behavior. The one deliberate nuance
(#21 caveat) tightens rather than loosens the promotional gate and asks for migration *toward*
the gate already codified in `ml_registry.py`.

## 6. Consequences

- No code is deleted in this review; removal candidates carry their exact removal steps for a
  later, separately-reviewed change.
- The CONVERT items are follow-ups, prioritized behind core business correctness.
- Future AI/ML additions must append a row to § 3 and re-run this review before merging.
