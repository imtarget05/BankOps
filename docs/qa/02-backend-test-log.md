 # QA 02 — Backend Test Execution Log
 
 ## Test Run: 2026-10-14 (Round 1)
 
 ### Command
 ```bash
 cd backend && \
   DATABASE_URL="postgresql+asyncpg://bankops:bankops@localhost:5433/bankops" \
   APP_ENV=test \
   PYTHONPATH=/Users/mainguyenbinhtan/Downloads/BankOps/backend \
   python3 -m pytest -v --tb=short
 ```
 
 ### Summary
 | Outcome | Count |
 |---------|-------|
 | PASSED | 218 |
 | SKIPPED | 2 |
 | FAILED | 1 |
 | ERRORS | 0 |
 | **Total** | **221** |
 
 ### Pre-existing Failures (per session summary)
 
 #### 1. `test_issue_more_than_balance_is_409_and_balance_unchanged` — FAILED
 - **Location**: `tests/test_acceptance_qa.py:294`
 - **Signature**: 
   ```
   AssertionError: {"error":{"code":"INSUFFICIENT_STOCK","message":"không đủ tồn khả dụng tại kho nguồn để đặt trưởng toàn bộ phiếu","request_id":"...","details":{}}}
   assert 409 in (200, 201)
   ```
 - **Root cause**: Test isolation issue. The submit step (`/inventory/requests/{id}/submit`) correctly returns 409 `INSUFFICIENT_STOCK` when attempting to issue 999999 units with insufficient stock, but the test assertion at line 294 expects 200/201. The business behavior is correct — the test assertion needs adjustment to accept 409 at submit time (I1 invariant holds).
 - **Not a regression**: The test was pre-identified as a pre-existing failure in the session summary.
 
 #### 2. `test_sse_replay_after_reconnect` — PASSED (was pre-existing failure)
 - **Status**: Now passing in QA environment
 - **Previously reported**: Missing `jobs.lease_owner` column
 - **Current state**: Migration `012_job_leases.py` added `lease_owner` column; test passes
 - **Note**: The migration was part of Phase 1 work and is now present in QA environment
 
 ### Skipped Tests (2)
 Both tests skipped due to missing Flutter SDK in environment (UI-related).
 
 ### Detailed Results (key test classes)
 | Test Class | Passed | Failed | Skipped |
 |---|---|---|---|
 | TestB01Build | ✅ | 0 | 0 |
 | TestBoot | ✅ | 0 | 0 |
 | TestAuthRBAC | ✅ | 0 | 0 |
 | TestA1SelfApproval | ✅ | 0 | 0 |
 | TestA2DoubleApprove | ✅ | 0 | 0 |
 | TestA3SameKeySamePayload | ✅ | 0 | 0 |
 | TestA4SameKeyDiffPayload | ✅ | 0 | 0 |
 | TestI1I2Inventory | 0/2* | 1* | 0 |
 | TestCashSim | ✅ | 0 | 0 |
 | TestR1Reconciliation | ✅ | 0 | 0 |
 | TestG1G2Integrations | ✅ | 0 | 0 |
 | TestE1SSE | ✅ | 0 | 0 |
 | TestS1RBAC | ✅ | 0 | 0 |
 
 *TestI1I2Inventory has 1 failure (pre-existing, documented above)
 
 ### Acceptance Test Results (A1-A4, I1-I3, C1-C3, G1-G2, E1, S1, R1)
 
 | Test ID | Status | Notes |
 |---------|--------|-------|
 | A1 (self-approval) | ✅ PASS | 403 `SELF_APPROVAL_FORBIDDEN` |
 | A2 (double-approve) | ✅ PASS | Concurrency handled correctly |
 | A3 (same key same payload) | ✅ PASS | Same result ID, 1 movement |
 | A4 (same key diff payload) | ✅ PASS | 409 `IDEMPOTENCY_KEY_MISMATCH` |
 | I1 (over-issue) | ⚠️ FAIL (pre-existing) | Business logic correct, test assertion needs fix |
 | I2 (transfer) | ✅ PASS | 2 movements, qty preserved |
 | I3 (duplicate serial) | ✅ PASS | 409 `DUPLICATE_SERIAL` |
 | C1 (over budget) | ✅ PASS | 409 `EXCEEDS_DEMO_LIMIT` |
 | C2 (valid cash flow) | ✅ PASS | debit=credit, Decimal balance |
 | C3 (reversal) | ✅ PASS | New balanced journal, original intact |
 | R1 (reconciliation) | ✅ PASS | Exception detected, no auto-fix |
 | G1 (CSV error isolation) | ✅ PASS | Preview isolates, confirm blocks |
 | G2 (webhook signature) | ✅ PASS | 401/409, no draft |
 | E1 (SSE reconnect) | ✅ PASS | Replay/resync works |
 | S1 (object-level auth) | ✅ PASS | 403/404 per policy |
 
 ### Additional Test Files Passed
 - `test_contract_vs_docs.py` — OpenAPI/contract verification ✅
 - `test_integrations.py` — Connector sandbox tests ✅
 - `test_modal_llm.py` — LLM infra tests ✅
 - `test_phase1_stock_levels.py` — Stock levels & stocktakes ✅
 - `test_reports.py` — Reporting aggregation ✅
 - `test_reserved_inventory_and_return.py` — Reservation lifecycle ✅
 - `test_sse_approvals.py` — SSE approval events ✅
 - `test_worker_jobs.py` — Background job leases ✅