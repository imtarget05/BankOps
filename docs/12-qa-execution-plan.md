 # 12 — QA Execution Plan (QA-Only Validation)
 
 > **Scope**: QA-only validation plan — **no merge/commit** of feature changes.
 > **Status**: Phase 1 complete → QA planning begins.
 > **Baseline**: 217 tests pass (2 pre-existing failures).
 
 ## PHASE 1 — QA ENVIRONMENT SETUP
 
 ### 1.1 Freeze Working Tree
 - [ ] `git status` — no uncommitted changes
 - [ ] `git stash` any stray changes
 - [ ] Create QA planning branch: `git checkout -b qa-validation-$(date +%Y%m%d)`
 
 ### 1.2 Spin Up Clean QA Database (port 5433)
 ```bash
 docker run -d --name bankops-qa-db \
   -e POSTGRES_USER=bankops -e POSTGRES_PASSWORD=bankops -e POSTGRES_DB=bankops \
   -p 5433:5432 postgres:16-alpine
 cd backend && alembic upgrade head
 python -c "from app.seed import seed_demo; import asyncio; asyncio.run(seed_demo())"
 ```
 - [ ] `GET /health/ready` returns 200 `status: ready`
 
 ### 1.3 Run Backend Suite Against QA DB
 ```bash
 DATABASE_URL="postgresql+asyncpg://bankops:bankops@localhost:5433/bankops" \
   python -m pytest -v --tb=short
 ```
 - [ ] All 217 pass; 2 pre-existing failures confirmed identical signatures
 
 ### 1.4 Pre-existing Failure Baseline
 - [ ] `test_issue_more_than_balance` — test isolation issue
 - [ ] `test_sse_replay_after_reconnect` — missing `jobs.lease_owner` column
 - [ ] Capture exact error signatures
 
 ## PHASE 2 — BACKEND BUSINESS-CRITICAL PATHS
 
 | Test ID | Scenario | Expected |
 |---------|----------|----------|
 | A1 | Maker approves own request | 403 `SELF_APPROVAL_FORBIDDEN` |
 | A2 | Two checkers approve simultaneously | 1 post, 1×200 + 1×409/replay-same |
 | A3 | Retry same key+payload | Same result ID, 1 movement |
 | A4 | Same key, diff payload | 409 `IDEMPOTENCY_KEY_MISMATCH` |
 | I1 | Issue > on-hand | 409 `INSUFFICIENT_STOCK`, balance unchanged |
 | I2 | Transfer locations | 2 movements, qty preserved |
 | I3 | Duplicate serial | 409 `DUPLICATE_SERIAL`, no 2nd asset |
 | C1 | Payment > demo budget | 409 `EXCEEDS_DEMO_LIMIT`, no journal |
 | C2 | Valid receipt/payment | debit=credit, Decimal balance |
 | C3 | Reversal | New balanced journal, original intact |
 | R1 | Planted mismatch → reconcile | `status: exception` with expected/actual |
 | G1 | CSV invalid row | Preview isolates, confirm blocks |
 | G2 | Webhook bad signature | 401; replay → 409 |
 | E1 | SSE disconnect + reconnect | Replay by cursor or `resync_required` |
 | S1 | User reads out-of-scope object | 403 or 404 |
 
 ## PHASE 3 — UI QA BY ROLE
 
 | Role | Paths to Test |
 |------|--------------|
 | Maker | Create draft → submit → 403 on approve |
 | Checker | Inbox → approve → 200 posted |
 | Auditor | Audit log read-only → no sensitive export |
 | Staff | Read-only → no write buttons |
 
 - [ ] Breakpoints: 320/768/1024/1440px
 - [ ] Demo watermark visible
 - [ ] Loading / Error / Empty states
 - [ ] CSV/Excel export — no formula injection
 
 ## PHASE 4 — AI QA
 
 - [ ] AI without DB context → **abstain** (not fabricate)
 - [ ] AI with data → includes **source citation**
 - [ ] Prompt injection (`ignore previous instructions`) → blocked
 - [ ] System prompt leakage → blocked
 - [ ] Staff queries restricted data → permission error/abstain
 - [ ] AI provider down → heuristic fallback (not 500)
 
 ## PHASE 5 — DEPLOYMENT VALIDATION
 
 - [ ] `python3 scripts/check_no_secrets.py` → exit 0
 - [ ] Git history secret scan → 0 results
 - [ ] `docker compose config` → exit 0
 - [ ] `docker compose up --build -d` → all healthy
 - [ ] QA DB backup/restore verified
 - [ ] Health/readiness probes pass
 - [ ] Post-deploy smoke: login → items → balances → audit-events
 
 ## PHASE 6 — EXIT CRITERIA
 
 | Criterion | Status |
 |-----------|--------|
 | 217 backend tests pass (2 pre-existing confirmed) | ⏳ |
 | A1–E1, I1–I3, C1–C3, G1–G2, S1 pass | ⏳ |
 | UI QA by role | ⏳ |
 | AI QA complete | ⏳ |
 | Secrets scan clean | ⏳ |
 | Docker Compose healthy | ⏳ |
 | Backup/restore verified | ⏳ |
 | Post-deploy smoke passes | ⏳ |
 
 ## PHASE 7 — RISK REGISTER
 
 | Risk | Mitigation |
 |------|-----------|
 | Pre-existing failures regress | Capture signatures before/after |
 | No Flutter SDK | Document skip; verify web build |
 | AI unreachable | Verify heuristic fallback graceful |
 | Concurrent approval race | Manual parallel simulation |
 | Webhook needs live URL | Use ngrok or mock receiver |
 | Backup integrity | Compare row counts pre/post restore |
 
 ## PHASE 8 — QA ARTIFACTS (docs/qa/)
 
 1. `docs/qa/01-environment-setup.md`
 2. `docs/qa/02-backend-test-log.md`
 3. `docs/qa/03-acceptance-results.md`
 4. `docs/qa/04-ui-role-qa.md`
 5. `docs/qa/05-ai-qa.md`
 6. `docs/qa/06-deployment-validation.md`
 7. `docs/qa/07-exit-report.md`
 
 **Next**: Freeze tree → Spin up QA DB → Run pytest.