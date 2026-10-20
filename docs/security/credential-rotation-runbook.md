# Credential Rotation Runbook — BankOps / QuanLyKho

**Owner:** chủ tài khoản (account owner) + SRE/ops
**Scope:** các credential đã bị ghi ra file local / lịch sử git (S10, 2026-10-20)
**Trạng thái sau S10:** `CONTAINED-PENDING-ROTATION` — đường lộ trong repo đã đóng,
nhưng **credential cũ vẫn còn hiệu lực** ở phía provider. Bước rotate phải do người
giữ tài khoản thực hiện; agent/automation **không** tự revoke.

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
| 4 | `SMTP_PASSWORD` (Gmail app password) | `qavo…(len=16, sha256=8e2b3b9b)` | `.env:21`, `backend/.env:26` | **CÓ** — `docker-compose.yml` @ `53be143` (còn ở `origin/main`) | **P0** |
| 5 | `CLOUDFLARE_API_TOKEN` | `cfut…(len=53, sha256=a9d3b0e0)` | `.env:7`, `.env.production:10`, `backend/.env:31`, `infra/k8s/base/secret-production.yaml:14` | Không | **P1** |
| 6 | `BACKUP_GPG_PASSPHRASE` | `qwfb…(len=32, sha256=6a2bee79)` | `.env.production:20`, `infra/k8s/base/secret-production.yaml:18` | Không | **P1** |
| 7 | `SUPERVISOR_PIN` | `1234…(len=6, sha256=8d969eef)` | `.env.production:5`, `infra/k8s/base/secret-production.yaml:12` | **CÓ** — giá trị này còn nằm trong file tracked (`infra/k8s/base/secret-template.yaml`, `docs/16-secrets-migration.md`, README, seed code) | **P1** |
| 8 | `DATABASE_URL` (dev Postgres `bankops:bankops@localhost`) | `post…(len=59, sha256=3d4d0275)` | `.env:3`, `.env.production:3`, `backend/.env:3` | Có (nhưng chỉ là credential DB **dev local**, không phải prod) | P3 |

Ghi chú: `SUPERVISOR_PIN` là giá trị **yếu, đã công khai trong repo** — sau khi rotate
production PIN sang giá trị mạnh, mọi tài liệu/demo cũng phải dùng PIN demo riêng.

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

Sinh mới (`python3 -c "import secrets; print(secrets.token_hex(32))"`), phát hành qua
`gh secret set SECRET_KEY --repo imtarget05/QuanLyKho`, cập nhật `.env.production:4`
và `infra/k8s/base/secret-production.yaml:11`. Verify: app khởi động OK
(`backend/app/config.py` fail-fast khi thiếu secret ở non-demo) + endpoint `/health`
trả 200. Rollback: đặt lại giá trị cũ + rollback deploy.

### 6.3. `BANKOPS_SESSION_SECRET` (P0)

Sinh mới, `gh secret set BANKOPS_SESSION_SECRET --repo imtarget05/QuanLyKho`, cập nhật
`backend/.env:18`. Verify: cookie/session cũ bị từ chối (đăng nhập lại được), session
mới hoạt động. Rollback: đặt lại giá trị cũ (kèm rollback deploy).

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
