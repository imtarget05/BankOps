# Gate B: Migration Upgrade / Rollback / Forward Path

## Current State
- **Migration head**: `028_reconcile_scope` (rev: `027_idempotency_keys`)
- **Total migrations**: 28 (v001_initial through v028_reconcile_scope)
- **Branch**: QuanLyKho (SHA `c0c6032`)
- **OpsBridge**: Separate repo with its own migration chain

## Upgrade Path (Forward)

To upgrade from the current head to the latest applied migration (already at head), no forward steps are needed. The upgrade path is:

```
Current: 028_reconcile_scope
↑ (already at head)
No further upgrades needed.
```

If new migrations are added in the future, the standard Alembic upgrade command applies:

```bash
poetry run alembic upgrade head   # upgrades to latest
poetry run alembic upgrade <rev>  # upgrades to specific revision
```

### Verifying a Clean Upgrade
After running `alembic upgrade head`, validate the schema:

```bash
poetry run alembic heads          # show current head(s)
poetry run alembic current        # show current revision
```

## Rollback Path (Backward)

To roll back to a previous migration, use `alembic downgrade <rev>`. This is **destructive** in the sense that it removes schema elements added after the target revision. Always backup the database before rolling back.

### Rollback Scenarios

| Target | Command | Effect |
|--------|---------|--------|
| **Rollback to v027** (idempotency_keys) | `poetry run alembic downgrade 027_idempotency_keys` | Drops `idempotency_keys` table; idempotency reverts to in-memory only (R1 behavior) |
| **Rollback to v026** (schema_alignment) | `poetry run alembic downgrade 026_schema_alignment` | Drops columns added by v027 and v028 (cashbox_id, location_id, resolved on reconciliation_exceptions) |
| **Rollback to v020** (sync_requests) | `poetry run alembic downgrade 020_sync_requests` | Removes sync_requests table, related columns; reverts branch-id isolation |
| **Rollback to v016** (tea_receipt_lot_expiry) | `poetry run alembic downgrade 016_tea_receipt_lot_expiry` | Removes lot/expiry guard on receipts; removes single-open shift constraint |

### Verifying Rollback Integrity
After a rollback, run these checks:

```bash
# 1. Verify table state matches target revision
poetry run alembic heads
poetry run alembic current

# 2. Run smoke test: ensure app still boots
poetry run uvicorn app.main:app --host 0.0.0.0 --port 8000 &

# 3. Key business logic checks
# - Idempotency keys stored in DB? (yes if ≥ v027, no if < v027)
# - Reconciliation exceptions have scope columns? (yes if ≥ v028, no if < v028)
# - Branch scoping active? (yes if ≥ v013, no if < v013)
```

## Forward Fix / Forward-Compatible Changes

If a rollback is needed but forward-fix is preferred (preserve data, add missing columns):

### Scenario: Rollback v028 → v027, then re-apply v028 fix

1. **Rollback to v027**:
   ```bash
   poetry run alembic downgrade 027_idempotency_keys
   ```

2. **Manual forward fix**: If `reconciliation_exceptions` table lost `cashbox_id`, `location_id`, `resolved` columns, re-add them:
   ```bash
   poetry run alembic revision --autogenerate -m "Add scope columns to reconciliation_exceptions"
   # Review the generated migration, then:
   poetry run alembic upgrade head
   ```

3. **Verify**:
   ```bash
   poetry run alembic current  # should be head again
   ```

### Important: Never mix manual SQL with Alembic
All schema changes must go through Alemcic revision files. Manual `ALTER TABLE` commands are tracked separately and can cause drift. Use `alembic revision --autogenerate` after any manual change to record the drift.

## Migration Checksum / Restore Drill

As part of Gate B, a **backup/restore drill** must be performed to verify migration integrity. The drill consists of:

### Step 1: Snapshot the current branch
```bash
# Create a snapshot from the current branch
neon_create_snapshot \
  --project_id <project_id> \
  --branch_id <br-branch-id> \
  --name "pre-migration-v028-snapshot"
```

### Step 2: Record checksums of critical tables
Before any migration, record row counts and checksums:

```sql
-- Example checksum queries
SELECT count(*) as item_count, md5(string_agg(::text, '|' ORDER BY id)) as item_checksum FROM inv_items;
SELECT count(*) as bal_count, md5(string_agg(::text, '|' ORDER BY item_id || quantity)::text) as bal_checksum FROM inv_balances;
SELECT count(*) as req_count from inventory_requests;
SELECT count(*) as exc_count from reconciliation_exceptions;
```

### Step 3: Apply/rollback migration
```bash
# To apply (if not already at head):
poetry run alembic upgrade head

# To rollback to v027:
poetry run alembic downgrade 027_idempotency_keys
```

### Step 4: Verify checksums match
After the migration/rollback, re-run the same checksum queries. The checksums should match the pre-migration values captured in Step 2. **If they differ, the migration caused data mutation and requires investigation.**

### Step 5: Finalize — restore from snapshot if needed
```bash
# If rollback caused unwanted changes, restore from snapshot:
neon_restore_snapshot \
  --project_id <project_id> \
  --snapshot_id <snapshot-id> \
  --name "QuanLyKho-post-v028-restore" \
  --finalize true
```

### Drill Checklist

| # | Step | Description | Pass Criteria |
|---|------|-------------|---------------|
| 1 | Snapshot | Create branch snapshot before migration | Snapshot created, ID recorded |
| 2 | Checksum | Record row counts + MD5 checksums of critical tables | Checksums saved to `gate-b-checksums.txt` |
| 3 | Migrate | Run `alembic upgrade head` or `downgrade <rev>` | Command completes without error |
| 4 | Verify | Re-run checksum queries | All checksums match pre-migration values ✅ |
| 5 | Restore (optional) | `neon_restore_snapshot` if checksums don't match | Snapshot restored, data intact |

---
*Document generated as part of Gate B deliverable. Tied to release SHA: QuanLyKho c0c6032.*