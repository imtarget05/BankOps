 # QA 06 — Deployment Validation
 
 ## Security
 
 ### Secrets Scan
 ```bash
 python3 scripts/check_no_secrets.py
 ```
 **Result**: ✅ PASS — "Secret guard passed: no known credential patterns in tracked files."
 
 ### Git History Secret Scan
 ```bash
 git log --all -p | grep -iE '(api[_-]?key|secret|password|token|BEGIN.*PRIVATE)'
 ```
 **Result**: ✅ PASS — No actual secrets found. Only false positives:
 - `DEMO_PASSWORD = "DemoPass123!"` — test fixture password (not a real secret)
 - `lease_token` — database column name
 - Documentation references to secrets
 
 ## Docker Compose
 
 ### Config Validation
 ```bash
 docker compose config
 ```
 **Result**: ✅ PASS — Exit code 0, valid configuration
 
 ### Build
 ```bash
 docker compose build
 ```
 **Result**: ✅ PASS — Both `bankops-api` and `bankops-worker` images built successfully
 
 ### Container Health
 ```bash
 docker compose up -d
 docker compose ps
 ```
 **Result**: ✅ PASS — All 4 containers healthy/running
 
 | Container | Status |
 |-----------|--------|
 | bankops-frontend | Running |
 | bankops-db | Healthy |
 | bankops-api | Healthy |
 | bankops-worker | Started |
 
 ## Backup/Restore
 
 ### Backup
 ```bash
 docker exec bankops-db pg_dump -U bankops bankops > qa_backup.sql
 ```
 **Result**: ✅ PASS — Backup completed successfully
 
 ### Restore Verification
- [x] Restore to fresh container — container tạm `bankops-restore-verify` (`postgres:16-alpine`, :5434), nạp từ `pg_dump` 731 KB
- [x] Re-run acceptance tests — **19 passed** trên DB vừa restore (`tests/test_acceptance_qa.py`, :5434)
- [x] Verify data integrity — **0 mismatch** trên 11 bảng chính (iam_users 22, inv_items 9, inv_requests 202, audit_events 500, cash_journals 60…); 39/39 bảng; alembic rev `014_etl_pipeline_models` khớp
 
 ## Health & Readiness Probes
 
 | Endpoint | Method | Result |
 |----------|--------|--------|
 | `/health/live` | GET | ✅ 200 `{"status":"alive"}` |
 | `/health/ready` | GET | ✅ 200 `{"status":"ready","database":"ready"}` |
 
 ## Post-Deploy Smoke Test
 
 | Step | Result |
 |------|--------|
 | Login as demo_maker → 200, valid JWT | ✅ PASS |
 | GET `/inventory/items` → 200, 5 items | ✅ PASS |
 | GET `/cash-sim/balances` → 200, Decimal amounts | ✅ PASS |
 | GET `/audit-events` as maker → 403 `FORBIDDEN` | ✅ PASS (RBAC enforced) |
 
 ## CI/CD
 
 - [x] GitHub Actions workflow verified (CI runs)
 - [x] Lint check: `ruff check backend/` = All checks passed
 - [ ] Type check: `mypy backend/` = No errors — ⚠️ **CHƯA CHẠY 2026-10-14**: `mypy` không có trong môi trường verify; theo dõi qua xfail `test_mypy_strict_passes` (~481 lỗi annotate, 27 file). Cố ý để trống.
 
 ## Summary
 
 All deployment validation checks **PASS**:
 - ✅ No secrets in tracked files or git history
 - ✅ Docker Compose config valid and builds successfully
 - ✅ All containers healthy
 - ✅ Backup/restore available
 - ✅ Health/readiness probes return 200
 - ✅ Post-deploy smoke test passes
 
 ## Cloud Deployment — FastAPI (Modal) + Neon + Cloudflare Pages
 
 **Ngày deploy**: 2026-10-14 · **Topology**: Cloudflare Pages (Flutter Web) → FastAPI trên Modal → Neon Postgres.
 Worker (legacy) đã archive trong source, **không deploy** (ADR-0001 Phase 2).
 
 ### Targets
 
 | Component | Provider | Identifier / URL | Status |
 |-----------|----------|------------------|--------|
 | Backend API | Modal | app `bankops-api` / fn `api` — `https://imtarget05--bankops-api-api.us-east.modal.run` | ✅ Deployed |
 | Frontend Web | Cloudflare Pages | project `bankops-web` — `https://bankops-web.pages.dev` | ✅ Production |
 | Frontend (alias) | Cloudflare Pages | `https://qa-validation-20261014.bankops-web.pages.dev` | ✅ Preview/alias |
 | Database | Neon Postgres 16 | project `BankOps` (`divine-meadow-83331783`), branch `br-quiet-surf-b34t5lwu` | ✅ 39 tables, alembic `014` |
 | Rollback point | Neon snapshot | `snap-aged-sun-b38mjspm` (`pre-fastapi-deploy-20261014`) | ✅ Available |
 | Legacy API | Cloudflare Workers | `bankops-api.tanmainguyenbinh.workers.dev` (mã cũ) | ⚠️ Vẫn chạy bản cũ — **giữ nguyên** (quyết định 2026-10-14) |
 
 ### Backend (Modal) — smoke tests
 
 | Check | Result |
 |-------|--------|
 | `GET /api/v1/health/live` | ✅ 200 `{"status":"alive"}` (cold start ~27s) |
 | `GET /api/v1/health/ready` | ✅ 200 `database: ready` |
 | `POST /api/v1/auth/login` (`demo_admin` / `DemoPass123!`) | ✅ 200 — JWT ~948 bytes |
 | `GET /api/v1/openapi.json` | ✅ 101 paths |
 | CORS preflight từ `https://bankops-web.pages.dev` | ✅ 200 + `allow-origin` + `allow-credentials: true` |
 | CORS trên POST login thật (không chỉ preflight) | ✅ `access-control-allow-origin: https://bankops-web.pages.dev` |
 
 ### Authenticated business endpoints (qua Modal, Origin production)
 
 | Endpoint | Result |
 |----------|--------|
 | `/api/v1/me` | ✅ 200 |
 | `/api/v1/inventory/items` | ✅ 200 (5 items) |
 | `/api/v1/inventory/locations` | ✅ 200 |
 | `/api/v1/inventory/stock-levels` | ✅ 200 |
 | `/api/v1/cash-sim/boxes` | ✅ 200 (3 boxes) |
 | `/api/v1/approvals/inbox` | ✅ 200 |
 | `/api/v1/activity` | ✅ 200 |
 | `/api/v1/admin/users` | ✅ 200 |
 | `/api/v1/etl/pipelines` | ✅ 200 |
 | `/api/v1/reconciliations` | ✅ 200 |
 
 ### Frontend (Cloudflare Pages)
 
 | Check | Result |
 |-------|--------|
 | `GET /` (production) | ✅ 200, title đúng |
 | `GET /main.dart.js` | ✅ 200 (~4.8 MB) |
 | `GET /flutter_bootstrap.js`, `/_redirects` | ✅ 200 |
 | API base baked vào bundle production | ✅ `https://imtarget05--bankops-api-api.us-east.modal.run/api/v1` |
 | Không còn host chết/legacy trong bundle | ✅ 0 tham chiếu `bankops-api.tanmainguyenbinh.*` |
 
 > **Pitfall đã gặp**: `wrangler pages deploy` **không có `--branch`** sẽ lấy branch Git hiện tại
 > (`qa-validation-20261014`) và tạo bản **preview**; `bankops-web.pages.dev` (branch `main`) vẫn phục vụ
 > bản cũ. Lần deploy đầu rơi vào bẫy này. Đã fix bằng `--branch=main` + thêm cờ này vào các workflow.
 
 ### Data (Neon, sau seed)
 
 | Entity | Count |
 |--------|-------|
 | Capabilities | 19 |
 | User-capability pairs | 39 |
 | Users | 12 |
 | Inventory items | 5 |
 | Cash boxes | 3 |
 
 ### CI/CD
 
 | Workflow | Trạng thái |
 |----------|-----------|
 | `.github/workflows/deploy-pages.yml` | ✅ Build web với URL Modal, deploy Pages `--branch=main`, có smoke test |
 | `.github/workflows/deploy.yml` | ✅ Đã bỏ bước deploy Worker; URL chuyển sang Modal |
 | `.github/workflows/deploy-worker.yml` | ✅ Validate-only (không bao giờ deploy Worker) |
 
 ### Rủi ro còn lại / rollback
 
 - **JWT signing key**: `BANKOPS_SIGNING_KEY` đã set trong Modal secret; nếu chưa set, app dùng key
   ngẫu nhiên mỗi cold start ⇒ token cũ invalid. **Đã set** ⇒ OK.
 - **Cold start**: container scale-to-zero (`scaledown_window=300`) ⇒ request đầu sau idle ~27s.
 - **Rollback DB**: restore snapshot `snap-aged-sun-b38mjspm`.
 - **Rollback frontend**: `wrangler pages deployment list --project-name=bankops-web` rồi rollback về
   deployment trước (`d844798f-38f1-434c-a53c-8f134f1c4dbc`).
- **Legacy Worker**: **quyết định 2026-10-14 = giữ nguyên bản cũ đang chạy**, không deploy bản archive
  (health-only + `410 Gone`). Lý do: mobile build cũ vẫn trỏ `workers.dev`; frontend production đã trỏ Modal
  nên không ảnh hưởng. Bản archive đã sửa + verify local, sẵn sàng deploy khi mobile chuyển sang Modal.
  Khi đó rollback: `wrangler deployments list` → `wrangler rollback`.

### Bổ sung tối 2026-10-14 — deploy alias QA + smoke/E2E độc lập (track QA)

Build từ branch `qa-validation-20261014` (3 commits: `f9c16ec` backend QA fixes, `4c13475`
flutter RadioGroup, `90a6327` snapshot). Không động production.

| Check | Result |
|-------|--------|
| `modal deploy infra/modal/bankops_api.py` | ✅ Không đổi mã — URL giữ nguyên `https://imtarget05--bankops-api-api.us-east.modal.run` |
| `GET /health/live` (Modal, cold start) | ✅ 200 `{"status":"alive"}` |
| `GET /health/ready` | ✅ 200 `database: ready` (Neon đã migrate) |
| `GET /api/v1/openapi.json` | ✅ 200 |
| Login `demo_maker` → JWT 536 ký tự | ✅ 200 |
| `GET /inventory/items`, `/inventory/balances`, `/activity` | ✅ 200, 200, 200 |
| `GET /audit-events` (maker) | ✅ 403 (RBAC đúng) |
| E2E maker→checker live: create → submit 200 → approve → `posted` | ✅ PASS |
| `flutter build web --dart-define=API_BASE_URL=<modal>/api/v1` | ✅ Built |
| `wrangler pages deploy --project-name=bankops-web` (branch alias) | ✅ `https://qa-validation-20261014.bankops-web.pages.dev` 200, title đúng |
| Production `bankops-web.pages.dev` | ✅ Không đụng (giữ bản production của track deploy) |

### Bổ sung tối 2026-10-14 — production redeploy trực tiếp (user lệnh "làm ngay")

CI `deploy-pages.yml` vẫn đỏ vì repo **0 secret** (`gh secret list` trống; không có
environment nào) — không trigger run hỏng thêm. Deploy production bằng local build
đã verify + `wrangler pages deploy --branch=main` (wrangler OAuth đã login).

| Check | Result |
|-------|--------|
| `flutter build web --release --dart-define=API_BASE_URL=https://imtarget05--bankops-api-api.us-east.modal.run/api/v1 --dart-define=APP_ENV=production` | ✅ Built 33s |
| Bundle kiểm tra trước deploy | ✅ Có Modal URL, 0 tham chiếu `bankops-api.tanmainguyenbinh.*` |
| `wrangler pages deploy --project-name=bankops-web --branch=main` | ✅ Deployment `f432a664` |
| Production `GET /` | ✅ 200, title đúng |
| Production `main.dart.js` (~4.9 MB) | ✅ Có Modal `/api/v1`, 0 legacy ref |
| CORS preflight từ production origin tới Modal | ✅ 200 + `allow-origin: bankops-web.pages.dev` + credentials |
| Rollback | `wrangler pages deployment list --project-name=bankops-web` → rollback về deployment trước nếu cần |

### Bổ sung 2026-10-15 ~00:35Z — CI đỏ (token/account mismatch) + production redeploy local

- `gh secret set` đủ 4 secrets (3 tự động + `CLOUDFLARE_API_TOKEN` do owner dán qua chat —
  **coi như lộ, phải rotate**, xem cuối).
- CI `deploy-pages.yml` run `38660046086` + `38660373388`: secrets-check PASS, Flutter
  analyze/test/build PASS, nhưng deploy step 7003 `Could not route to
  /accounts/{id}/pages/projects/bankops-web` — lặp lại sau khi reset
  `CLOUDFLARE_ACCOUNT_ID` đúng account `8788…e1b3c` ⇒ token không thuộc account này
  hoặc thiếu scope Pages. CI còn đỏ cho tới khi token đúng.
- Production deploy trực tiếp (OAuth local, đã verify): `flutter test +80 pass`,
  `analyze` sạch, rebuild release, `wrangler pages deploy --branch=main` →
  deployment `df43cb6d`. Verify production: `/` 200, `main.dart.js` có Modal URL +
  0 legacy ref, API `/health/ready` 200.
- ⚠️ **Hành động bắt buộc**: revoke token đã dán qua chat (Settings → API Tokens →
  delete), tạo token mới đúng account + scope Pages:Edit, cập nhật GH secret
  `CLOUDFLARE_API_TOKEN`, re-run workflow để CI xanh lại.
