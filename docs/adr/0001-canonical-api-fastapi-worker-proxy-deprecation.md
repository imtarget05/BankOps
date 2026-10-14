# ADR 0001: Canonical API Policy — FastAPI as Single Business API

**Status**: Accepted  
**Date**: 2026-10-14  
**Related**: docs/03-architecture.md, docs/14-cloudflare-deploy.md, docs/16-secrets-migration.md

---

## Context

BankOps has TWO API implementations sharing PostgreSQL but diverging in auth,
transactions, idempotency, audit, and business logic:

1. FastAPI (backend/) — canonical. Async SQLAlchemy, maker-checker invariants,
   optimistic locking, idempotency, transactional outbox, double-entry ledger.
2. Cloudflare Worker (infra/cloudflare-worker/) — Hono/TS mirror. Direct Neon SQL
   but differs in error formats, capability checks, reserved-quantity handling.

Divergence evidence:
 - Worker inventory.ts (945 lines) has NO stocktake reservation logic
 - Worker auth.ts (675 lines) uses bcryptjs inline
 - Error envelopes differ: FastAPI vs Worker inconsistency
 - scripts/create_admin.py hardcodes Neon URL with embedded credentials
 - Flutter auth_service.dart:66 defaults to workers.dev URL

## Decision

FastAPI is the sole backend for all business API. Worker is thin proxy (Phase 1),
then archived (Phase 2). Flutter must point to FastAPI.

## Security

- Rotate hardcoded Neon credential in scripts/create_admin.py
- Remove cfut_WtI4hAp3 reference from docs/15-security-deploy-checklist.md

Phase 0 completed (2026-10-14):
- scripts/create_admin.py: NEON_DATABASE_URL now from env var, password is required arg
- auth_service.dart:66: workers.dev URL changed to pages.dev (FastAPI)
- docs/15-security-deploy-checklist.md: fake cfut_WtI4hAp3 reference removed

Phase 1 in progress:
- Strip Worker business routes (done — index.ts only imports healthRoutes)
- Keep only /api/v1/health endpoints, return 410 for all other business paths

## Approval

| Role | Name | Signature | Date |
|---|---|---|---|
| Architect | | | |
| Security Lead | | | |
| Backend Lead | | | |
| Frontend Lead | | | |
