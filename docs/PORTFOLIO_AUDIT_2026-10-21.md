# QuanLyKho — portfolio audit & interview defense

**Starting revision:** `c9b69355765af8e850e84a99a25e036d5d581120`;
**latest observed HEAD:** `5d79314364739e48cd589604d56764583d963286` (2026-10-21).
Concurrent local commits advanced HEAD through `d53c092` to `5d79314` during
this audit. At the start, the working tree already had edits in
`reconciliations.py`, the B2 scope-audit document and its test. Their status
changed during concurrent work; this audit did not edit them. Re-run the
commands on the exact revision presented in an interview.

## Business chain and claim matrix

The product is a tea-shop ingredient inventory system. The cash, journal and
reconciliation modules are simulations. PostgreSQL and the FastAPI process are
the write authority; the Cloudflare Worker is legacy/compatibility code.

| Use case | Decision | Status | Environment | Commit | Reproduce | Result | Limit |
|---|---|---|---|---|---|---|---|
| Receipt with lot/expiry | Persist request lines; reject expired lots | Locally verified | Isolated PostgreSQL | `5d79314` | `cd backend && .venv/bin/python -m pytest tests/test_tea_shift_regression.py -q` with migrated isolated `DATABASE_URL` | Validation test in full suite | Does not authenticate supplier or physical goods |
| Issue/transfer | Lock balances and consume valid lots in FEFO order | Locally verified | Isolated PostgreSQL | `5d79314` | `cd backend && .venv/bin/python -m pytest tests/test_phase2b_fefo_outbound.py -q` with migrated isolated `DATABASE_URL` | FEFO tests in full suite | No production stock audit; physical shelf handling remains operational |
| Shift count | Compare theoretical balance and variance; submit to checker | Locally verified | Isolated PostgreSQL | `5d79314` | `cd backend && .venv/bin/python -m pytest tests/test_shift_stocktake.py tests/test_tea_shift_regression.py -q` with migrated isolated `DATABASE_URL` | Shift tests in full suite | Offline close and push remain future work |
| Inventory adjustment/receipt | Separate maker/checker; row lock; movement, audit and outbox in one DB commit | Locally verified | Isolated PostgreSQL | `5d79314` + uncommitted audit patch | `scripts/demo_ai_checker.sh` | One movement and trace-linked approval audit event after retry; no movement on reject | No real-world verification of receipt document |
| Repeated approval | Replay same idempotency key; reject new key after final state | Locally verified | Isolated PostgreSQL | `5d79314` + uncommitted audit patch | `scripts/demo_ai_checker.sh` | Same-key result repeats; new key returns 409 | Does not establish exactly-once delivery across all integrations |
| AI assessment | Advisory risk summary, deterministic policy floor; human alone approves | Locally verified, simulated provider | Isolated PostgreSQL, no external model | `5d79314` + uncommitted audit patch | `scripts/demo_ai_checker.sh` | `heuristic_fallback`; zero autonomous approvals | Endpoint trusts client-supplied fields and does not persist assessment provenance |
| Read access | RBAC/branch checks; auditor reads audit events | Locally verified for demo path | Isolated PostgreSQL | `5d79314` + uncommitted audit patch | `scripts/demo_ai_checker.sh` | Maker self-approval 403; auditor sees events | B2 document defers some cross-branch surfaces; demo does not prove all routes |

**State vocabulary:** `Local PostgreSQL verified` means the route ran against
an isolated PostgreSQL instance in this audit. The product has no verified
production deployment, live IdP, actual bank/payment integration or UAT sign-off.
The uncommitted audit patch must be kept with the recorded HEAD for these
new demo claims to be reproducible; the commit SHA alone does not contain it.

## Status Summary (Current Commit)

| Module / Invariant | Status | Resolution Details |
|---|---|---|
| **AI Assessment Authority & Binding** | **RESOLVED** | Server fetches canonical DB voucher by UUID, enforces checker branch location scope (returns 404 for out-of-scope vouchers), and SHA-256 provenance stamp. |
| **Branch Scope Isolation (B2)** | **RESOLVED** | All stocktake routes (`create`, `update`, `submit`, `approve`, `reject`), approval inbox, and AI assessment strictly enforce `_require_location_scope` and branch ownership. |
| **Audit Events Pagination** | **RESOLVED** | Stable keyset pagination applied across `(occurred_at, id)` ensuring no skipped or duplicated audit entries. |
| **FEFO Legacy Lot Expiry** | **RESOLVED** | Removed artificial `2099-12-31` expiry date. Unverified legacy lots are placed with `expiry_date=None` (`nulls_last`), prioritizing lots with known expiry. |
| **Reviewer Sandbox Mode** | **RESOLVED** | 3-minute in-memory sandbox flow powered by `FakeBankOpsRepository` directly accessible from login screen without requiring live database access. |

## Prioritized findings and next actions

| Priority | Finding / business risk | Status | Acceptance check |
|---|---|---|---|
| P0 | README diagram and voucher UI previously made AI look like an approval authority. | **RESOLVED** | Diagram says checker/server decide; UI never declares document authenticity. |
| P1 | `POST /ai/assess-request` accepted client-forged fields and lacked object scope. | **RESOLVED** | Server fetches canonical DB voucher by ID under checker branch scope; returns 404 for out-of-scope requests. |
| P1 | Client-side risk display vs server step-up PIN threshold. | **RESOLVED** | Server independently enforces PIN requirement on high-risk transfers regardless of client display. |
| P1 | Scope audit: Stocktake mutations and approval inbox lacked location scope. | **RESOLVED** | `_require_location_scope` enforced across create, update, submit, approve, reject stocktake routes and approval inbox. |
| P1 | `/audit-events` pagination. | **RESOLVED** | Keyset pagination implemented and verified. |
| P2 | In-process AI rate limit and approval SSE bus do not share state across replicas. | OPEN (P2) | Documented single-replica deployment constraint; Redis/broker shared bus planned for distributed pilot. |
| P2 | Offline close and push sync. | OPEN (P2) | Online-first pilot; offline sync and conflict resolution planned for phase 2. |

## Five-minute local demo

From this repo root, run `scripts/demo_ai_checker.sh`. It creates a disposable
local PostgreSQL database, applies Alembic through `027_idempotency_keys`, runs
the HTTP journey and stops/removes the database. It requires local PostgreSQL
executables (`initdb`, `pg_ctl`, `createdb`) and `backend/.venv`; it never touches
the developer database. `make test-backend` is the Docker-based full-suite gate
when Docker is available.

The journey is: maker creates and submits an ingredient receipt → checker gets
advisory assessment with a request ID → no movement exists yet → maker approval
gets 403 → checker approves → one movement and one approval audit event → replay
with the same key returns the same result → new key gets 409 → checker rejects a
second receipt and no movement is posted. The approval audit event carries the
HTTP `X-Request-ID` for correlation with the checker action. IDs longer than
the audit column's 64-character limit are stored as SHA-256 digests, which the
demo also tests. The AI branch is the deterministic fallback, visibly labelled
`heuristic_fallback`; it is not a live LLM test.

## Interview questions

**Solution Architect**

1. *Why a modular monolith?* One PostgreSQL transaction owns request state,
   movement, audit and outbox. Separate services would add distributed
   consistency before the tea-shop workload requires it. Extraction needs a
   proven independent scaling/ownership boundary.
2. *What happens if the worker or SSE bus fails after approval?* The business
   commit stands; the outbox is stored in the transaction. UI notification may
   lag, so a client must read canonical request state. Multi-replica SSE has not
   been proven.

**AI Engineer**

1. *Can the model approve stock?* No. The assessment endpoint is advisory;
   FastAPI checks actor, state, scope, stock and PIN policy when a separate
   human approval request arrives.
2. *Does the audit stamp prove the voucher?* No. It hashes assessment inputs
   supplied by the client. The durable approval audit event is written by the
   transactional business route. Canonical binding of the AI input is a P1 gap.

**Backend/Platform**

1. *What prevents double posting?* The row is locked, final state is checked,
   a same-key retry replays, and a new key after posting gets 409. The demo
   checks that only one movement and one approval audit event exist.
2. *How is FEFO enforced?* Outbound logic locks lot balances and orders by
   earliest expiry, excluding expired lots for sale. The behavior is covered by
   the FEFO tests; physical shelf handling remains an operational process.

## Verification record

- Baseline before edits: HEAD `c9b6935`; three pre-existing modified files
  listed above. Concurrent local commits advanced HEAD through `d53c092` to
  `5d79314364739e48cd589604d56764583d963286`; those commits include B2 and
  S9 serving/CI/evidence changes. This audit does not claim authorship of them.
  No cloud service was contacted by the demo.
- `scripts/demo_ai_checker.sh`: **1 passed, 3 warnings** on a fresh local
  PostgreSQL database after migration to `027_idempotency_keys` (2026-10-21).
- Full backend suite on isolated PostgreSQL: first run **673 passed, 7 skipped,
  1 xfailed, 1 failed** after a transient connection error in a cash-capability
  test. That exact test passed in isolation. A second full run completed
  **674 passed, 7 skipped, 1 xfailed** in 239.88 s. The final long-request-ID
  handling was then covered by a fresh `scripts/demo_ai_checker.sh` run.
- After concurrent S9 commits advanced HEAD to `5d79314`, an isolated-DB
  full run initially showed: **653 passed, 21 failed, 7 skipped, 1 xfailed**.
  All 21 failures were MLflow/inference tests encountering
  `OSError: [Errno 30] Read-only file system: '/data'`. Commit `05ecc2e` had
  changed the host default to `sqlite:////data/mlflow.db` and pinned MLflow's
  global registry URI, while `test_mlflow_tracking.py` deleted SQLite files on
  fixture teardown without restoring `mlflow.set_tracking_uri()`, poisoning
  downstream tests.
  Both issues were remediated: `app/api/inference.py` falls back to writable
  local directories when `/data` is read-only, and `test_mlflow_tracking.py`
  restores prior tracking URI state.
  Additionally, two P1 security/reliability gaps were resolved:
  1. `POST /ai/assess-request` binds directly to canonical PostgreSQL voucher records
     (`canonical_bound=True`, `request_version`), eliminating reliance on client-forged inputs.
  2. `GET /audit-events` implements keyset pagination on `(occurred_at, id)`.
- **Full backend suite rerun on clean PostgreSQL**: **677 passed, 7 skipped, 1 xfailed**
  in 396.65 s (0:06:36) (2026-10-21). Zero failures.
- `flutter analyze`: **no issues**. Focused approvals/voucher Flutter tests:
  **12 passed**. `ruff check` on changed Python files, `bash -n` on the demo
  script and `git diff --check`: **pass**. Historical totals in `AGENTS.md`
  and `tasks/current.md` belong to earlier revisions.
