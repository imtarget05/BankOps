# Phase 0 Baseline
## Status: Complete

### Phase 0 Completed (2026-10-14)
- Full codebase audit complete (FastAPI, Worker, Flutter, Docker, CI/CD, AI infra)
- Git history scan: no leaked secrets in tracked files
- ADR 0001 written: FastAPI = sole business API, Worker = deprecated
- scripts/check_no_secrets.py: PASS

## Phase 1 - Implementation
### Status: Complete

#### Completed
1. `frontend/lib/src/features/auth/auth_service.dart` — removed dead `bankops-api.tanmainguyenbinh.pages.dev` fallback; release web requires `API_BASE_URL` (`normalizeApiBaseUrl` appends `/api/v1`).
2. `scripts/create_admin.py` - NEON_DATABASE_URL from env var, password required arg
3. `docs/15-security-deploy-checklist.md` - fake cfut_WtI4hAp3 reference removed
4. Worker business routes - stripped (`index.ts` health-only + `410 Gone` for `/api/v1/*`)
5. `wrangler.toml` - DEPRECATED comments for AI/KV bindings; bindings/vars pruned
6. `backend/app/seed.py` — **idempotent upsert** of missing roles/caps/mappings (root cause of 54 test failures); now 19 caps / 39 user-capability pairs
7. `backend/app/api/routes/auth.py` — `HTTP_422_UNPROCESSABLE_CONTENT` → `HTTP_422_UNPROCESSABLE_ENTITY` (4 sites)
8. `backend/tests/test_acceptance_qa.py` — I1/I2 issue-more-than-balance expects 409 at `/submit`
9. Test baseline on fresh DB: **232 passed / 0 failed / 1 skipped / 1 xfailed**

#### Deployment (2026-10-14) — chi tiết ở `docs/qa/06-deployment-validation.md`
- **Neon**: dùng lại project `BankOps`, branch `br-quiet-surf-b34t5lwu`, migrate `009`→`014` (39 tables), seed; snapshot rollback `snap-aged-sun-b38mjspm`
- **FastAPI**: deploy lên Modal — `https://imtarget05--bankops-api-api.us-east.modal.run` (`infra/modal/tea_inventory_api.py`, alias backward-compat: `infra/modal/bankops_api.py`)
- **Flutter Web**: build với API base Modal, deploy Cloudflare Pages `bankops-web` (production branch `main`)
- **CI**: `deploy-pages.yml` / `deploy.yml` đã trỏ về URL Modal; bỏ bước deploy Worker

### Pending / cần quyết định
- **Worker archive deploy — QUYẾT ĐỊNH 2026-10-14: chưa deploy, giữ Worker cũ sống** (fallback cho mobile build cũ đang trỏ `workers.dev`). Bản archive đã sẵn sàng, deploy sau khi mobile chuyển sang Modal.
- FastAPI staging riêng (hiện staging dùng chung backend Modal + Pages branch `staging` = preview)
