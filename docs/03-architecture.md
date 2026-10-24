# 03 — Kiến trúc modular monolith (Gate B Update)

## C4 Context Diagram (Gate B)

```mermaid
flowchart LR
    %% External actors
    F[Flutter Mobile/Web] -->|HTTPS/REST + SSE| API[FastAPI API — canonical (SHA c0c6032)]
    U[UAT / Integration Test Harness] -->|HTTPS/REST| API
    M[Manual Tester] -->|HTTPS/REST| API
    
    %% Internal services
    API --> IAM[Identity/RBAC — IAM users, roles, scope grants]
    API --> INV[Inventory — items, lots, stock levels, stocktakes]
    API --> CASH[Cash Simulation — cash_sim journal, reconciliations]
    API --> INT[Integration Hub — outbox, events, sandbox external services]
    API --> ACT[Activity — audit trail, shift counts, reports]
    API --> DASH[Dashboard — summary, exceptions, reconciliation views]
    
    %% Data store
    INV --> DB[(PostgreSQL 16 — single cluster, branch-scoped)]
    CASH --> DB
    IAM --> DB
    INT --> DB
    ACT --> DB
    DASH --> DB
    
    %% Outbox / worker
    API --> OUT[Transactional Outbox — same txn as API writes]
    OUT --> W[Background Worker — Celery/RQ, at-least-once, idempotent consumer]
    W --> DB
    W --> EXT[Sandbox External Services — email, payment gateways, third-party APIs]
    
    %% Cross-cutting
    API --> LOG[Structured Logging — JSON, app/core/logger.py]
    API --> METRICS[Prometheus Metrics — inventory ops, request latency, error rates]
    
    %% Style
    classDef api fill:#e3f2fd,stroke:#1976d2,stroke-width:2px;
    classDef db fill:#fff3e0,stroke:#fb8c00,stroke-width:2px;
    classDef worker fill:#e8f5e9,stroke:#388e3c,stroke-width:2px;
    classDef external fill:#f3e5f5,stroke:#8e24aa,stroke-width:2px;
    class API,API api;
    class DB db;
    class W worker;
    class EXT external;
```

## Module Boundaries (Gate B)

```
backend/app/
  api/              # FastAPI routes, controllers (inventory, cash_sim, approvals, integrations, activity, auth, admin)
  core/             # Config, security, exceptions, logger, metrics
  modules/
    identity/       # IAM users, roles, role_capabilities, scope_grants
    inventory/      # items, lots, stock_levels, stocktakes, adjustments, returns
    cash_sim/       # cash_requests, journals, reconciliations
    approvals/      # maker-checker workflow, approve/reject, idempotency
    integrations/   # outbox, external service adapters
    jobs/           # background tasks, retries, job leases
    activity/       # audit trail, shift counts, reports
    reporting/      # dashboard views, summary exceptions
  db/               # SQLAlchemy models, session, engine
alembic/
  versions/         # 28 migrations (v001..v028_reconcile_scope)
tests/
  backend/          # pytest unit + integration
  e2e/             # full business journey E2E (test_business_journey_full.py)
```

## Key Decisions (ADRs)

| ADR | Title | Status | relevance to Gate B |
|-----|-------|--------|---------------------|
| **0001** | Canonical API Policy — FastAPI as Single Business API | Accepted | ✅ Defines FastAPI as the only business API; Cloudflare Worker is legacy proxy only |
| **0002** | AI Governance, Advisory Boundaries & MLOps Justification | Accepted & Code-Verified | ✅ Nonfunctional targets: AI advisory limit 30% of inventory ops; human-in-the-loop for all policy changes |
| **0003** | AI/ML Component Review & Justification | Accepted & Code-Verified | ✅ Removes unjustified AI/ML components; keeps only core business correctness |
| **0004** | CONVERT Follow-ups — Drift Detection Wiring & Model Promotion Consolidation | Accepted & Implemented | ✅ Ensures drift detection is wired; model promotion consolidated under ADR 0002 |
| **0005** | Branch Scoping Decision for Inventory Locations | Accepted | ✅ Role × branch × status access matrix; `_require_location_scope` enforcement |
| **0006** | Idempotency Design for Inventory Requests | Accepted | ✅ Durable idempotency store (DB + in-memory); `Idempotency-Key` replay semantics |
| **B-xx** | **Business Journey E2E** | **Gate B Draft** | ✅ Full arc: receipt → FEFO issue → stocktake → adjustment → Maker-Checker → idempotency |
| **B-xx** | **Security Matrix — Role × Branch × Status** | **Gate B Draft** | ✅ Negative cross-branch tests; 404 NOT_FOUND for out-of-scope access |
| **B-xx** | **Migration Drill & Checksum Verification** | **Gate B Draft** | ✅ Snapshot + checksum + restore procedure; tied to release SHA c0c6032 |

## Nonfunctional Targets (Gate B)

| Target | Value | Measurement |
|--------|-------|-------------|
| **API latency (p95)** | < 500 ms | `hey -n 100 -c 10 https://api.quanlykho.test/inventory/items` |
| **DB connection pool** | max 20, min 5 | SQLAlchemy `pool_size` / `max_overflow` config |
| **Idempotency key retention** | 30 days (configurable via `idempotency_key_retention_hours`) | `idempotency_keys.expires_at` TTL |
| **Branch scope check overhead** | < 5 ms per request | `get_accessible_location_ids()` query time |
| **Backup/restore RTO** | < 15 min | `neon_restore_snapshot` with `finalize: true` |
| **Backup/restore RPO** | < 5 min | Data checksum drift threshold (0 mismatched rows) |
| **AI advisory participation** | ≤ 30% of inventory decision ops | Human-in-the-loop audit log count / total inventory ops |
| **Audit trail completeness** | 100% of write ops | `audit.log` entries / total DB write operations |

## Failure Modes (Gate B)

| Failure Mode | Root Cause | Impact | Mitigation |
|-------------|------------|--------|------------|
| **FM-001**: Cross-branch data leak | `_require_location_scope` misconfigured or bypassed | Makers see other branch's inventory | Enforce scope check at every entry point; automated regression test (TC-SEC-001 to TC-SEC-006) |
| **FM-002**: Idempotency key collision | Same key used for different business intents (replay attack) | Duplicate or conflicting state | 409 Conflict on same key + different payload (ADR 0006) |
| **FM-003**: Migration drift after rollback | Manual ALTER TABLE not tracked by Alembic | Schema divergence, broken downgrade paths | Use `alembic revision --autogenerate` after any manual change; follow migration drill (05-migration-drill.md) |
| **FM-004**: AI advisory overrride without human review | AI advisory > 30% threshold bypassed | Incorrect inventory decisions | Human-in-the-loop gate; all AI advisory decisions logged and require manual confirmation |
| **FM-005**: Shift stocktake lock not released | `STOCKTAKE_LOCKED` state not cleared on crash | No further stocktakes possible until manual reset | Auto-clear lock after 24h + manual `reset_postgres_role_password` path; test recovery (test_3 in business journey) |
| **FM-006**: Expired lot issued via FEFO bypass | Lot expiry validation skipped in sale flow | Customer receives expired product | 422 EXPIRED_LOT validation on all receipts; FEFO order enforced in outbound logic |
| **FM-007**: Maker-Checker race condition | Both checkers approve same request concurrently | Duplicate approval, inconsistent state | Idempotency key on approve; DB unique constraint; 409 on re-approve of final state |
| **FM-008**: Pagination blindness (balances) | Single GET /inventory/balances shows only first page | "Invisible" balances beyond page 1 | Use `fetch_all_balances()` cursor pagination helper; documented in conftest.py |
| **FM-009**: Enum type drift (userstatus) | Enum created but not tracked in migration order | `DuplicateObject` on `alembic upgrade head` | Always `alembic upgrade head` in order; never skip migrations; use `make test-backend` for fresh DB |

## Release Tie-In

All Gate B deliverables are tied to **QuanLyKho release SHA `c0c6032`** and **OpsBridge SHA `d5725a1`**:

- **Business journey E2E** (`tests/test_business_journey_full.py`): Validates the full arc end-to-end against this SHA.
- **Security matrix** (`docs/04-security-matrix.md`: Documents the role × branch × status access control model for this SHA.
- **Migration drill** (`docs/05-migration-drill.md`: Snapshot/checksum/restore procedure tied to this SHA.
- **Architecture docs** (`docs/03-architecture.md`, `docs/adr/`: All updated to reflect decisions and trade-offs for this SHA.

---
*Document generated as part of Gate B deliverable. Current revision: c0c6032 (QuanLyKho), d5725a1 (OpsBridge).*