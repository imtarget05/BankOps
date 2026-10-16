 # QA 04 — UI QA by Role
 
 ## Status
 
 **Flutter SDK**: Not available in QA environment
 **Web build**: Available at `frontend/dist/`
 
 ## UI QA Coverage
 
 ### Role Matrix
 
 | Role | Capabilities | UI Paths Tested | Status |
 |------|-------------|-----------------|--------|
 | **Maker** | `inventory:create_request`, `cash:create_request` | Create draft → submit → denied approve (403) | ⏳ Pending (no Flutter SDK) |
 | **Checker** | `inventory:approve`, `cash:approve` | View approval inbox → approve → 200 posted | ⏳ Pending (no Flutter SDK) |
 | **Auditor** | `audit:view`, `inventory:view_balances` | Audit log read-only, no sensitive export | ⏳ Pending (no Flutter SDK) |
 | **Staff** | `inventory:view_balances`, `cash:view_balances` | Read-only views, no write buttons | ⏳ Pending (no Flutter SDK) |
 
 ### Responsive Design
 
 | Breakpoint | Status |
 |------------|--------|
 | 320px (mobile) | ⏳ Pending |
 | 768px (tablet) | ⏳ Pending |
 | 1024px (desktop) | ⏳ Pending |
 | 1440px (desktop wide) | ⏳ Pending |
 
 ### UI States
 
 | State | Status |
 |-------|--------|
 | Loading (skeleton/spinner) | ⏳ Pending |
 | Error (4xx/5xx envelope) | ⏳ Pending |
 | Empty (no data messaging) | ⏳ Pending |
 | Demo watermark | ⏳ Pending |
 
 ### Export
 
 | Feature | Status |
 |---------|--------|
 | CSV export | ⏳ Pending |
 | Excel export | ⏳ Pending |
 | Formula injection prevention | ⏳ Pending |
 
 ## Mitigation
 
 Since Flutter SDK is not available in the QA environment:
 1. Web build verified to exist at `frontend/dist/`
 2. Web build served via Docker Compose `frontend-web` container (nginx:alpine)
 3. Browser-based smoke test can be performed via browser console
 4. Full widget/golden tests require Flutter SDK — documented as limitation
 
 ## Web Build Smoke Test
 
 ```bash
 # Verify web build is served correctly
 curl -s http://localhost:8080/ | head -20
 # Expected: HTML with BankOps app shell
 ```
 
 ## Limitation
 
 Flutter SDK is **not installed** in the QA environment. Widget tests, golden tests, and device simulation cannot be executed. This limitation is documented and should be addressed in CI pipeline.