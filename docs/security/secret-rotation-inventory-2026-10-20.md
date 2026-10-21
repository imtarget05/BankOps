# Secret Rotation Inventory — BankOps / QuanLyKho (2026-10-20)

**Owner:** chủ tài khoản (Cloudflare / Gmail / GitHub) + SRE/ops
**Scope:** 5 credential P0/P1 bắt buộc rotate + 3 credential P1/P3 đi kèm
**Trạng thái:** `ROTATED-PARTIAL` — **2026-10-21 (DECISION 3)**: 4 credential đã
rotate + đã có bằng chứng token cũ chết; 3 credential **cần chủ tài khoản**
(Gmail app password, Cloudflare API token, GPG passphrase) — giá trị cũ đã được
**gỡ khỏi đĩa** (placeholder), nhưng **credential cũ ở provider chưa chết**.
Xem §0 (bảng trạng thái) và §5 (bằng chứng).

> **Quy tắc bắt buộc**
> - File này **không** chứa giá trị secret. Chỉ chứa *fingerprint*.
> - Fingerprint = `<4 ký tự đầu>…(len=<độ dài>, sha256=<8 hex>)`.
> - **Ngoại lệ (quan trọng):** `SUPERVISOR_PIN` là PIN 6 chữ số → `sha256[:8]` của nó
>   **brute-force được trong vài micro-giây** → công bố hash đó *tương đương công bố PIN*.
>   Vì vậy fingerprint **mới** của `SUPERVISOR_PIN` phải ghi ở dạng **salted**
>   (`sha256(salt + value)[:8]`, salt do owner giữ ngoài repo, đặt qua
>   `ROTATION_FINGERPRINT_SALT`). Xem `scripts/verify_secret_rotation.py`.
> - Mọi bước xác minh so **fingerprint**, không so giá trị.

---

## 0. Trạng thái sau wave rotation 2026-10-21 (DECISION 3)

Không có giá trị secret nào được ghi trong bảng này — chỉ fingerprint.

| Credential | Trạng thái | Nơi đã cập nhật | Fingerprint mới | Bằng chứng |
|---|---|---|---|---|
| `BANKOPS_SIGNING_KEY` | **ROTATED + VERIFIED** | `backend/.env:37` (`BANKOPS_dev_signing_key`), `infra/k8s/base/secret-production.yaml:19`, GH secret `BANKOPS_SIGNING_KEY` | `73b8…(len=64, sha256=b348ebd0)` | token ký bằng key cũ → `GET /api/v1/auth/me` = **401** (cả key dev cũ lẫn `SECRET_KEY` legacy cũ); `POST /api/v1/auth/login` = **200** với key mới |
| `BANKOPS_SESSION_SECRET` | **ROTATED + VERIFIED** | `backend/.env:18`, `infra/k8s/base/secret-production.yaml:20`, GH secret `BANKOPS_SESSION_SECRET` | `7Qx3…(len=64, sha256=4f456353)` | `settings.session_secret` khớp fingerprint mới; app khởi động OK; login 200 (không có session server-side nên không có session nào bị invalidate) |
| `SECRET_KEY` (legacy) | **TÊN ĐÃ GỠ (2026-10-21)** — xem ghi chú bên dưới | **đã gỡ 2026-10-21**: GH secret `SECRET_KEY` (`gh secret delete SECRET_KEY`) + k8s `infra/k8s/base/secret-production.yaml` (dòng `SECRET_KEY` đã xoá) · **còn lại**: `.env.production:4` (chưa gỡ) | `3c96…(len=64, sha256=dc5064b5)` (giá trị đã rotate 2026-10-21; **tên** đã gỡ ở 2/3 vị trí) | token ký bằng `SECRET_KEY` cũ → **401** |
| `SUPERVISOR_PIN` | **ROTATED** | `.env.production:5`, `infra/k8s/base/secret-production.yaml:12`, GH secret `SUPERVISOR_PIN` | `salted(len=6, sha256=4ab63689)` | PIN demo `123456` **chỉ** dùng khi `settings.is_demo_mode` (`backend/app/services/approval_controls.py:57`, `backend/app/seed.py:225`) |
| `SMTP_PASSWORD` | **CẦN OWNER — app password cũ VẪN LOGIN ĐƯỢC** | giá trị cũ đã gỡ: `.env:21` + `backend/.env:26` → `CHANGE_ME_SMTP_PASSWORD` | — | Probe SMTP (`--check-provider`, `SMTP_OLD_PASSWORD`): **old app password STILL LOGS IN** ⇒ credential đã lộ công khai **vẫn còn hiệu lực** ở Google → owner phải xoá ở `https://myaccount.google.com/apppasswords` |
| `CLOUDFLARE_API_TOKEN` | **CẦN OWNER** (token cũ **còn sống**) | giá trị cũ đã gỡ khỏi `.env:7`, `.env.production:10`, `backend/.env:31`, `infra/k8s/base/secret-production.yaml:14` | — | `GET /user/tokens/verify` (token cũ) = **200 / status `active`**; `GET /user/tokens` = **403**; `DELETE /user/tokens/{id}` = **403 (code 9109 Unauthorized)** ⇒ token **không tự revoke được** |
| `BACKUP_GPG_PASSPHRASE` | **CẦN OWNER** | giá trị cũ đã gỡ: `.env.production:20`, `infra/k8s/base/secret-production.yaml:18` | — | không thể verify tự động (cần keyring + backup cũ để re-encrypt) |
| `DATABASE_URL` (dev) | **CHƯA ROTATE** (P3, ngoài scope wave này) | — | — | quyết định owner: chỉ rotate khi DB dev có dữ liệu thật |

> **Ghi chú `SECRET_KEY` (legacy).** Kế hoạch ban đầu (2026-10-20) đặt end state là
> **remove** (gỡ hẳn tên biến). DECISION 3 (2026-10-21) chọn phương án **giữ tên
> nhưng đổi giá trị** ở wave này, vì shim `backend/entrypoint.sh:10-14` vẫn còn
> (`SECRET_KEY` → `BANKOPS_SIGNING_KEY`) và việc gỡ tên phải đi kèm PR gỡ shim
> (runbook mục 11 #17 / mục 12 #25). Vì vậy `end_state` của `legacy_secret_key`
> trong khối JSON bên dưới đổi `remove` → `rotate`; **gỡ hẳn tên** vẫn là
> hạng mục mở (xem §6 bảng "còn lại cần owner").
> **⟵ ĐÃ ĐẢO NGƯỢC LẠI `remove` ngày 2026-10-21** (xem cập nhật ngay bên dưới).
>
> **Cập nhật 2026-10-21 (gỡ tên legacy).** Shim `backend/entrypoint.sh` **đã** được
> gỡ ở wave code-hygiene (§0.1: production/staging → **FAIL-FAST** nếu thiếu
> `BANKOPS_SIGNING_KEY`), nên rào chặn của DECISION 3 **không còn**. Vì vậy
> `end_state` của `legacy_secret_key` trong khối JSON **đã đổi ngược lại `remove`**,
> và **tên** `SECRET_KEY` đã bị gỡ ở **2/3** vị trí:
> - **GitHub Actions secret** `SECRET_KEY` → **đã xoá** (`gh secret delete SECRET_KEY --repo imtarget05/QuanLyKho`, 2026-10-21; xác nhận bằng `gh secret list` — không còn tên này).
> - **k8s Secret** `infra/k8s/base/secret-production.yaml` → **đã gỡ** dòng `SECRET_KEY` (2026-10-21; file gitignored, **không** commit). File này **đã** có `BANKOPS_SIGNING_KEY` ⇒ deploy mới không gãy.
> - **Còn lại:** `.env.production:4` (file local gitignored — **ngoài phạm vi** thay đổi 2026-10-21) và **Secret đang chạy** trên cluster (`kubectl -n bankops-prod patch secret bankops-secrets …`), cần owner xử lý.
>
> Vì `end_state = remove`, `--check-env` giờ **FAIL** ở vị trí `.env.production`
> (legacy var vẫn còn) — đây là **tín hiệu đúng** (tên legacy chưa gỡ xong),
> không phải hồi quy. Chi tiết hạng mục còn mở: §6.1 #3.
>
> **Hazard cần lưu ý:** hiện có **hai** giá trị khác nhau cho cùng một vai trò
> (`BANKOPS_SIGNING_KEY` ≠ `SECRET_KEY`). Ở production, `entrypoint.sh` ưu tiên
> `BANKOPS_SIGNING_KEY`; nếu một môi trường chỉ set `SECRET_KEY` thì key ký JWT
> sẽ **khác** ⇒ token ký bằng key canonical bị từ chối. Sửa dứt điểm: gỡ shim
> + gỡ tên `SECRET_KEY` (PR riêng) hoặc đặt `SECRET_KEY` = `BANKOPS_SIGNING_KEY`.

---

## 0.1 Wave code-hygiene 2026-10-21 (agent đã làm)

Phần **code-side** của vòng hygiene secrets đã hoàn tất trên nhánh
`merge/g2-20261020` (commit `fix(secrets): gate default supervisor PIN, remove
legacy signing key fallback, complete secret templates`):

| Hạng mục | Kết quả |
|---|---|
| Default supervisor PIN khi admin tạo user | Đã **gate** theo `settings.is_demo_mode`; ngoài demo mode `pin_hash = None` |
| Shim legacy `SECRET_KEY → BANKOPS_SIGNING_KEY` | Đã gỡ fallback âm thầm: production/staging ⇒ **FAIL-FAST**; demo/dev/test ⇒ fallback **kèm cảnh báo lớn** |
| Template + `.env.example` | Đủ key chuẩn (placeholder) + ghi rõ `SECRET_KEY` là **DEPRECATED** |
| `scripts/setup_secrets_and_deploy.sh` | Ghi đủ key chuẩn, `--from-env`, không in giá trị, **không ghi đè file** khi thiếu biến bắt buộc |
| `scripts/sync_github_secrets.sh` | Chỉ in **tên** biến, đủ 4 biến chuẩn, không sync `SECRET_KEY` |
| GitHub secret scanning + push protection | **Đã bật** cho `imtarget05/QuanLyKho` và `imtarget05/AKS-SRE-Platform` (`imtarget05/OpsBridge` → 404, không tồn tại) |

**Trạng thái cổng secrets gate: vẫn FAIL** — 3 credential còn sống ở provider và
chỉ chủ tài khoản mới gỡ được: `SMTP_PASSWORD` (Gmail app password), 
`CLOUDFLARE_API_TOKEN`, `BACKUP_GPG_PASSPHRASE`. Chi tiết:
`docs/security/credential-rotation-runbook.md` §13.

---

## 1. Bảng tổng hợp

| # | Credential (tên chuẩn) | Fingerprint **hiện tại** | Nơi đang dùng (chính) | Lộ công khai? | Ưu tiên | End state |
|---|---|---|---|---|---|---|
| 1 | `BANKOPS_SIGNING_KEY` (JWT signing key) | ~~`iK6K…(len=64, sha256=96557a63)`~~ → **`73b8…(len=64, sha256=b348ebd0)`** (đã rotate 2026-10-21) | `backend/.env:37` (`BANKOPS_dev_signing_key`), `backend/app/config.py:213,218,237`, `backend/app/api/routes/auth_utils.py:71,380,389,445,609` | Không | **P0** | rotate |
| 2 | `SECRET_KEY` (tên legacy của #1 ở tầng deploy) | ~~`9e7c…(len=64, sha256=e9649e5a)`~~ → **`3c96…(len=64, sha256=dc5064b5)`** (đã rotate 2026-10-21) — **tên đã gỡ 2026-10-21** ở GH secret + k8s Secret manifest | **đã gỡ**: GH secret `SECRET_KEY`, `infra/k8s/base/secret-production.yaml` · **còn**: `.env.production:4`, `backend/entrypoint.sh:10-14` (shim đã gỡ ở wave code-hygiene) | Không | **P0** | **remove** |
| 3 | `BANKOPS_SESSION_SECRET` | ~~`rvK4…(len=64, sha256=f00d82ab)`~~ → **`7Qx3…(len=64, sha256=4f456353)`** (đã rotate 2026-10-21) | `backend/.env:18`, `backend/app/config.py:201-210` (**không có consumer thật**) | Không | **P0** | rotate |
| 4 | `SMTP_PASSWORD` (Gmail app password) | ~~`qavo…(len=16, sha256=8e2b3b9b)`~~ — **CẦN OWNER**; giá trị cũ đã gỡ khỏi đĩa 2026-10-21 | `.env:21`, `backend/.env:26`, `backend/app/config.py:138`, `render.yaml:34` | **CÓ** — `docker-compose.yml` @ `53be143` (còn ở `origin/main`) | **P0** | rotate |
| 5 | `SUPERVISOR_PIN` | ~~**giá trị đã công khai** (`len=6`, `sha256=8d969eef`)~~ → **`salted(len=6, sha256=4ab63689)`** (đã rotate 2026-10-21) | `.env.production:5`, `infra/k8s/base/secret-production.yaml:12`, `backend/app/config.py:162`, `backend/app/services/approval_controls.py:56-60` | **CÓ** — `infra/k8s/base/secret-template.yaml` @ `e76419b`,`bea0922`; `README.md` @ `5602ef0`,`310551a` | **P1** | rotate |
| 6 | `CLOUDFLARE_API_TOKEN` | ~~`cfut…(len=53, sha256=a9d3b0e0)`~~ — **CẦN OWNER** (token cũ còn active); giá trị cũ đã gỡ khỏi đĩa 2026-10-21 | `.env:7`, `.env.production:10`, `backend/.env:31`, `infra/k8s/base/secret-production.yaml:14`, `.github/workflows/deploy.yml:82,134`, `deploy-pages.yml:32` | Không (chỉ mẫu `cfut_…` trong docs) | **P1** | rotate |
| 7 | `BACKUP_GPG_PASSPHRASE` | ~~`qwfb…(len=32, sha256=6a2bee79)`~~ — **CẦN OWNER**; giá trị cũ đã gỡ khỏi đĩa 2026-10-21 | `.env.production:20`, `infra/k8s/base/secret-production.yaml:18`, `infra/k8s/base/cronjob-backup.yaml:27-31` | Không | **P1** | rotate |
| 8 | `DATABASE_URL` (dev Postgres) | `post…(len=59, sha256=3d4d0275)` | `.env:3`, `.env.production:3`, `backend/.env:3`, `scripts/setup_secrets_and_deploy.sh:108,110` | Có (dev credential, 29 commit) | P3 | rotate |

**Định danh chuẩn (sau rotation chỉ được dùng tên cột "canonical"):**

| Canonical var | Store chuẩn | Consumer path sau rotation | Tên legacy phải dọn |
|---|---|---|---|
| `BANKOPS_SIGNING_KEY` | GitHub Actions secret `BANKOPS_SIGNING_KEY` + k8s Secret key `BANKOPS_SIGNING_KEY` | `config.py:213` → `settings.signing_key` → ký/verify JWT | `SECRET_KEY` (shim `entrypoint.sh:10`), `BANKOPS_dev_signing_key` (`JWT_SIGNING_KEY_REF`) |
| `BANKOPS_SESSION_SECRET` | GitHub Actions secret + k8s Secret key `BANKOPS_SESSION_SECRET` | `config.py:201` `settings.session_secret` (xem ghi chú "không có consumer") | — |
| `SMTP_PASSWORD` | GitHub Actions secret + k8s Secret key `SMTP_PASSWORD` + Render dashboard secret | `config.py:138` → `email_service.py` | — |
| `SUPERVISOR_PIN` | GitHub Actions secret + k8s Secret key `SUPERVISOR_PIN` | `config.py:162` → `approval_controls.py:56-60` | `wrangler secret put SUPERVISOR_PIN` (Worker **không** đọc biến này) |
| `CLOUDFLARE_API_TOKEN` | GitHub Actions secret | `deploy.yml:82,134`, `deploy-pages.yml:32` | — |
| `BACKUP_GPG_PASSPHRASE` | GitHub Actions secret + k8s Secret key | `cronjob-backup.yaml:27-31` | — |

---

## 2. Chi tiết từng credential

### 2.1 `BANKOPS_SIGNING_KEY` — JWT signing key (P0)

| Trường | Nội dung |
|---|---|
| Fingerprint hiện tại | `iK6K…(len=64, sha256=96557a63)` |
| Nơi đang dùng | `backend/.env:37` (`BANKOPS_dev_signing_key`); `backend/app/config.py:213` (`_signing_key_from_env`), `:218` (`signing_key`), `:237` (`assert_runtime_secrets` → fail-fast); `backend/app/api/routes/auth_utils.py:71,380,389,445,609`; `backend/app/api/routes/auth.py:397`; `backend/entrypoint.sh:10-14` (shim từ `SECRET_KEY`); `render.yaml:22` (`generateValue: true`) |
| CI secret | `BANKOPS_SIGNING_KEY` (GitHub Actions) — hiện **chưa** được `scripts/sync_github_secrets.sh` sync |
| k8s secret ref | **THIẾU** — `infra/k8s/base/secret-template.yaml` chỉ có `SECRET_KEY` (dòng 14), `secret-production.yaml:11` chỉ có `SECRET_KEY` |
| Hardcoded default? | **KHÔNG** — `config.py:224,239` raise `RuntimeError` nếu thiếu ở non-demo. Nhưng có **shim** `entrypoint.sh:10-14` làm `SECRET_KEY` *trở thành* signing key ⇒ 2 tên cho 1 giá trị |
| Trạng thái | Chưa rotate, **chưa** lộ công khai (chỉ nằm ở file local gitignored) |
| **Cách tạo mới** | `python3 -c "import secrets; print(secrets.token_hex(32))"` → 64 ký tự hex, 256 bit entropy. Hoặc `openssl rand -hex 32` |
| **Cách cập nhật** | 1) `gh secret set BANKOPS_SIGNING_KEY --repo imtarget05/QuanLyKho` (dán giá trị, không truyền argv)<br>2) k8s: `kubectl -n bankops-prod create secret generic bankops-secrets --from-literal=BANKOPS_SIGNING_KEY="$NEW" --dry-run=client -o yaml \| kubectl apply -f -`<br>3) local: `backend/.env:37` → **đổi tên biến** thành `BANKOPS_SIGNING_KEY` (giữ nguyên giá trị mới)<br>4) `render.yaml:22` đã dùng đúng tên → không cần sửa |
| **Cách xác minh cũ đã chết** | `curl -sS -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $OLD_ACCESS_TOKEN" "$API_BASE_URL/api/v1/auth/me"` → **401** (token ký bằng key cũ phải bị từ chối). Hoặc `python3 scripts/verify_secret_rotation.py --check-provider` với `OLD_ACCESS_TOKEN` + `API_BASE_URL` |
| **Cách xác minh mới hoạt động** | Đăng nhập lại → token mới → `GET /api/v1/auth/me` → **200**; `--check-provider` với `NEW_ACCESS_TOKEN` → PASS |
| Rollback | Rollback **mã deploy** về bản cũ **và** đặt lại key cũ trong secret store. Hệ quả: token đã ký bằng key cũ sống lại (đánh đổi an toàn) — chỉ dùng khi sự cố triển khai, sau đó phải rotate lại |
| Ảnh hưởng nếu rotate sai | **Toàn bộ user phải đăng nhập lại**: access token (TTL 30 phút) + refresh token (TTL 7 ngày, `config.py:73`) đều không dùng được. Không có cửa sổ bảo toàn được — đây là hành vi đúng (mục tiêu là chặn forge). Cần thông báo cho user + giám sát tỷ lệ login lỗi sau deploy |

### 2.2 `SECRET_KEY` — tên legacy của signing key ở tầng deploy (P0, end state = **remove**)

| Trường | Nội dung |
|---|---|
| Fingerprint hiện tại | `9e7c…(len=64, sha256=e9649e5a)` |
| Nơi đang dùng | `.env.production:4` (**còn** — ngoài phạm vi 2026-10-21); `infra/k8s/base/secret-template.yaml:14` (placeholder `CHANGE_ME_…` — đúng, giữ nguyên theo §6.1 #18); `scripts/setup_secrets_and_deploy.sh` (`JWT_SEC` → `SECRET_KEY`); `scripts/sync_github_secrets.sh:50` (`gh secret set SECRET_KEY` — **không** sync nữa từ wave code-hygiene) · **đã gỡ 2026-10-21**: k8s `infra/k8s/base/secret-production.yaml` (dòng `SECRET_KEY` xoá) + GitHub Actions secret `SECRET_KEY` (`gh secret delete`) |
| Runtime consumer | **Không có code nào đọc `SECRET_KEY`** (`rg 'SECRET_KEY' backend/app/` → 0 kết quả). Nó chỉ được dùng **gián tiếp** qua shim `backend/entrypoint.sh:10-14` → `BANKOPS_SIGNING_KEY` |
| Hardcoded default? | **KHÔNG** (giá trị thật chỉ ở file local gitignored) |
| Trạng thái | Đã rotate 2026-10-21; **tên biến đã gỡ 2026-10-21** ở GH secret + k8s Secret manifest; còn `.env.production` + Secret đang chạy trên cluster |
| **Cách tạo mới** | Không tạo mới — biến này phải **bị gỡ**. (Nếu owner muốn giữ tên, giá trị mới = giá trị của `BANKOPS_SIGNING_KEY` mới, tuyệt đối khác giá trị cũ) |
| **Cách cập nhật** | 1) Xoá key `SECRET_KEY` khỏi k8s Secret: `kubectl -n bankops-prod patch secret bankops-secrets --type=json -p '[{"op":"remove","path":"/data/SECRET_KEY"}]'` — **MỞ** (cần owner; agent không có cluster)<br>1b) Xoá dòng `SECRET_KEY` khỏi manifest `infra/k8s/base/secret-production.yaml` — **ĐÃ XONG 2026-10-21** (file gitignored, **không** commit)<br>2) Xoá dòng `SECRET_KEY=` khỏi `.env.production` — **MỞ** (ngoài phạm vi thay đổi 2026-10-21)<br>3) `gh secret delete SECRET_KEY --repo imtarget05/QuanLyKho` — **ĐÃ XONG 2026-10-21** (xác nhận: `gh secret list` không còn tên này)<br>4) Gỡ shim ở `backend/entrypoint.sh:10-14` và dòng `set_secret "SECRET_KEY"` ở `scripts/sync_github_secrets.sh` — **ĐÃ XONG** (wave code-hygiene 2026-10-21: fallback âm thầm đã gỡ, script không sync `SECRET_KEY` nữa) |
| **Cách xác minh cũ đã chết** | Sau khi deploy lại với `BANKOPS_SIGNING_KEY` mới: token ký bằng `SECRET_KEY` cũ → `GET /api/v1/auth/me` → **401** |
| **Cách xác minh mới hoạt động** | Pod mới start không còn log `[Entrypoint] BANKOPS_SIGNING_KEY chưa set -> dùng SECRET_KEY …`; `/api/v1/health/live` → 200 |
| Rollback | Cần `SECRET_KEY` cũ để rollback deploy (nếu deploy cũ dùng shim). **Giữ lại giá trị cũ ở password manager cho tới khi deploy mới ổn định**, nhưng **không** đặt lại vào GitHub/k8s sau khi xác nhận |
| Ảnh hưởng nếu rotate sai | Nếu gỡ `SECRET_KEY` mà **chưa** thêm `BANKOPS_SIGNING_KEY` vào k8s Secret → `config.py:239` raise → **container không khởi động** (fail-closed, không lộ dữ liệu). Bắt buộc thêm key mới **trước**, gỡ key cũ **sau** |

### 2.3 `BANKOPS_SESSION_SECRET` (P0)

| Trường | Nội dung |
|---|---|
| Fingerprint hiện tại | `rvK4…(len=64, sha256=f00d82ab)` |
| Nơi đang dùng | `backend/.env:18`; `backend/app/config.py:201-210` (property `session_secret`) |
| Runtime consumer | ⚠️ **KHÔNG có consumer thật**: `backend/app/main.py` **không** mount `SessionMiddleware` (`rg 'SessionMiddleware' backend/app` → 0). Property `session_secret` chỉ được gọi trong test (`backend/tests/test_config_service.py:49,54,61,69`). Auth là **stateless JWT** |
| CI secret | **THIẾU** — `scripts/sync_github_secrets.sh` không sync biến này |
| k8s secret ref | **THIẾU** — không có trong `secret-template.yaml` / `secret-production.yaml` |
| Hardcoded default? | **KHÔNG** — `config.py:206-210` dùng secret **ephemeral** (`secrets.token_urlsafe(48)`, `config.py:26-29`) cho demo/test, raise `RuntimeError` ngoài demo/test |
| Trạng thái | Chưa rotate, chưa lộ công khai |
| **Cách tạo mới** | `python3 -c "import secrets; print(secrets.token_urlsafe(48))"` → ≥48 ký tự base64url, ≥256 bit |
| **Cách cập nhật** | `gh secret set BANKOPS_SESSION_SECRET --repo imtarget05/QuanLyKho`; k8s `create secret generic … --from-literal=BANKOPS_SESSION_SECRET="$NEW" --dry-run=client -o yaml \| kubectl apply -f -`; `backend/.env:18` |
| **Cách xác minh cũ đã chết** | Vì **không có session server-side**, rotate **không** làm mất session nào. Bằng chứng đúng là: (a) app vẫn khởi động ở `APP_ENV=production` với giá trị mới (không `RuntimeError`), (b) `/api/v1/auth/login` → 200, (c) `python3 scripts/verify_secret_rotation.py --check-env` → PASS cho `BANKOPS_SESSION_SECRET` |
| **Cách xác minh mới hoạt động** | `/api/v1/auth/login` → 200; `settings.session_secret` trả đúng giá trị mới (đối chiếu fingerprint) |
| Rollback | Đặt lại giá trị cũ trong secret store + rollback deploy |
| Ảnh hưởng nếu rotate sai | **Hiện tại: không ảnh hưởng** (dead property). **Rủi ro tương lai:** nếu ai đó mount lại `SessionMiddleware(secret_key=settings.session_secret)`, việc rotate sẽ **invalidate toàn bộ cookie session** → toàn bộ user phải đăng nhập lại. Nếu session được bật lại, cần **window bảo trì** (rotate trong giờ thấp điểm) hoặc chấp nhận đăng nhập lại |

### 2.4 `SMTP_PASSWORD` — Gmail app password (P0, **đã lộ công khai**)

| Trường | Nội dung |
|---|---|
| Fingerprint hiện tại | `qavo…(len=16, sha256=8e2b3b9b)` — ⚠️ 4 ký tự đầu đã bị công bố trong `docs/security/credential-rotation-runbook.md` (commit `bea0922`) → giảm entropy còn ~60 bit |
| Nơi đang dùng | `.env:21`, `backend/.env:26`; `backend/app/config.py:138-142`; `backend/app/services/email_service.py` (đọc `settings.smtp_password`); `render.yaml:34` (`sync: false` — dán tay trong Render dashboard) |
| CI secret | `SMTP_PASSWORD` — **THIẾU** (không có trong `sync_github_secrets.sh`) |
| k8s secret ref | **ĐÃ CÓ PLACEHOLDER (2026-10-21)** — `infra/k8s/base/secret-template.yaml` (tracked) có `SMTP_USER` + `SMTP_PASSWORD` (`CHANGE_ME_*`); manifest local `infra/k8s/base/secret-production.yaml` (gitignored) **đã bổ sung** `SMTP_USER: "CHANGE_ME_SMTP_USER"` + `SMTP_PASSWORD: "CHANGE_ME_SMTP_PASSWORD"` → `envFrom: bankops-secrets` **cấp được** key ⇒ không còn "thiếu key ⇒ mail hỏng". ⚠️ **Owner phải thay cả 2 giá trị** (Gmail app password mới) trước khi deploy — placeholder không gửi được mail |
| Hardcoded default? | **KHÔNG** ở code; **CÓ trong git history** — `docker-compose.yml` @ `53be143` (reachable từ `origin/main`), đã gỡ ở `90a6327` (xác minh bằng `git log -S`) |
| Trạng thái | **ĐÃ LỘ CÔNG KHAI** → coi như credential bị xâm nhập |
| **Cách tạo mới** | Google Account → **Security → 2-Step Verification → App passwords** → app name `bankops-mail-2026-10` → loại **Mail** → sinh **16 ký tự** (4 nhóm 4, bỏ khoảng trắng). Entropy ≈ 80 bit. **Không** dùng lại app password cũ dù nó còn "chạy" |
| **Cách cập nhật** | 1) `gh secret set SMTP_PASSWORD --repo imtarget05/QuanLyKho`<br>2) k8s: `kubectl -n bankops-prod create secret generic bankops-secrets --from-literal=SMTP_PASSWORD="$NEW" --dry-run=client -o yaml \| kubectl apply -f -` (kèm `SMTP_USER`, `SMTP_HOST`, `SMTP_PORT`)<br>3) Render dashboard: service `kho-tra-sua-fastapi` → Environment → `SMTP_PASSWORD` (dán tay)<br>4) local: `.env:21`, `backend/.env:26`<br>5) Worker Cloudflare **không** dùng SMTP → **không** `wrangler secret put` |
| **Cách xác minh cũ đã chết** | `python3 scripts/verify_secret_rotation.py --check-provider` với `SMTP_USER` + `SMTP_OLD_PASSWORD` → login SMTP **phải trả `535` (`5.7.8 Username and Password not accepted`)**. **Không gửi email thật.** Nếu vẫn login được ⇒ app password cũ **chưa** bị xoá |
| **Cách xác minh mới hoạt động** | Cùng lệnh với `SMTP_NEW_PASSWORD` → login **OK** (chỉ `AUTH`, không `sendmail`) |
| Rollback | **Không** dùng lại app password đã lộ. Nếu app password mới lỗi → tạo app password tạm thứ 2, cập nhật, xoá app password tạm sau khi ổn định |
| Ảnh hưởng nếu rotate sai | **User-facing outage**: OTP, email mời, email kích hoạt tài khoản (`email_service.py`) đều dừng. Nên **tạo app password mới → cấp → xác minh → mới xoá app password cũ** (Gmail cho phép nhiều app password cùng lúc) |

### 2.5 `SUPERVISOR_PIN` (P1, giá trị đã công khai)

| Trường | Nội dung |
|---|---|
| Fingerprint hiện tại | **KHÔNG dùng hash để đối chiếu** — giá trị này **trùng với PIN demo hardcode trong code** (`backend/app/services/approval_controls.py:11`), tức là đã công khai. Chỉ ghi `len=6` trong tài liệu. (Nếu cần đối chiếu máy, dùng `sha256` của giá trị demo, cũng vô nghĩa vì công khai) |
| Nơi đang dùng | `.env.production:5`; `infra/k8s/base/secret-production.yaml:12`; `backend/app/config.py:162` (`supervisor_pin: SecretStr` — pydantic-settings đọc env `SUPERVISOR_PIN`); `backend/app/services/approval_controls.py:56-60` (consumer thật) |
| CI secret | `SUPERVISOR_PIN` — **THIẾU** (không có trong `sync_github_secrets.sh`) |
| k8s secret ref | `infra/k8s/base/secret-template.yaml:15` → `CHANGE_ME_SUPERVISOR_PIN` (placeholder **đúng**) |
| **Hardcoded default? CÓ** | `backend/app/api/routes/admin_users.py:351` → `pin_hash=get_password_hash("123456")` — **gán cho MỌI user mới tạo qua admin, KHÔNG có gate demo** (khác `seed.py:220` và `auth.py:221` vốn đã gate theo `settings.is_demo_mode`). ⇒ Đây là **default yếu đang chạy ở production** nếu admin tạo user trên production. **Không sửa ở wave này** (file của worker khác) → đã báo cáo |
| Còn lại | `frontend/lib/src/data/repositories/fake_repository.dart:77`, `frontend/lib/src/features/auth/auth_service.dart:895` (còn chấp nhận password `'admin'`), `frontend/lib/src/features/approvals/approvals_screen.dart:125,1464`, `frontend/lib/src/features/auth/widgets/register_dialog.dart:30,91` → **PIN demo ở client**; `frontend/lib/src/features/auth/auth_service.dart:895` → fallback password `'admin'` trong fake repo (client-side, không phải credential server) |
| Trạng thái | Chưa rotate; **giá trị đã công khai** |
| **Cách tạo mới** | ⚠️ Ràng buộc: `backend/app/api/routes/auth.py:224-228` bắt buộc PIN **đúng 6 chữ số** → không thể chọn PIN mạnh hơn 10^6 (20 bit) nếu chưa sửa validation. Với 6 chữ số: dùng `python3 -c "import secrets; print(f'{secrets.randbelow(1000000):06d}')"`, **không** trùng PIN demo, **không** trùng PIN cũ. Bổ sung: rate-limit 5 lần/15 phút đã có (`approval_controls.py:16-17`) |
| **Cách cập nhật** | 1) `gh secret set SUPERVISOR_PIN --repo imtarget05/QuanLyKho`<br>2) k8s: `kubectl -n bankops-prod create secret generic bankops-secrets --from-literal=SUPERVISOR_PIN="$NEW" --dry-run=client -o yaml \| kubectl apply -f -`<br>3) `.env.production:5`, `infra/k8s/base/secret-production.yaml:12`<br>4) **KHÔNG** `wrangler secret put SUPERVISOR_PIN` — Worker không đọc biến này (dead secret). `infra/scripts/setup-neon.sh` đang làm vậy → **đề xuất bỏ** |
| **Cách xác minh cũ đã chết** | Gọi luồng duyệt 4-mắt với PIN cũ → **HTTP 403** `Mã PIN kiểm soát viên không đúng.` (`approval_controls.py:69`) |
| **Cách xác minh mới hoạt động** | Cùng luồng với PIN mới → **HTTP 200 / phiếu được duyệt** |
| Rollback | Đặt lại PIN cũ + rollback deploy (chỉ dùng khi sự cố triển khai, sau đó rotate lại) |
| Ảnh hưởng nếu rotate sai | **Nghiệp vụ bị chặn**: mọi phiếu cần duyệt 4-mắt sẽ fail 403 cho tới khi supervisor nhập PIN mới ⇒ cần **thông báo + window bảo trì** (ví dụ 30 phút giờ thấp điểm) và phân phối PIN mới ngoài repo/không qua chat log |
| **Ghi chú bằng chứng** | Fingerprint **mới** của PIN phải ghi ở dạng **salted** (xem đầu file). Hash thường của PIN 6 chữ số = công bố PIN |

### 2.6 `CLOUDFLARE_API_TOKEN` (P1)

| Trường | Nội dung |
|---|---|
| Fingerprint hiện tại | `cfut…(len=53, sha256=a9d3b0e0)` |
| Nơi đang dùng | `.env:7`, `.env.production:10`, `backend/.env:31`, `infra/k8s/base/secret-production.yaml:14`, `infra/k8s/base/secret-template.yaml:16` (placeholder đúng), `backend/app/config.py:151` (`cloudflare_api_token`), `.github/workflows/deploy.yml:82,134`, `.github/workflows/deploy-pages.yml:32`, `docker-compose.yml:37` |
| Hardcoded default? | **KHÔNG** |
| Trạng thái | Chưa rotate; **chưa** lộ công khai (`git log -S'cfut_'` chỉ khớp **mẫu** trong docs, không phải giá trị thật — đã xác minh bằng quét blob toàn bộ history) |
| **Cách tạo mới** | Cloudflare Dashboard → **My Profile → API Tokens → Create Token** → template **Edit Cloudflare Workers** (scope tối thiểu: `Workers Scripts: Edit` + `Pages: Edit` nếu deploy Pages). **Không** dùng Global API Key. Bật IP restriction nếu CI chạy từ IP cố định. Format `cfut_` + 49 ký tự |
| **Cách cập nhật** | `gh secret set CLOUDFLARE_API_TOKEN --repo imtarget05/QuanLyKho`; local `.env:7`, `.env.production:10`, `backend/.env:31`; k8s `secret-production.yaml:14` |
| **Cách xác minh cũ đã chết** | `GET https://api.cloudflare.com/client/v4/user/tokens/verify` với token cũ → **không phải 200** (Cloudflare trả **400** `code 1000 Invalid API Token`, hoặc 401/403). Script `--check-provider` (env `CLOUDFLARE_OLD_TOKEN`) |
| **Cách xác minh mới hoạt động** | Cùng endpoint với token mới → **200**; hoặc chạy thử 1 workflow deploy dry-run |
| Rollback | Token cũ **giữ sống** tới khi token mới verify OK rồi mới **Revoke** trên Dashboard (nếu cần rollback → tạo token mới thay vì hồi sinh token đã revoke) |
| Ảnh hưởng nếu rotate sai | Deploy Cloudflare/Pages + Workers AI (`config.py:248` fail-fast khi thiếu token ở `AI_PROVIDER=cloudflare`) → hỏng. Cần có **2 token sống song song** trong lúc cắt |

### 2.7 `BACKUP_GPG_PASSPHRASE` (P1)

| Trường | Nội dung |
|---|---|
| Fingerprint hiện tại | `qwfb…(len=32, sha256=6a2bee79)` |
| Nơi đang dùng | `.env.production:20`, `infra/k8s/base/secret-production.yaml:18`, `infra/k8s/base/secret-template.yaml:18` (placeholder đúng), `infra/k8s/base/cronjob-backup.yaml:27-31` (`envFrom: bankops-secrets`) |
| Hardcoded default? | **KHÔNG** |
| Trạng thái | Chưa rotate, chưa lộ công khai |
| **Cách tạo mới** | `python3 -c "import secrets; print(secrets.token_urlsafe(32))"` → ≥32 ký tự, ≥192 bit. Lưu trong password manager offline |
| **Cách cập nhật** | `gh secret set BACKUP_GPG_PASSPHRASE --repo imtarget05/QuanLyKho`; k8s `create secret generic … --from-literal=BACKUP_GPG_PASSPHRASE="$NEW" --dry-run=client -o yaml \| kubectl apply -f -`; `.env.production:20` |
| **Cách xác minh cũ đã chết** | `printf '%s' "$OLD" \| gpg --batch --passphrase-fd 0 --decrypt <backup_cu.gpg> >/dev/null` → **phải fail** (sai passphrase). ⚠️ passphrase cũ **phải giữ tạm** cho tới khi mọi backup cũ đã re-encrypt (xem rollback) |
| **Cách xác minh mới hoạt động** | `gpg --batch --passphrase-fd 0 --decrypt <backup_moi.gpg>` → OK; và CronJob backup chạy thành công |
| Rollback | Re-encrypt backup cũ bằng passphrase mới (`gpg --decrypt old \| gpg --encrypt --recipient <KEY_ID> > new`) **trước khi** xoá passphrase cũ. Không xoá passphrase cũ khi còn backup chưa re-encrypt |
| Ảnh hưởng nếu rotate sai | Mất khả năng khôi phục backup cũ ⇒ **rủi ro không hoàn tác được** ⇒ cần window + backup mirror trước khi xoá |

### 2.8 `DATABASE_URL` (P3 — dev credential)

| Trường | Nội dung |
|---|---|
| Fingerprint hiện tại | `post…(len=59, sha256=3d4d0275)` |
| Nơi đang dùng | `.env:3`, `.env.production:3`, `backend/.env:3`, `backend/app/config.py:64-68` (fallback dev URL), `scripts/setup_secrets_and_deploy.sh:108,110` |
| Hardcoded default? | **CÓ (dev-only, chấp nhận được):** `config.py:67` có fallback về DB Postgres **local** (`kho-tra-sua` user, mật khẩu dev tĩnh) — chỉ là credential DB **local**, không phải production |
| Trạng thái | Chưa rotate; giá trị dev đã nằm trong 29 commit (không phải credential production) |
| **Cách tạo mới** | `ALTER USER … WITH PASSWORD '<random 24+>'` trên DB dev; `python3 -c "import secrets; print(secrets.token_urlsafe(24))"` |
| **Cách cập nhật** | `.env:3`, `.env.production:3`, `backend/.env:3` |
| **Cách xác minh cũ đã chết** | `psql "…:5432/db" -c '\l'` bằng mật khẩu cũ → phải fail `password authentication failed` |
| **Cách xác minh mới hoạt động** | `alembic upgrade head` + `pytest backend/tests` với URL mới → pass |
| Rollback | `ALTER USER … WITH PASSWORD '<cũ>'` |
| Ảnh hưởng nếu rotate sai | Dev/CI local DB không truy cập được. **Chỉ rotate nếu DB dev có dữ liệu thật** |

---

## 3. Bảng exposure (bằng chứng "đã lộ")

Mức độ: **LOCAL** = chỉ trong file gitignored trên máy · **HISTORY** = nằm trong commit đã push lên `origin/main` · **TRACKED** = nằm trong file đang được track ở HEAD.

| Credential | Mức độ | Bằng chứng (commit / file) | Ghi chú |
|---|---|---|---|
| `SMTP_PASSWORD` | **HISTORY (công khai)** | `docker-compose.yml` @ `53be143` (thêm) → `90a6327` (gỡ). Cả hai reachable từ `origin/main` | Bằng chứng bằng `git log -S` + quét blob toàn bộ history. Cần rotate **trước**, rewrite **sau** |
| `SMTP_PASSWORD` (4 ký tự đầu) | **HISTORY** | `docs/security/credential-rotation-runbook.md` @ `bea0922` (reachable `origin/main`) | Chỉ 4/16 ký tự → entropy còn ~60 bit; vẫn nên rotate |
| `SUPERVISOR_PIN` | **HISTORY + TRACKED(đã gỡ)** | `infra/k8s/base/secret-template.yaml` @ `e76419b`, `bea0922` (giá trị thật; HEAD nay là `CHANGE_ME_…`) | reachable `origin/main` |
| `SUPERVISOR_PIN` | **HISTORY** | `README.md` @ `5602ef0`, `310551a`; `scripts/setup_secrets_and_deploy.sh` @ `af2157b`, `bea0922`; `infra/scripts/setup-neon.sh` @ `e6275a3` | reachable `origin/main` |
| `SUPERVISOR_PIN` | **TRACKED (demo constant)** | `backend/app/services/approval_controls.py:11` (`DEMO_SUPERVISOR_PIN`), `backend/app/seed.py:220`, `backend/app/api/routes/auth.py:221`, `frontend/lib/**` (nhiều file) | Giá trị demo — **không được dùng làm PIN production** |
| `SUPERVISOR_PIN` | **TRACKED — default không gate (NGUY HIỂM)** | `backend/app/api/routes/admin_users.py:351` `pin_hash=get_password_hash(<PIN demo>)` cho **mọi user mới tạo qua admin**, không gate demo | Cần fix code (worker khác) |
| `BANKOPS_SIGNING_KEY` | LOCAL | `backend/.env:37` (gitignored) | Chưa lộ |
| `SECRET_KEY` | LOCAL | `.env.production:4`, `infra/k8s/base/secret-production.yaml:11` (gitignored) | Chưa lộ |
| `BANKOPS_SESSION_SECRET` | LOCAL | `backend/.env:18` (gitignored) | Chưa lộ |
| `CLOUDFLARE_API_TOKEN` | LOCAL | `.env:7`, `.env.production:10`, `backend/.env:31`, `infra/k8s/base/secret-production.yaml:14` | Chưa lộ (docs chỉ có **mẫu** `cfut_…`) |
| `BACKUP_GPG_PASSPHRASE` | LOCAL | `.env.production:20`, `infra/k8s/base/secret-production.yaml:18` | Chưa lộ |
| `DATABASE_URL` (dev) | HISTORY + TRACKED(dev) | 29 commit; `config.py:67` fallback | Dev-only |
| `SUPERVISOR_PIN` | HISTORY | `f5be287`, `35e6e6b` (docs/16-secrets-migration.md) | **KHÔNG** reachable từ `origin/main` (nhánh cục bộ) → chỉ cần rewrite nếu còn nhánh đó được push |

**Đề xuất rewrite history (KHÔNG tự thực hiện — cần phê duyệt riêng):**

| Mục tiêu | Công cụ | Rủi ro |
|---|---|---|
| Xoá `SMTP_PASSWORD` khỏi `docker-compose.yml` trong mọi commit | `git filter-repo --path docker-compose.yml --invert-paths` (xoá hẳn file) hoặc `--replace-text` (thay đúng giá trị) | Mất commit của người khác nếu filter bịa; cần `git push --force --mirror` ⇒ **mọi clone phải `fetch && reset --hard`**; PR cũ mất context; **phải rotate trước** (rewrite không làm credential chết) |
| Xoá giá trị PIN trong `secret-template.yaml`, `README.md`, `setup_secrets_and_deploy.sh`, `setup-neon.sh` | `git filter-repo --replace-text <file-replacements>` | Như trên + phải giữ `DEMO_SUPERVISOR_PIN` trong code (là demo constant, không phải secret) |
| Bật GitHub secret scanning + push protection | **Owner**: `https://github.com/imtarget05/QuanLyKho/settings/security_analysis` (bật *Secret scanning*) và `https://github.com/imtarget05/QuanLyKho/settings/security_analysis/push_protection` (bật *Push protection*) | Push protection chặn commit chứa secret ⇒ cần allowlist cho `scripts/check_no_secrets.py` + `backend/tests/test_check_no_secrets.py` (chúng chứa pattern/fixture giả) |

---

## 4. Lệch giữa "tên biến" và "nơi lưu" (nguyên nhân incident)

| Vấn đề | Bằng chứng | Hậu quả | Consumer chuẩn sau rotation |
|---|---|---|---|
| Tầng deploy chỉ có `SECRET_KEY`, code đọc `BANKOPS_SIGNING_KEY` | `infra/k8s/base/secret-template.yaml:14` vs `backend/app/config.py:213` | Dùng **shim** `backend/entrypoint.sh:10-14` → 2 tên, 1 giá trị; rotate 1 bên ⇒ bên kia vẫn cũ | k8s Secret có **cả** `BANKOPS_SIGNING_KEY`; gỡ `SECRET_KEY` |
| `BANKOPS_SESSION_SECRET` **không có** trong k8s Secret | `secret-template.yaml` không có key này | `config.py:206-210` raise khi property được dùng | thêm key `BANKOPS_SESSION_SECRET` |
| `SMTP_PASSWORD` **không có** trong k8s Secret | `secret-template.yaml` không có | `envFrom` không cấp → gửi mail lỗi | thêm key `SMTP_PASSWORD` (+ `SMTP_USER/HOST/PORT`) |
| `SUPERVISOR_PIN` được `wrangler secret put` nhưng Worker **không đọc** | `infra/scripts/setup-neon.sh` vs `infra/cloudflare-worker/src/index.ts` (không có `SUPERVISOR_PIN`) | Tạo cảm giác an toàn giả; secret thừa trên Cloudflare | Bỏ `wrangler secret put SUPERVISOR_PIN`; PIN chỉ ở FastAPI |
| `scripts/sync_github_secrets.sh` **in ra giá trị secret** khi `gh` chưa cài | `scripts/sync_github_secrets.sh` (nhánh fallback trước `exit 0`) | Lộ giá trị ra terminal/log CI | Sửa nhánh fallback chỉ in **tên** biến (file của worker khác → đã báo cáo) |
| `scripts/sync_github_secrets.sh` không sync 4 secret mới | `BANKOPS_SIGNING_KEY`, `BANKOPS_SESSION_SECRET`, `SMTP_PASSWORD`, `SUPERVISOR_PIN` | CI deploy dùng secret cũ/không có | Bổ sung `set_secret` cho 4 biến trên (worker khác → đã báo cáo) |
| `render.yaml` có `BANKOPS_SIGNING_KEY`/`BANKOPS_SESSION_SECRET` `generateValue: true` | `render.yaml:22,25` | Render sinh giá trị **riêng**, không đồng bộ với k8s/GitHub ⇒ 3 bản key khác nhau | Một nguồn sự thật (GitHub Actions secret) + copy tới từng store |
| `backend/.env.example` **thiếu** `BANKOPS_SIGNING_KEY` / `BANKOPS_SESSION_SECRET` | `backend/.env.example` | Dev mới không biết phải set gì | Bổ sung 2 dòng placeholder (file của worker khác → đã báo cáo) |
| `SECRET_KEY` được `gh secret set` nhưng **không app nào đọc** | `scripts/sync_github_secrets.sh:50` | Secret thừa trong GitHub | `gh secret delete SECRET_KEY` |

---

## 5. Bằng chứng rotate (điền sau khi owner xoay)

Cột `new_fingerprint` trong khối JSON phía dưới được owner điền **sau khi rotate**,
bằng lệnh (in ra **chỉ fingerprint**, không in giá trị):

```bash
python3 scripts/verify_secret_rotation.py --record-new <credential_id>
```

Đối với `supervisor_pin` (6 chữ số) phải dùng chế độ **salted**:

```bash
export ROTATION_FINGERPRINT_SALT="$(openssl rand -hex 16)"   # lưu ở password manager, KHÔNG commit
python3 scripts/verify_secret_rotation.py --record-new supervisor_pin
```

Sau đó:

```bash
python3 scripts/verify_secret_rotation.py --check-env        # exit 0 = đã rotate đủ
python3 scripts/verify_secret_rotation.py --check-provider   # exit 0 = token cũ đã chết
python3 scripts/verify_secret_rotation.py --check-artifacts  # exit 0 = artifact sạch
```

### 5.1 Ghi chú wave 2026-10-21 (DECISION 3)

- Fingerprint mới đã được điền trong khối JSON (mục trên) cho
  `jwt_signing_key`, `legacy_secret_key`, `session_secret`, `supervisor_pin`.
- Fingerprint của `supervisor_pin` là **salted**: salt nằm ở file local
  **gitignored** `.rotation-salt.local` (`.gitignore:32-34`) — **owner phải chuyển
  salt này vào password manager**, nếu không thì không thể tái tạo fingerprint
  salted để verify lần sau. Không bao giờ commit salt (salt + hash của PIN 6
  chữ số = lộ PIN).
- Ba credential **CẦN OWNER** (`smtp_password`, `cloudflare_api_token`,
  `backup_gpg_passphrase`) có `new_fingerprint = null` — `--check-env` sẽ báo
  **FAIL** cho chúng cho tới khi owner cấp giá trị mới (đây là trạng thái
  **đúng**, không phải lỗi của script).
- `database_url` (P3) không nằm trong scope wave này ⇒ vẫn **FAIL** "NOT ROTATED".

---

<!-- BEGIN INVENTORY-JSON -->
```json
{
  "inventory_date": "2026-10-20",
  "repo": "imtarget05/QuanLyKho",
  "credentials": [
    {
      "id": "jwt_signing_key",
      "canonical_var": "BANKOPS_SIGNING_KEY",
      "legacy_vars": ["BANKOPS_dev_signing_key", "SECRET_KEY"],
      "old_fingerprint": "iK6K…(len=64, sha256=96557a63)",
      "new_fingerprint": "73b8…(len=64, sha256=b348ebd0)",
      "status": "ROTATED+VERIFIED",
      "evidence": "2026-10-21: token ký bằng key cũ (dev cũ + SECRET_KEY legacy cũ) -> GET /api/v1/auth/me = 401; POST /api/v1/auth/login = 200 (key mới).",
      "end_state": "rotate",
      "priority": "P0",
      "locations": [
        {"kind": "env_file", "path": "backend/.env", "key": "BANKOPS_dev_signing_key", "required": false},
        {"kind": "process_env", "var": "BANKOPS_SIGNING_KEY", "fallbacks": ["BANKOPS_dev_signing_key"], "required": false},
        {"kind": "k8s_secret", "path": "infra/k8s/base/secret-production.yaml", "key": "BANKOPS_SIGNING_KEY", "required": true},
        {"kind": "github_secret", "name": "BANKOPS_SIGNING_KEY", "required": false}
      ]
    },
    {
      "id": "legacy_secret_key",
      "canonical_var": "SECRET_KEY",
      "legacy_vars": ["SECRET_KEY"],
      "old_fingerprint": "9e7c…(len=64, sha256=e9649e5a)",
      "new_fingerprint": "3c96…(len=64, sha256=dc5064b5)",
      "end_state": "remove",
      "status": "NAME-REMOVED (2026-10-21) — value ROTATED+VERIFIED",
      "evidence": "2026-10-21: end_state rotate -> remove (shim entrypoint.sh đã gỡ ở wave code-hygiene nên rào chặn của DECISION 3 không còn). Giá trị: token ký bằng SECRET_KEY cũ -> GET /api/v1/auth/me = 401. TÊN ĐÃ GỠ ở 2/3 vị trí: GitHub Actions secret (gh secret delete SECRET_KEY, xác nhận bằng gh secret list) + k8s manifest infra/k8s/base/secret-production.yaml. Còn lại (cần owner): .env.production + Secret đang chạy trên cluster.",
      "priority": "P0",
      "locations": [
        {"kind": "env_file", "path": ".env.production", "key": "SECRET_KEY", "required": false},
        {"kind": "k8s_secret", "path": "infra/k8s/base/secret-production.yaml", "key": "SECRET_KEY", "required": false},
        {"kind": "github_secret", "name": "SECRET_KEY", "required": false}
      ]
    },
    {
      "id": "session_secret",
      "canonical_var": "BANKOPS_SESSION_SECRET",
      "legacy_vars": ["BANKOPS_SESSION_SECRET"],
      "old_fingerprint": "rvK4…(len=64, sha256=f00d82ab)",
      "new_fingerprint": "7Qx3…(len=64, sha256=4f456353)",
      "status": "ROTATED+VERIFIED",
      "evidence": "2026-10-21: settings.session_secret khớp fingerprint mới; app khởi động OK + login 200 (không có session server-side nên không mất session nào).",
      "end_state": "rotate",
      "priority": "P0",
      "locations": [
        {"kind": "env_file", "path": "backend/.env", "key": "BANKOPS_SESSION_SECRET", "required": false},
        {"kind": "process_env", "var": "BANKOPS_SESSION_SECRET", "required": false},
        {"kind": "k8s_secret", "path": "infra/k8s/base/secret-production.yaml", "key": "BANKOPS_SESSION_SECRET", "required": true},
        {"kind": "github_secret", "name": "BANKOPS_SESSION_SECRET", "required": false}
      ]
    },
    {
      "id": "smtp_password",
      "canonical_var": "SMTP_PASSWORD",
      "legacy_vars": ["SMTP_PASSWORD", "GMAIL_APP_PASSWORD"],
      "old_fingerprint": "qavo…(len=16, sha256=8e2b3b9b)",
      "new_fingerprint": null,
      "status": "OWNER-REQUIRED",
      "evidence": "2026-10-21: giá trị cũ đã gỡ khỏi .env + backend/.env (placeholder CHANGE_ME_SMTP_PASSWORD). Probe SMTP cho thấy app password CŨ VẪN LOGIN ĐƯỢC (chưa bị xoá ở Google) -> CẦN OWNER xoá + tạo app password mới (probe giá trị MỚI chỉ chạy được sau khi owner tạo). 2026-10-21: k8s manifest infra/k8s/base/secret-production.yaml đã bổ sung CẶP placeholder SMTP_USER/SMTP_PASSWORD (CHANGE_ME_*) -> envFrom cấp được key, nhưng owner PHẢI thay cả 2 giá trị trước khi deploy (placeholder không gửi được mail).",
      "end_state": "rotate",
      "priority": "P0",
      "locations": [
        {"kind": "env_file", "path": ".env", "key": "SMTP_PASSWORD", "required": false},
        {"kind": "env_file", "path": "backend/.env", "key": "SMTP_PASSWORD", "required": false},
        {"kind": "process_env", "var": "SMTP_PASSWORD", "required": false},
        {"kind": "k8s_secret", "path": "infra/k8s/base/secret-production.yaml", "key": "SMTP_PASSWORD", "required": true},
        {"kind": "github_secret", "name": "SMTP_PASSWORD", "required": false}
      ]
    },
    {
      "id": "supervisor_pin",
      "canonical_var": "SUPERVISOR_PIN",
      "legacy_vars": ["SUPERVISOR_PIN"],
      "old_fingerprint": "1234…(len=6, sha256=8d969eef)",
      "new_fingerprint": "salted(len=6, sha256=4ab63689)",
      "status": "ROTATED",
      "evidence": "2026-10-21: PIN mới 6 chữ số ≠ PIN demo 123456, lưu .env.production + secret-production.yaml + GH secret. Salt của fingerprint salted nằm ở file local gitignored .rotation-salt.local (owner phải chuyển vào password manager). PIN demo 123456 chỉ dùng khi settings.is_demo_mode.",
      "end_state": "rotate",
      "fingerprint_mode": "salted",
      "priority": "P1",
      "locations": [
        {"kind": "env_file", "path": ".env.production", "key": "SUPERVISOR_PIN", "required": false},
        {"kind": "k8s_secret", "path": "infra/k8s/base/secret-production.yaml", "key": "SUPERVISOR_PIN", "required": true},
        {"kind": "process_env", "var": "SUPERVISOR_PIN", "required": false},
        {"kind": "github_secret", "name": "SUPERVISOR_PIN", "required": false}
      ]
    },
    {
      "id": "cloudflare_api_token",
      "canonical_var": "CLOUDFLARE_API_TOKEN",
      "legacy_vars": ["CLOUDFLARE_API_TOKEN"],
      "old_fingerprint": "cfut…(len=53, sha256=a9d3b0e0)",
      "new_fingerprint": null,
      "status": "OWNER-REQUIRED",
      "evidence": "2026-10-21: giá trị cũ đã gỡ khỏi .env/.env.production/backend/.env/secret-production.yaml (placeholder). Token cũ id=047a0f925794d270641de780673aef42 vẫn ACTIVE: GET /user/tokens/verify=200, GET /user/tokens=403, DELETE /user/tokens/{id}=403 (code 9109) -> phải owner revoke ở Cloudflare Dashboard.",
      "end_state": "rotate",
      "priority": "P1",
      "locations": [
        {"kind": "env_file", "path": ".env", "key": "CLOUDFLARE_API_TOKEN", "required": false},
        {"kind": "env_file", "path": ".env.production", "key": "CLOUDFLARE_API_TOKEN", "required": false},
        {"kind": "env_file", "path": "backend/.env", "key": "CLOUDFLARE_API_TOKEN", "required": false},
        {"kind": "k8s_secret", "path": "infra/k8s/base/secret-production.yaml", "key": "CLOUDFLARE_API_TOKEN", "required": false},
        {"kind": "github_secret", "name": "CLOUDFLARE_API_TOKEN", "required": false}
      ]
    },
    {
      "id": "backup_gpg_passphrase",
      "canonical_var": "BACKUP_GPG_PASSPHRASE",
      "legacy_vars": ["BACKUP_GPG_PASSPHRASE"],
      "old_fingerprint": "qwfb…(len=32, sha256=6a2bee79)",
      "new_fingerprint": null,
      "status": "OWNER-REQUIRED",
      "evidence": "2026-10-21: giá trị cũ đã gỡ khỏi .env.production + secret-production.yaml (placeholder). Passphrase MỚI phải do người giữ keyring GPG tạo; không verify tự động được (cần backup cũ để re-encrypt).",
      "end_state": "rotate",
      "priority": "P1",
      "locations": [
        {"kind": "env_file", "path": ".env.production", "key": "BACKUP_GPG_PASSPHRASE", "required": false},
        {"kind": "k8s_secret", "path": "infra/k8s/base/secret-production.yaml", "key": "BACKUP_GPG_PASSPHRASE", "required": false},
        {"kind": "github_secret", "name": "BACKUP_GPG_PASSPHRASE", "required": false}
      ]
    },
    {
      "id": "database_url",
      "canonical_var": "DATABASE_URL",
      "legacy_vars": ["DATABASE_URL"],
      "old_fingerprint": "post…(len=59, sha256=3d4d0275)",
      "new_fingerprint": null,
      "status": "NOT-ROTATED (P3, out of scope wave 2026-10-21)",
      "evidence": "2026-10-21: giữ nguyên theo kế hoạch (chỉ rotate khi DB dev có dữ liệu thật). Lưu ý: 3 vị trí có 3 URL KHÁC NHAU (dev docker host vs localhost) nên old_fingerprint của credential này chỉ khớp đúng .env.production — độ chính xác của inventory, không phải lỗi rotation.",
      "end_state": "rotate",
      "priority": "P3",
      "locations": [
        {"kind": "env_file", "path": ".env", "key": "DATABASE_URL", "required": false},
        {"kind": "env_file", "path": ".env.production", "key": "DATABASE_URL", "required": false},
        {"kind": "env_file", "path": "backend/.env", "key": "DATABASE_URL", "required": false},
        {"kind": "github_secret", "name": "DATABASE_URL", "required": false}
      ]
    }
  ]
}
```
<!-- END INVENTORY-JSON -->

---

## 6. Bảng "còn lại cần owner" (agent **không** làm được)

| # | Hành động | Lệnh / đường dẫn | Cách xác nhận |
|---|---|---|---|
| 1 | Tạo JWT signing key mới | `python3 -c "import secrets; print(secrets.token_hex(32))"` | `python3 scripts/verify_secret_rotation.py --record-new jwt_signing_key` |
| 2 | Cấp key mới cho GitHub Actions | `gh secret set BANKOPS_SIGNING_KEY --repo imtarget05/QuanLyKho` | `gh secret list --repo imtarget05/QuanLyKho` (có `BANKOPS_SIGNING_KEY`) |
| 3 | Cấp key mới cho k8s + gỡ `SECRET_KEY` | `kubectl -n bankops-prod create secret generic bankops-secrets --from-literal=BANKOPS_SIGNING_KEY="$NEW" --dry-run=client -o yaml \| kubectl apply -f -` | `kubectl -n bankops-prod get secret bankops-secrets -o jsonpath='{.data}' \| tr ',' '\n'` (không có `SECRET_KEY`) |
| 4 | Tạo Gmail app password mới + xoá app password cũ | `https://myaccount.google.com/apppasswords` | `--check-provider` với `SMTP_OLD_PASSWORD` → 535; `SMTP_NEW_PASSWORD` → OK |
| 5 | Tạo Cloudflare API token mới + Revoke token cũ | `https://dash.cloudflare.com/profile/api-tokens` | `--check-provider` với `CLOUDFLARE_OLD_TOKEN` → không 200; `CLOUDFLARE_NEW_TOKEN` → 200 |
| 6 | Tạo `BANKOPS_SESSION_SECRET` mới | `python3 -c "import secrets; print(secrets.token_urlsafe(48))"` | `--record-new session_secret` → khớp |
| 7 | Chọn PIN production mới (6 chữ số, ≠ PIN demo) | `python3 -c "import secrets; print(f'{secrets.randbelow(1000000):06d}')"` | `--record-new supervisor_pin` (chế độ salted) |
| 8 | Cấp PIN mới (GitHub + k8s), **không** `wrangler secret put` | `gh secret set SUPERVISOR_PIN --repo imtarget05/QuanLyKho` | Luồng duyệt 4-mắt: PIN cũ → 403, PIN mới → 200 |
| 9 | Re-encrypt backup cũ bằng passphrase GPG mới | `gpg --batch --yes --passphrase-fd 3 --decrypt old.dump.gpg \| gpg --batch --yes --passphrase-fd 3 --encrypt --recipient <KEY_ID> > new.dump.gpg` | `gpg --decrypt new.dump.gpg` với passphrase mới → OK |
| 10 | Xoá app password / token cũ ở provider | Google App passwords · Cloudflare API Tokens → **Revoke** | `--check-provider` báo PASS |
| 11 | Bật **GitHub secret scanning** | `https://github.com/imtarget05/QuanLyKho/settings/security_analysis` | Trang báo "Secret scanning: Enabled" |
| 12 | Bật **push protection** | `https://github.com/imtarget05/QuanLyKho/settings/security_analysis/push_protection` | Trang báo "Push protection: Enabled" |
| 13 | (Sau khi rotate) Duyệt **rewrite history** | `git filter-repo --replace-text <file>` + `git push --force --mirror origin` | `git log --all -S<giá trị cũ>` → 0 kết quả |
| 14 | Fix `admin_users.py:351` (default PIN không gate demo) | PR riêng | Test: tạo user ở `APP_ENV=production` → `pin_hash is None` |
| 15 | Fix `scripts/sync_github_secrets.sh` (in giá trị secret ra terminal; thiếu 4 biến) | PR riêng | `rg 'set_secret' scripts/sync_github_secrets.sh` → có đủ 4 biến mới |
| 16 | Bổ sung `BANKOPS_SIGNING_KEY`/`BANKOPS_SESSION_SECRET` vào `backend/.env.example` | PR riêng | `rg 'BANKOPS_' backend/.env.example` |
| 17 | Gỡ shim `SECRET_KEY` ở `backend/entrypoint.sh:10-14` | PR riêng (sau khi #3 xong) | Log entrypoint không còn nhánh "dùng SECRET_KEY" |
| 18 | Thêm `SMTP_PASSWORD`, `BANKOPS_SESSION_SECRET`, `BANKOPS_SIGNING_KEY` vào `infra/k8s/base/secret-template.yaml` | PR riêng (file của worker khác → đã báo cáo, **không** sửa) | `rg 'BANKOPS_SIGNING_KEY' infra/k8s/base/secret-template.yaml` |

### 6.1 Trạng thái các hạng mục trên sau wave 2026-10-21

| # | Hạng mục | Trạng thái 2026-10-21 |
|---|---|---|
| 1, 2, 6, 8 | Sinh + cấp key/PIN mới (GitHub + file local) | **ĐÃ XONG** (key mới đã set trong GH, file local, k8s manifest) |
| 3 | Cấp key mới cho k8s Secret + gỡ `SECRET_KEY` | **MỞ (giảm)** — 2026-10-21: `BANKOPS_SIGNING_KEY` đã có trong `secret-production.yaml`; **tên legacy `SECRET_KEY` đã gỡ** ở **GitHub Actions secret** (`gh secret delete SECRET_KEY`) và **k8s Secret manifest** (`infra/k8s/base/secret-production.yaml`, file gitignored — không commit). **Còn lại (cần owner):** (a) xoá dòng `SECRET_KEY=` trong `.env.production:4`; (b) patch Secret **đang chạy** trên cluster: `kubectl -n bankops-prod patch secret bankops-secrets --type=json -p '[{"op":"remove","path":"/data/SECRET_KEY"}]'` |
| 4, 5, 7, 9, 10 | Cấp SMTP/CF/GPG mới + revoke/thu hồi cái cũ | **CẦN OWNER** — không làm được từ máy agent |
| 11, 12 | Bật secret scanning + push protection | **ĐÃ XONG** (2026-10-21, wave code-hygiene): `imtarget05/QuanLyKho` → `security_and_analysis.secret_scanning.status=enabled` + `secret_scanning_push_protection.status=enabled` (xác minh bằng `gh api repos/imtarget05/QuanLyKho --jq .security_and_analysis`); `imtarget05/AKS-SRE-Platform` → cũng enabled; `imtarget05/OpsBridge` → **404** (repo không tồn tại trong account ⇒ **CẦN OWNER xác nhận tên repo**). Endpoint `.../secret-scanning/secret-scanning` trả 404 vì repo public (endpoint đó dành cho GH Advanced Security) |
| 13 | Rewrite history | **CHƯA** — cần phê duyệt riêng (rotate xong mới nên rewrite) |
| 14 | Fix `admin_users.py:351` (default PIN không gate demo) | **ĐÃ XONG** (2026-10-21, wave code-hygiene): `pin_hash` chỉ gán khi `settings.is_demo_mode`, ngoài demo mode ⇒ `None`. Test `backend/tests/test_admin_user_default_pin_gate.py` |
| 15 | Fix `scripts/sync_github_secrets.sh` | **ĐÃ XONG** (2026-10-21): nhánh fallback không còn in giá trị secret (chỉ in tên, ghi literal); đã thêm 4 biến chuẩn vào danh sách sync; **không** sync `SECRET_KEY` (legacy) nữa. Test `backend/tests/test_sync_github_secrets_script.py` |
| 16 | `backend/.env.example` | **ĐÃ XONG** (2026-10-21, wave code-hygiene): khai báo `BANKOPS_SIGNING_KEY`, `BANKOPS_SESSION_SECRET`, `SUPERVISOR_PIN` (placeholder) + nhắc `SECRET_KEY` là legacy/DEPRECATED |
| 17 | Gỡ shim `SECRET_KEY` ở `backend/entrypoint.sh` | **ĐÃ XONG (2026-10-21, wave code-hygiene)**: fallback âm thầm đã bị gỡ — production/staging (hoặc `APP_ENV` unset) **FAIL-FAST** exit 1; demo/dev/test mới fallback kèm cảnh báo lớn. Test `backend/tests/test_entrypoint_signing_key.py`. *Còn mở (owner):* gỡ tên `SECRET_KEY` khỏi k8s/GitHub/`.env.production` (mục #3) |
| 18 | `secret-template.yaml` | **ĐÃ XONG** (2026-10-21, wave code-hygiene): khai báo đủ key chuẩn (`BANKOPS_SIGNING_KEY`, `BANKOPS_SESSION_SECRET`, `SMTP_USER`, `SMTP_PASSWORD`, `SUPERVISOR_PIN`) + `SECRET_KEY` ghi rõ DEPRECATED. Test `backend/tests/test_k8s_secret_template.py` |
| 19 | Sửa `scripts/setup_secrets_and_deploy.sh` (ghi đè file khi thiếu biến; thiếu key chuẩn; in giá trị) | **ĐÃ XONG** (2026-10-21, wave code-hygiene): ghi đủ key chuẩn, có `--from-env`, không in giá trị, **không ghi đè file** khi thiếu biến bắt buộc (exit 1 + danh sách tên biến thiếu), không ghi/không fallback `SECRET_KEY`. Test `backend/tests/test_setup_secrets_script.py` |
