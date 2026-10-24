# ADR 0005: Branch Scoping Decision for Inventory Locations

**Status**: Accepted  
**Date**: 2026-10-23  
**Related**: docs/03-architecture.md, docs/06-api.md  

## Context

In BankOps, inventory locations (kho) must be scoped to users based on their branch membership. The question is how to enforce this scoping at the API level while maintaining usability for makers, checkers, and auditors across different branches.

## Decision

Locations are scoped to users via `branch_id` in the `iam_users` table and validated at API query time through `get_accessible_location_ids()`. The logic is:

1. **Admin / System Admin**: Has access to all locations (`return None`)
2. **Other roles**: Access is limited to:
   - Locations belonging to their `branch_id`
   - Locations granted via `iam_scope_grants` (per-user/per-branch overrides)

This decision was made because:
- Centralized RBAC in `iam_scope_grants` provides fine-grained control without schema changes
- Branch-based filtering is the primary ownership model for inventory (each branch owns its stock)
- Auditors need cross-branch visibility for reconciliation, but makers/checkers are branch-bound

## Consequences

**Pros**:
- Clean separation of concerns — scoping logic lives in a single reusable function
- Admins can grant temporary cross-branch access via scope grants without modifying user records
- Matches the existing `branch_id` pattern used throughout the system

**Cons**:
- Requires explicit scope grant setup for cross-branch access (easy to forget)
- Query-time filtering adds a small overhead, but is negligible compared to DB latency

## Alternatives Considered

| Approach | Description | Why Not Chosen |
|----------|-------------|----------------|
| Hard `branch_id` filter in every query | Embed `Location.branch_id = user.branch_id` in every repository method | Too repetitive, error-prone, cannot grant ad-hoc cross-branch access |
| Separate location tables per branch | `inv_locations_bbbb`, `inv_locations_cccc` etc. | Anti-pattern — too many tables, violates single source of truth |
| Role-based location pools | Pre-defined sets of locations per role (e.g. "auditor-can-see-all") | Inflexible — cannot add new locations without role redefinition |

## ADR References

- **0001**: Canonical API Policy — FastAPI as the single source of truth for all business APIs
- **03**: Architecture modular monolith — module boundaries and data flow

---

# ADR 0006: Idempotency Design for Inventory Requests

**Status**: Accepted  
**Date**: 2026-10-23  
**Related**: docs/03-architecture.md, docs/06-api.md  

## Context

Inventory request creation (`POST /inventory/requests`) must be idempotent — sending the same payload twice must produce the same result without duplicate entries. This is critical for preventing duplicate receipts, adjustments, and transfers caused by network retries or UI double-submits.

## Decision

Idempotency is implemented via a client-supplied `Idempotency-Key` header. The key follows this flow:

1. **Request 1** (new key): 
   - `_require_key()` extracts the key from headers (400 if missing)
   - `_replay()` checks in-memory store `_store`, then durable DB store `idempotency_keys`
   - No existing entry → `_durable_claim()` inserts a new row with `status_code=NULL`, `response_body=NULL`
   - Route creates the inventory request, then `remember()` stores `(status, body)` in both `_store` and `idempotency_keys` after transaction commit

2. **Request 2** (same key, same payload):
   - `_replay()` finds the cached `(status, body)` → returns 200 with same response
   - **Same key, different payload** → raises `IdempotencyConflict` (409) to prevent partial updates

3. **Request 2** (same key, different payload after partial processing):
   - The system deliberately rejects this with 409 to maintain data integrity

## Key Design Details

- **Key format**: UUID string (e.g., `550e8400-e29b-41d4-a716-446655440000`)
- **Hash canonicalization**: `payload_hash()` uses `json.dumps(payload, sort_keys=True, default=str)` to ensure consistent hashing regardless of key order
- **Durable store**: `idempotency_keys` table persists keys across restarts; in-memory `_store` provides fast path
- **`remember()`**: Called after transaction commit to ensure the stored result survives process restarts
- **Conflict detection**: If the same key is used with a modified payload, the system returns 409 instead of silently overwriting or creating a new resource

## Consequences

**Pros**:
- Client-controlled — no need for server-generated keys or session affinity
- Standards-compatible — follows idempotency best practices (RFC 7231)
- Dual-store approach (memory + PostgreSQL) gives both speed and durability
- Clear conflict semantics: same key + same payload = replay; same key + different payload = 409

**Cons**:
- Client must remember to include the key on every retry
- If the key is lost, the idempotency benefit is lost (but the operation can be retried)
- The 409 on different payloads might surprise clients not expecting this behavior

## Alternatives Considered

| Approach | Description | Why Not Chosen |
|----------|-------------|----------------|
| Server-generated keys (auto-UUID) | Server generates and returns the idempotency key | Breaks client control; harder to correlate with user intent; requires extra API round-trip |
| Hash-based keys (hash of payload) | Key = `sha256(payload)` | Difficult to invalidate/revoke; if payload changes slightly, key changes → no replay benefit |
| Two-phase commit (claim then submit) | Client claims key first, then submits request | Overly complex for a simple HTTP API; adds round-trip latency; not needed since we use client-supplied keys |

## Approval

| Role | Name | Signature | Date |
|------|------|-----------|------|
| Architect | | | |
| Backend Lead | | | |
| QA Lead | | | |

---