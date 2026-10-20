# Credential Rotation Runbook — BankOps / QuanLyKho

**Owner:** chủ tài khoản (account owner) + SRE/ops
**Scope:** các credential đã bị ghi ra file local / lịch sử git (S10, 2026-10-20)
**Trạng thái sau S10:** `CONTAINED-PENDING-ROTATION` — đường lộ trong repo đã đóng,
nhưng **credential cũ vẫn còn hiệu lực** ở phía provider. Bước rotate phải do người
giữ tài khoản thực hiện; agent/automation **không** tự revoke.

> **Runbook bổ sung (2026-10-20, wave secrets-rotation):**
> - Bảng inventory chi tiết (fingerprint, nơi dùng, cách tạo/cập nhật/xác minh,
>   rollback, ảnh hưởng) nằm ở
>   **`docs/security/secret-rotation-inventory-2026-10-20.md`**.
> - Cơ chế xác minh **sau rotation** nằm ở **`scripts/verify_secret_rotation.py`**
>   (mục 10, 11, 12 bên dưới).

> **Quy tắc bắt buộc khi thực hiện runbook này**
> - Không in giá trị credential ra terminal, log CI, hay commit.
> - Dùng `read -s` / prompt ẩn, hoặc paste trực tiếp vào secret store.
> - Mọi bước "verify" đều so **fingerprint** (4 ký tự đầu + độ dài + `sha256[:8]`),
>   không so giá trị.
> - Mọi bước xoá/rotate là **phá huỷ** — không làm khi chưa có backup + rollback.

---

## 0. Danh sách credential cần rotate (kèm fingerprint hiện tại)

Fingerprint = `<4 ký tự đầu>…(len=<độ dài>, sha256=<8 hex>)`.
Dùng bảng này để xác định **đúng** giá trị cần thay mà không cần đọc giá trị.

| # | Credential | Fingerprint hiện tại | Nơi đang xuất hiện | Lộ trong lịch sử git? | Ưu tiên |
|---|---|---|---|---|---|
| 1 | `BANKOPS_dev_signing_key` (JWT signing key) | `iK6K…(len=64, sha256=96557a63)` | `backend/.env:37` | Không | **P0** |
| 2 | `SECRET_KEY` (app secret) | `9e7c…(len=64, sha256=e9649e5a)` | `.env.production:4`, `infra/k8s/base/secret-production.yaml:11` | Không | **P0** |
| 3 | `BANKOPS_SESSION_SECRET` | `rvK4…(len=64, sha256=f00d82ab)` | `backend/.env:18` | Không | **P0** |
| 4 | `SMTP_PASSWORD` (Gmail app password) | `qavo…(len=16, sha256=8e2b3b9b)` | `.env:21`, `backend/.env:26` | **CÓ** — `docker-compose.yml` @ `53be143` (còn ở `origin/main`); thêm nữa 4 ký tự đầu nằm trong `docs/security/credential-rotation-runbook.md` @ `bea0922` | **P0** |
| 5 | `CLOUDFLARE_API_TOKEN` | `cfut…(len=53, sha256=a9d3b0e0)` | `.env:7`, `.env.production:10`, `backend/.env:31`, `infra/k8s/base/secret-production.yaml:14` | Không (đã quét toàn bộ blob history: chỉ có **mẫu** `cfut_…` trong docs) | **P1** |
| 6 | `BACKUP_GPG_PASSPHRASE` | `qwfb…(len=32, sha256=6a2bee79)` | `.env.production:20`, `infra/k8s/base/secret-production.yaml:18` | Không | **P1** |
| 7 | `SUPERVISOR_PIN` | `1234…(len=6, sha256=8d969eef)` — **giá trị đã công khai** (trùng PIN demo trong code) | `.env.production:5`, `infra/k8s/base/secret-production.yaml:12` | **CÓ** — `infra/k8s/base/secret-template.yaml` @ `e76419b`,`bea0922`; `README.md` @ `5602ef0`,`310551a`; `scripts/setup_secrets_and_deploy.sh` @ `af2157b`; `infra/scripts/setup-neon.sh` @ `e6275a3` | **P1** |
| 8 | `DATABASE_URL` (dev Postgres `bankops:bankops@localhost`) | `post…(len=59, sha256=3d4d0275)` | `.env:3`, `.env.production:3`, `backend/.env:3` | Có (nhưng chỉ là credential DB **dev local**, không phải prod) | P3 |

Ghi chú: `SUPERVISOR_PIN` là giá trị **yếu, đã công khai trong repo** — sau khi rotate
production PIN sang giá trị mạnh, mọi tài liệu/demo cũng phải dùng PIN demo riêng.

> ⚠️ **Hash của PIN 6 chữ số là đồng nghĩa với lộ PIN** (`sha256[:8]` brute-force được
> trong vài micro-giây). Vì vậy fingerprint **mới** của `SUPERVISOR_PIN` phải ghi ở
> dạng **salted** — xem mục 10.

---

## 1. Thứ tự thực hiện (làm theo thứ tự này)

1. **P0 — JWT signing key (`BANKOPS_dev_signing_key`)** và **`SECRET_KEY`**:
   lộ = forge được token admin → ưu tiên tuyệt đối.
2. **P0 — `BANKOPS_SESSION_SECRET`**: invalidate toàn bộ session đang còn sống.
3. **P0 — Gmail app password (`SMTP_PASSWORD`)**: đã nằm trong git history **công khai**
   → coi như đã lộ công khai, rotate ngay.
4. **P1 — `SUPERVISOR_PIN`**: rotate production PIN sang giá trị mạnh (≥6 ký tự, không ai biết).
5. **P1 — Cloudflare API token**: scope hẹp nhất, rotate + thu hồi token cũ.
6. **P1 — `BACKUP_GPG_PASSPHRASE`**: ảnh hưởng khả năng giải mã backup cũ → cần kế hoạch
   re-encrypt backup (xem mục 6).
7. **P2 — dọn lịch sử git** (mục 7) + bật GitHub secret scanning.
8. **P3 — `DATABASE_URL` dev**: chỉ rotate nếu DB dev có dữ liệu thật.

---

## 2. Ghi giá trị mới an toàn (không lộ qua shell history)

```bash
# Dùng shell tương tác, KHÔNG truyền giá trị làm argv (argv bị ghi vào history/ps).
read -rsp "New value: " NEW_VALUE; echo
printf '%s' "$NEW_VALUE" | sha256sum | cut -c1-8   # fingerprint để đối chiếu, không lộ giá trị
unset NEW_VALUE
```

Hoặc ghi trực tiếp vào secret store (không qua file trung gian):

```bash
gh secret set BANKOPS_SIGNING_KEY      # GitHub Actions secret (ẩn giá trị)
```

---

## 3. Cloudflare API Token (P1)

Bước cần **chủ tài khoản Cloudflare** (đăng nhập dashboard).

1. Cloudflare Dashboard → **My Profile → API Tokens → Create Token**.
   - Template: **Edit Cloudflare Workers** (scope tối thiểu: `Workers Scripts: Edit`
     + `Pages: Edit` nếu deploy Pages; **không** dùng "Global API Key").
   - Không đặt TTL dài hơn mức cần; bật IP restriction nếu CI chạy từ IP cố định.
2. **Thu hồi token cũ** *sau khi* token mới đã được dùng thành công (xem verify).
   Token cũ: Dashboard → API Tokens → token tương ứng → **Revoke**.
3. Phát hành lại:
   ```bash
   gh secret set CLOUDFLARE_API_TOKEN --repo imtarget05/QuanLyKho
   gh secret set CLOUDFLARE_ACCOUNT_ID --repo imtarget05/QuanLyKho
   ```
   (`CLOUDFLARE_ACCOUNT_ID` không nhạy cảm, nhưng để một chỗ cho dễ quản lý.)
4. Cập nhật local env (file gitignored, không commit):
   - `.env:7`, `.env.production:10`, `backend/.env:31`
   - `infra/k8s/base/secret-production.yaml:14` (nếu file này còn được dùng — nó là
     output của `scripts/setup_secrets_and_deploy.sh`, có thể regenerate)
5. **Verify token mới hoạt động:**
   ```bash
   curl -sS -o /dev/null -w '%{http_code}\n' \
     -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
     https://api.cloudflare.com/client/v4/user/tokens/verify
   # 200 => token hợp lệ
   ```
6. **Verify token cũ đã chết** (sau khi revoke):
   ```bash
   # dùng token CŨ (biến tạm, không log ra):
   curl -sS -o /dev/null -w '%{http_code}\n' \
     -H "Authorization: Bearer $OLD_CF_TOKEN" \
     https://api.cloudflare.com/client/v4/user/tokens/verify
   # 403/401 => token cũ đã bị thu hồi (đạt mục tiêu)
   ```
7. **Rollback:** nếu deploy bằng token mới lỗi → quay lại token cũ *trước khi revoke*
   (giữ token cũ sống đến khi token mới verify OK), sửa scope, tạo token mới.

---

## 4. Gmail app password (P0 — đã lộ công khai)

Bước cần **chủ tài khoản Google**.

1. Google Account → **Security → 2-Step Verification → App passwords**
   (bắt buộc bật 2-Step Verification trước).
2. Tạo app password mới cho "Mail" (tên gợi ý: `bankops-mail-<tháng>`).
3. **Xoá app password cũ** (ngay sau khi app password mới chạy OK — xem verify).
4. Phát hành lại:
   ```bash
   gh secret set SMTP_PASSWORD --repo imtarget05/QuanLyKho
   ```
5. Cập nhật local env: `.env:21`, `backend/.env:26`.
6. **Verify:** gửi 1 email test qua đúng SMTP host/port của repo (`smtp.gmail.com:587`):
   ```bash
   # dùng biến tạm; không in giá trị
   python3 - <<'PY'
   import os, smtplib
   with smtplib.SMTP(os.environ["SMTP_HOST"], int(os.environ["SMTP_PORT"]), timeout=20) as s:
       s.starttls()
       s.login(os.environ["SMTP_USER"], os.environ["SMTP_PASSWORD"])
   print("SMTP login OK")
   PY
   ```
   `SMTP login OK` ⇒ app password mới dùng được.
7. **Verify app password cũ đã chết:** lặp lại bước 6 với app password cũ →
   phải trả `535 Authentication credentials invalid`. Nếu vẫn login được ⇒ chưa bị xoá.
8. **Rollback:** nếu SMTP mới lỗi → tạo app password tạm mới (không dùng lại app
   password cũ đã nằm trong git history), sửa cấu hình, rồi xoá app password tạm.

---

## 5. GPG backup passphrase (P1)

Bước cần **chủ tài khoản** (người giữ keyring GPG offline).

1. Sinh passphrase mới (mạnh, ≥ 32 ký tự, lưu ở password manager):
   ```bash
   python3 -c "import secrets; print(secrets.token_urlsafe(32))"
   ```
2. Phát hành lại:
   ```bash
   gh secret set BACKUP_GPG_PASSPHRASE --repo imtarget05/QuanLyKho
   ```
3. Cập nhật local env: `.env.production:20`, `infra/k8s/base/secret-production.yaml:18`.
4. **Verify:** test decrypt bằng passphrase mới trên 1 backup mới:
   ```bash
   printf '%s' "$BACKUP_GPG_PASSPHRASE" | gpg --batch --passphrase-fd 0 \
     --decrypt /path/to/backup.dump.gpg > /dev/null && echo "decrypt OK"
   ```
5. **Lưu ý tương thích:** passphrase cũ vẫn phải giữ **tạm** cho tới khi mọi backup
   cũ đã được re-encrypt bằng passphrase mới (mục 6). Xoá passphrase cũ sớm ⇒ mất
   khả năng khôi phục backup cũ.
6. **Rollback:** nếu backup job mới fail → tạm quay lại passphrase cũ **chỉ** để đọc
   backup cũ, không ghi backup mới bằng passphrase cũ.

### 6. Re-encrypt backup cũ (kèm theo mục 5)

```bash
gpg --batch --yes --passphrase-fd 3 --decrypt old.dump.gpg \
  | gpg --batch --yes --passphrase-fd 3 --encrypt --recipient <KEY_ID> \
  > new.dump.gpg
```
Chạy từng file backup cũ, verify bằng cách decrypt lại `new.dump.gpg` với passphrase
mới, rồi mới xoá bản cũ. **Chỉ chủ tài khoản (người giữ keyring) thực hiện.**

---

## 6. `SUPERVISOR_PIN` (P1) + `SECRET_KEY` / `BANKOPS_SESSION_SECRET` / JWT signing key (P0)

### 6.1. JWT signing key (`BANKOPS_dev_signing_key`) — P0

Key ký JWT. **Lộ = forge được token admin.**

1. Sinh key mới (32 byte hex = 64 ký tự):
   ```bash
   python3 -c "import secrets; print(secrets.token_hex(32))"
   ```
2. Phát hành lại:
   ```bash
   gh secret set BANKOPS_dev_signing_key --repo imtarget05/QuanLyKho
   ```
   Backend đọc key qua `BANKOPS_<JWT_SIGNING_KEY_REF>`; với `JWT_SIGNING_KEY_REF=dev_signing_key`
   thì tên biến là `BANKOPS_dev_signing_key` (giữ nguyên ref để không phá config).
3. Cập nhật local env: `backend/.env:37`.
4. **Verify:** token cũ phải **không còn hợp lệ**:
   ```bash
   # token cũ (đã lấy trước khi rotate) → phải trả 401
   curl -sS -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $OLD_ACCESS_TOKEN" \
     https://<api-host>/api/v1/auth/me
   ```
   Token mới (đăng nhập lại) → 200. Sau khi đổi signing key, **mọi user phải đăng nhập
   lại** (access + refresh token cũ đều không dùng được) — đó chính là mục tiêu.
5. **Rollback:** nếu deploy lỗi → rollback **mã deploy** về bản cũ **và** đặt lại key
   cũ trong secret store; chấp nhận token cũ sống lại (đánh đánh đổi an toàn).

### 6.2. `SECRET_KEY` (P0)

> ⚠️ **Tên legacy — trạng thái đích là GỠ, không phải rotate.**
> `SECRET_KEY` **không được đọc bởi bất kỳ code nào** trong `backend/app/`. Nó chỉ
> được dùng gián tiếp qua shim `backend/entrypoint.sh:10-14` → `BANKOPS_SIGNING_KEY`.
> Vì vậy, ở tầng deploy hiện tại, `SECRET_KEY` **chính là** JWT signing key.
> Việc rotate đúng là: thêm `BANKOPS_SIGNING_KEY` (giá trị mới) vào k8s Secret +
> GitHub secret → deploy → xác nhận token cũ trả 401 → **xoá** `SECRET_KEY` khỏi
> k8s Secret / `.env.production` / GitHub secret → gỡ shim ở `entrypoint.sh`.
> Chi tiết: `docs/security/secret-rotation-inventory-2026-10-20.md` §2.2.

Sinh mới (`python3 -c "import secrets; print(secrets.token_hex(32))"`), phát hành qua
`gh secret set BANKOPS_SIGNING_KEY --repo imtarget05/QuanLyKho`, thêm vào k8s Secret
(`kubectl create secret generic bankops-secrets --from-literal=BANKOPS_SIGNING_KEY=… --dry-run=client -o yaml | kubectl apply -f -`).
Verify: app khởi động OK (`backend/app/config.py` fail-fast khi thiếu secret ở non-demo)
+ endpoint `/health` trả 200 + token cũ trả 401. Rollback: đặt lại giá trị cũ + rollback deploy.

### 6.3. `BANKOPS_SESSION_SECRET` (P0)

> ⚠️ **Không có session server-side.** `backend/app/main.py` **không** mount
> `SessionMiddleware`; auth là **stateless JWT**. Property `settings.session_secret`
> (`backend/app/config.py:201-210`) hiện **không được gọi ở production** ⇒ rotate
> **không** làm mất session nào. Bằng chứng đúng cho bước này là "app vẫn khởi động
> ở `APP_ENV=production` + login 200", không phải "session cũ bị từ chối".
> *Nếu* session được bật lại sau này, rotate sẽ invalidate toàn bộ cookie → cần window.

Sinh mới, `gh secret set BANKOPS_SESSION_SECRET --repo imtarget05/QuanLyKho`, thêm vào
k8s Secret, cập nhật `backend/.env:18`. Verify: `--check-env` báo PASS cho
`BANKOPS_SESSION_SECRET` + `/api/v1/auth/login` → 200. Rollback: đặt lại giá trị cũ
(kèm rollback deploy).

### 6.4. `SUPERVISOR_PIN` (P1)

1. Chọn PIN mạnh (≥6 ký tự, **không dùng** `123456`, không trùng PIN demo trong README).
2. Phát hành: `gh secret set SUPERVISOR_PIN --repo imtarget05/QuanLyKho`
   (Worker: `npx wrangler secret put SUPERVISOR_PIN` cho từng env `production`/`staging`).
3. Cập nhật `.env.production:5`, `infra/k8s/base/secret-production.yaml:12`.
4. Verify: PIN cũ bị từ chối (`403`), PIN mới được chấp nhận trên luồng duyệt 4-mắt.
5. **Lưu ý:** PIN demo trong code/README (`123456`) là **demo**, không phải production
   credential — nhưng vì nó từng trùng với PIN production nên sau khi rotate, tuyệt đối
   không đặt lại production PIN bằng giá trị đó.
6. Rollback: đặt lại PIN cũ trong secret store + rollback deploy (chỉ dùng khi fix
   sự cố triển khai, sau đó phải rotate lại).

---

## 7. Dọn lịch sử git (P2) — `SMTP_PASSWORD` đã nằm trong history công khai

Hiện trạng: `docker-compose.yml` tại commit `53be143` (2026-10-14) chứa giá trị
`SMTP_PASSWORD` dạng plaintext; commit đó **reachable từ `origin/main`** → ai clone
repo cũng đọc được. Các commit liên quan: `53be143` (thêm), `90a6327` (gỡ).

Ngoài ra (đã quét **toàn bộ blob** trong lịch sử, không chỉ tên biến):

- `SMTP_PASSWORD` (4 ký tự đầu) nằm trong `docs/security/credential-rotation-runbook.md`
  @ `bea0922` (reachable `origin/main`) — giảm entropy của app password 16 ký tự.
- `SUPERVISOR_PIN` (giá trị thật) nằm trong `infra/k8s/base/secret-template.yaml`
  @ `e76419b`, `bea0922`; `README.md` @ `5602ef0`, `310551a`;
  `scripts/setup_secrets_and_deploy.sh` @ `af2157b`; `infra/scripts/setup-neon.sh` @ `e6275a3`
  — tất cả reachable từ `origin/main`.
- `f5be287`, `35e6e6b` chứa `SUPERVISOR_PIN` nhưng **KHÔNG** reachable từ `origin/main`
  (nhánh cục bộ) → chỉ cần rewrite nếu nhánh đó còn được push lên remote.
- `SECRET_KEY`, `BANKOPS_SESSION_SECRET`, `BANKOPS_dev_signing_key`,
  `CLOUDFLARE_API_TOKEN`, `BACKUP_GPG_PASSPHRASE`: **KHÔNG** có trong lịch sử git
  (chỉ nằm ở file local gitignored) → không cần rewrite, chỉ cần rotate.

**Bắt buộc: rotate (mục 4) TRƯỚC khi rewrite history.** Rewrite không làm credential
mất hiệu lực — nếu chưa rotate thì rewrite là vô nghĩa.

Procedure (chủ repo / admin, cần thao tác trên remote):

```bash
# 1. Bắt buộc: đồng bộ mọi thay đổi đang dở của người khác trước khi rewrite
git fetch --all --prune
git status                      # phải sạch (hoặc stash có chủ đích của bạn)

# 2. Dùng git-filter-repo để xoá file/giá trị khỏi toàn bộ lịch sử
pipx install git-filter-repo
git filter-repo --path docker-compose.yml --invert-paths   # xoá hẳn file khỏi lịch sử
# (nếu muốn giữ file, dùng --replace-text để thay đúng giá trị secret)

# 3. Đẩy lại (cần force-push + cập nhật mọi clone)
git push --force --mirror origin
```

Hậu quả bắt buộc:
- Tất cả clone cũ của dev phải `git fetch && git reset --hard origin/main` (hoặc clone lại).
- Mọi PR/mở tab cũ trỏ vào commit đã bị ghi đè sẽ cần rebase.
- Nếu repo đã fork/copy ra nơi khác → credential vẫn còn ở đó → **bắt buộc rotate**
  (đã nêu ở mục 4).
- Bật **GitHub → Settings → Code security → Secret scanning** (push protection) để
  chặn lần sau.

Rollback: giữ một mirror backup cục bộ của repo **trước khi rewrite** để khôi phục
nếu rewrite làm hỏng lịch sử; nhưng **không** push mirror đó lên remote công khai.

---

## 8. Dọn local (không commit)

Các file local dưới đây là **gitignored**, giữ nguyên cho tới khi rotate xong, sau đó
cập nhật giá trị mới theo bảng ở mục 0:

- `.env` (dòng 7, 21)
- `.env.production` (dòng 4, 5, 10, 20)
- `backend/.env` (dòng 18, 26, 31, 37)
- `infra/k8s/base/secret-production.yaml` (dòng 11, 12, 14, 18) — output của
  `scripts/setup_secrets_and_deploy.sh`; có thể regenerate sau khi rotate.

Sau khi rotate xong: **xoá các bản sao lưu cũ** (`.env.bak`, backup cục bộ, file
`*.dump.gpg` cũ chứa dữ liệu mã hoá bằng passphrase cũ) — hoặc mã hoá lại bằng
passphrase mới (mục 6 của mục 5).

---

## 9. Checklist nghiệm thu S10

- [ ] P0: JWT signing key đã rotate + token cũ trả 401.
- [ ] P0: `SECRET_KEY` đã rotate.
- [ ] P0: `BANKOPS_SESSION_SECRET` đã rotate.
- [ ] P0: Gmail app password đã rotate + app password cũ login fail (535).
- [ ] P1: `SUPERVISOR_PIN` đã rotate sang giá trị mạnh, khác mọi giá trị trong repo.
- [ ] P1: Cloudflare API token đã rotate + token cũ trả 403.
- [ ] P1: `BACKUP_GPG_PASSPHRASE` đã rotate + backup cũ đã re-encrypt.
- [ ] P2: Git history đã rewrite (nếu quyết định) + secret scanning bật.
- [ ] Tất cả secret store (GitHub Actions / Cloudflare secret / Vault) đã cập nhật.
- [ ] `python3 scripts/check_no_secrets.py` → exit 0.
- [ ] `python3 scripts/check_no_secrets.py --local` → không còn finding sau khi local
      env đã được cập nhật giá trị mới.

> Checklist chi tiết kèm **cột Evidence** nằm ở mục 12.

---

## 10. Cơ chế xác minh SAU rotation — `scripts/verify_secret_rotation.py`

Script này là **cổng bằng chứng (evidence gate)**: nó chỉ in **fingerprint**, không
in giá trị secret, và **exit 0 chỉ khi** mọi credential đã rotate + credential cũ
đã chết.

### 10.1. Ba chế độ

| Chế độ | Lệnh | Làm gì | Exit |
|---|---|---|---|
| So sánh env | `python3 scripts/verify_secret_rotation.py --check-env` | Đối chiếu giá trị hiện tại ở mọi nơi lưu (process env, `.env`, `.env.production`, `backend/.env`, k8s `secret-production.yaml`) với fingerprint **trước** và **sau** rotation ghi trong inventory | `0` = đã rotate đủ · `1` = còn credential chưa rotate / thiếu bằng chứng · `2` = không kết luận được |
| Kiểm tra provider | `python3 scripts/verify_secret_rotation.py --check-provider` | Probe **read-only**: Cloudflare `GET /user/tokens/verify` (token cũ phải ≠ 200), Gmail SMTP `login` bằng app password cũ (phải trả **535**), JWT: access token cũ gọi `GET /api/v1/auth/me` (phải **401**). **Không tạo tài nguyên, không gửi mail** | `0` = token cũ đã chết & token mới chạy |
| Quét artifact | `python3 scripts/verify_secret_rotation.py --check-artifacts [DIR ...]` | Quét log/artifact, so **bằng hash** (sha256[:8]) với các secret đang biết → chỉ báo `file:line + tên credential`, **không** in giá trị | `0` = sạch |

### 10.2. Ghi fingerprint mới (sau khi rotate)

```bash
# In fingerprint của giá trị HIỆN TẠI để owner dán vào inventory.
python3 scripts/verify_secret_rotation.py --record-new                 # tất cả
python3 scripts/verify_secret_rotation.py --record-new jwt_signing_key # một credential
```

Dán giá trị đó vào trường `new_fingerprint` của credential tương ứng trong khối
`INVENTORY-JSON` của `docs/security/secret-rotation-inventory-2026-10-20.md`.

**Riêng `SUPERVISOR_PIN` (6 chữ số)**: `sha256[:8]` của PIN là *tương đương lộ PIN*
(brute-force được). Phải dùng chế độ **salted**:

```bash
export ROTATION_FINGERPRINT_SALT="$(openssl rand -hex 16)"   # lưu ở password manager, KHÔNG commit
python3 scripts/verify_secret_rotation.py --record-new supervisor_pin
# -> supervisor_pin  .env.production:SUPERVISOR_PIN  salted(len=6, sha256=xxxxxxxx)
```

Khi chạy `--check-env` mà **thiếu** `ROTATION_FINGERPRINT_SALT` ⇒ script báo
`UNKNOWN` (exit ≠ 0) — cố ý, để không ai vô tình dùng hash không salt.

### 10.3. Biến môi trường cho `--check-provider`

| Biến | Bắt buộc? | Ý nghĩa |
|---|---|---|
| `CLOUDFLARE_OLD_TOKEN` | để chứng minh token Cloudflare cũ chết | giá trị token cũ (do owner cung cấp lúc chạy; **không** ghi vào file) |
| `CLOUDFLARE_NEW_TOKEN` | không | token mới — dùng để chứng minh token mới sống |
| `SMTP_USER` | có (khi probe Gmail) | địa chỉ Gmail (không nhạy cảm) |
| `SMTP_OLD_PASSWORD` | để chứng minh app password cũ chết | app password cũ |
| `SMTP_NEW_PASSWORD` | không | app password mới |
| `SMTP_HOST` / `SMTP_PORT` | không | mặc định `smtp.gmail.com` / `587` |
| `API_BASE_URL` + `OLD_ACCESS_TOKEN` | để chứng minh JWT cũ chết | URL API + access token đã cấp trước khi rotate |
| `NEW_ACCESS_TOKEN` | không | access token mới |
| `OLD_SECRET_<CRED_ID>` | không | giá trị **cũ** của 1 credential (vd `OLD_SECRET_SMTP_PASSWORD`) để `--check-artifacts` dò được artifact chứa secret đã bị thay |

Ví dụ (không in ra giá trị):

```bash
CLOUDFLARE_OLD_TOKEN="$OLD_CF" SMTP_USER=… SMTP_OLD_PASSWORD="$OLD_APW" \
  API_BASE_URL=https://… OLD_ACCESS_TOKEN="$OLD_AT" \
  python3 scripts/verify_secret_rotation.py --check-provider
```

### 10.4. Vì sao `--check-env` **không** chạy trong CI

CI không có env production ⇒ `--check-env` ở CI sẽ báo FAIL vô nghĩa. CI chỉ chạy
`scripts/check_no_secrets.py` (fail khi tracked file chứa credential) + gate "không
có file `.env` bị commit". Bằng chứng rotate là việc của **máy deploy / owner**,
chạy `--check-env` + `--check-provider` sau khi phát hành secret mới.

---

## 11. Ai làm gì — bảng phân công & ký hiệu xác nhận

| # | Việc | Ai làm | Lệnh / nơi thực hiện | Ký hiệu xác nhận (bằng chứng) |
|---|---|---|---|---|
| 1 | Sinh key mới cho `BANKOPS_SIGNING_KEY` | Owner | `python3 -c "import secrets; print(secrets.token_hex(32))"` | `--record-new jwt_signing_key` → fingerprint mới |
| 2 | Cấp `BANKOPS_SIGNING_KEY` cho GitHub Actions | Owner | `gh secret set BANKOPS_SIGNING_KEY --repo imtarget05/QuanLyKho` | `gh secret list` |
| 3 | Cấp `BANKOPS_SIGNING_KEY` cho k8s Secret | Owner + SRE | `kubectl create secret generic bankops-secrets --from-literal=BANKOPS_SIGNING_KEY=… --dry-run=client -o yaml \| kubectl apply -f -` | `kubectl get secret bankops-secrets -o yaml` (chỉ xem **key**) |
| 4 | Gỡ `SECRET_KEY` (legacy) | Owner + SRE | `kubectl patch secret bankops-secrets --type=json -p '[{"op":"remove","path":"/data/SECRET_KEY"}]'` + `gh secret delete SECRET_KEY` | `--check-env` báo PASS cho `legacy_secret_key` |
| 5 | Tạo + cấp Gmail app password mới, xoá app password cũ | Owner (Google account) | `https://myaccount.google.com/apppasswords` | `--check-provider` → `smtp_password PASS (535)` |
| 6 | Tạo + revoke Cloudflare API token cũ | Owner (Cloudflare) | `https://dash.cloudflare.com/profile/api-tokens` | `--check-provider` → `cloudflare_api_token PASS` |
| 7 | PIN production mới (6 chữ số, ≠ PIN demo) | Owner | `python3 -c "import secrets; print(f'{secrets.randbelow(1000000):06d}')"` | `--record-new supervisor_pin` (salted) + duyệt 4-mắt 200 / 403 |
| 8 | `BANKOPS_SESSION_SECRET` mới | Owner | `python3 -c "import secrets; print(secrets.token_urlsafe(48))"` | `--check-env` PASS |
| 9 | `BACKUP_GPG_PASSPHRASE` mới + re-encrypt backup cũ | Owner (giữ keyring) | xem mục 5/6 | `gpg --decrypt` OK bằng passphrase mới |
| 10 | `DATABASE_URL` dev (nếu DB dev có dữ liệu thật) | Owner | `ALTER USER … WITH PASSWORD` | `--check-env` PASS |
| 11 | Cập nhật file local (`.env`, `.env.production`, `backend/.env`) | Owner | dán tay (file gitignored) | `--check-env` PASS |
| 12 | Bật GitHub secret scanning + push protection | Owner (repo settings) | `https://github.com/imtarget05/QuanLyKho/settings/security_analysis` | ảnh chụp màn hình setting |
| 13 | Duyệt & thực hiện rewrite history | Owner (repo admin) | `git filter-repo --replace-text <file>` + `git push --force --mirror origin` | `git log --all -S<giá trị cũ>` → 0 kết quả |
| 14 | Fix `admin_users.py:351` (default PIN không gate demo) | Worker khác (PR) | PR riêng | test: tạo user ở production → `pin_hash is None` |
| 15 | Fix `scripts/sync_github_secrets.sh` (in giá trị secret; thiếu 4 biến) | Worker khác (PR) | PR riêng | `rg set_secret scripts/sync_github_secrets.sh` |
| 16 | Bổ sung 3 key còn thiếu vào `infra/k8s/base/secret-template.yaml` + `.env.example` | Worker khác (PR) | PR riêng | `rg BANKOPS_SIGNING_KEY infra/k8s/base/secret-template.yaml` |
| 17 | Gỡ shim `SECRET_KEY` ở `backend/entrypoint.sh:10-14` | Worker khác (PR, **sau** #4) | PR riêng | log entrypoint không còn nhánh fallback |
| 18 | Chạy `--check-env` + `--check-provider` + `--check-artifacts` | Owner (máy có secret store) | xem mục 10 | **cả 3 exit 0** |
| 19 | Mở/đóng G2 | Owner | — | bảng mục 12 đầy đủ cột Evidence |

> **Agent (SRE/automation) không làm:** #1–#13 (cần tài khoản provider / repo admin).
> Agent **đã làm** ở wave này: audit references, inventory, `verify_secret_rotation.py`,
> mở rộng `check_no_secrets.py`, wire CI secret-scan fail, tài liệu runbook.

---

## 12. Checklist nghiệm thu có cột Evidence

Điền **Evidence** bằng *bằng chứng có thể kiểm lại lại*, không phải "đã làm".
`Evidence` tối thiểu = fingerprint mới / mã HTTP / commit hash / ảnh chụp màn hình.

| # | Hạng mục | Evidence (điền sau khi rotate) | Người | Ngày |
|---|---|---|---|---|
| 1 | `BANKOPS_SIGNING_KEY` đã rotate + token cũ 401 | | | |
| 2 | `BANKOPS_SIGNING_KEY` đã có trong k8s Secret | | | |
| 3 | `SECRET_KEY` đã gỡ khỏi k8s / GitHub / `.env.production` | | | |
| 4 | `BANKOPS_SESSION_SECRET` đã rotate (salted/plain fingerprint) | | | |
| 5 | `SMTP_PASSWORD` đã rotate | | | |
| 6 | Gmail app password **cũ** trả 535 | | | |
| 7 | Gmail app password **mới** login OK | | | |
| 8 | `SUPERVISOR_PIN` đã rotate (salted fingerprint) | | | |
| 9 | PIN cũ bị từ chối 403 / PIN mới được chấp nhận | | | |
| 10 | `CLOUDFLARE_API_TOKEN` đã rotate | | | |
| 11 | Cloudflare token cũ ≠ 200 | | | |
| 12 | `BACKUP_GPG_PASSPHRASE` đã rotate + backup cũ re-encrypt | | | |
| 13 | `DATABASE_URL` dev đã rotate (nếu áp dụng) | | | |
| 14 | `--check-env` exit 0 | | | |
| 15 | `--check-provider` exit 0 | | | |
| 16 | `--check-artifacts` exit 0 | | | |
| 17 | `python3 scripts/check_no_secrets.py` exit 0 | | | |
| 18 | `python3 scripts/check_no_secrets.py --local` không còn finding | | | |
| 19 | GitHub secret scanning **Enabled** | | | |
| 20 | GitHub push protection **Enabled** | | | |
| 21 | Git history đã rewrite (nếu quyết định) + mọi clone đã đồng bộ | | | |
| 22 | PR fix `admin_users.py:351` đã merge | | | |
| 23 | PR fix `sync_github_secrets.sh` đã merge | | | |
| 24 | PR bổ sung key vào `secret-template.yaml` / `.env.example` đã merge | | | |
| 25 | PR gỡ shim `entrypoint.sh` đã merge | | | |

> **G2 chỉ đóng được khi mọi dòng trên đã đầy cột Evidence.**
> Trước wave này, **G2 chưa đóng được**: chưa credential nào được rotate, mọi
> `--check-env` / `--check-provider` đều FAIL.
