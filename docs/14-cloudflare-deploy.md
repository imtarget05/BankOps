# Cloudflare: host Flutter Web và provider phụ trợ

> **Trạng thái Phase 0:** FastAPI + PostgreSQL là API nghiệp vụ production duy nhất.
> Cloudflare Pages có thể host Flutter Web; Cloudflare AI có thể là provider mà
> FastAPI gọi. Cloudflare Worker trong repository là implementation cũ/
> compatibility sandbox, **không deploy như API production** và không có cam
> kết feature parity với FastAPI.

## Trạng thái triển khai (2026-10-13)

- Worker config/typecheck chỉ xác minh source legacy build được; không xác minh
  production readiness, parity hay quyền ghi nghiệp vụ.
- Revoke/rotate mọi Cloudflare API token đã từng có trong repository history trước khi cấp credentials mới.
- Production cần secret `SUPERVISOR_PIN` riêng, Neon `DATABASE_URL`, `JWT_SECRET`; staging secrets phải set tách riêng.
- Chỉ dùng `123456` khi `APP_ENV=demo`; không dùng PIN demo như production credential.

## Tổng quan kiến trúc được hỗ trợ

```
[Nhân viên] → [Cloudflare Pages - Flutter Web] → [FastAPI API] → [PostgreSQL]
                 CDN/global static hosting          canonical API       data + transaction owner

                                      FastAPI → [Cloudflare AI, optional provider]
```

Cloudflare Pages không làm Cloudflare Worker trở thành backend. Chỉ cấu hình
`API_BASE_URL` trỏ tới FastAPI đã qua smoke/E2E trên cùng môi trường.

## Yêu cầu

- [ ] Tài khoản [Cloudflare](https://dash.cloudflare.com) (free)
- [ ] Tài khoản [Neon](https://console.neon.tech) (free)
- [ ] Tài khoản [GitHub](https://github.com) (để CI/CD)
- [ ] Node.js 20+, Flutter 3.24+, Python 3.11+, Poetry

---

## BƯỚC 1 — Tạo Neon PostgreSQL (3 phút)

1. Vào https://console.neon.tech → **New Project** → đặt tên `bankops`
2. Chọn region: **Asia Pacific (Singapore)** hoặc gần nhất
3. Sau khi tạo, copy **Connection string (Pooled)**:
   ```
   postgresql://user:password@ep-xxx-xxx.ap-southeast-1.aws.neon.tech/bankops?sslmode=require
   ```
   > ⚠️ Dùng **pooled** endpoint (có `-pooler` trong URL), không phải direct endpoint

---

## BƯỚC 2 — Chạy Migrations & Seed

```bash
cd backend

# Cài dependencies
poetry install

# Đặt DATABASE_URL
export DATABASE_URL="postgresql+asyncpg://user:password@ep-xxx.ap-southeast-1.aws.neon.tech/bankops?sslmode=require"

# Chạy migrations
poetry run alembic upgrade head

# Seed demo data
poetry run python -c "from app.seed import seed_demo; import asyncio; asyncio.run(seed_demo())"
```

---

## Không deploy Cloudflare Worker làm API nghiệp vụ

Các phần hướng dẫn Worker cũ đã được thay thế bằng FastAPI canonical. Không đặt
`DATABASE_URL`, JWT, PIN hay secret nghiệp vụ cho Worker nhằm phục vụ production.
Không chạy `wrangler deploy` cho API cho đến khi một ADR mới phê duyệt proxy mỏng
không-state tới FastAPI và xác nhận contract/E2E parity.

Nếu FastAPI dùng Cloudflare AI, chỉ cấp `CLOUDFLARE_ACCOUNT_ID` và
`CLOUDFLARE_API_TOKEN` cho môi trường FastAPI thông qua secret manager. Các
credential đó không được đặt trong source, Wrangler vars hay Flutter build.

## BƯỚC 3 — Build & deploy Flutter Web lên Cloudflare Pages

### 3a. Đăng nhập Cloudflare

```bash
cd infra/cloudflare-worker
npm install  # cài dependencies
npx wrangler login  # mở browser đăng nhập
```

### 3b. Build

```bash
cd frontend
flutter pub get

# Dùng URL FastAPI của đúng môi trường, không dùng workers.dev URL.
flutter build web \
  --release \
  --web-renderer canvaskit \
  --dart-define=API_BASE_URL=https://api.bankops.example.com

# Output: frontend/build/web/
```

### 3c. Deploy lên Cloudflare Pages

```bash
cd infra/cloudflare-worker  # wrangler đang ở đây
npx wrangler pages project create bankops-web  # lần đầu

npx wrangler pages deploy ../../frontend/build/web \
  --project-name=bankops-web
# URL: https://bankops-web.pages.dev
```

### 3d. Copy _headers và _redirects vào build

```bash
cp infra/cloudflare-pages/_headers frontend/build/web/
cp infra/cloudflare-pages/_redirects frontend/build/web/
# Redeploy nếu cần
```

---

## BƯỚC 4 — CI/CD GitHub Actions

### 5a. Secrets cần thiết

Vào **GitHub → Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Giá trị |
|--------|---------|
| `CLOUDFLARE_API_TOKEN` | Token giới hạn quyền deploy **Pages** (và AI provider nếu FastAPI cần, tách scope/token khi có thể). KHÔNG dùng lại token đã từng dán vào code/docs — revoke token cũ trước khi tạo token mới. |

`API_BASE_URL` là cấu hình release và phải trỏ FastAPI canonical. Không hard-code
account ID hoặc API URL production trong tài liệu/workflow.

### 4b. Quy tắc workflow

Một deploy release phải build Flutter với `API_BASE_URL` FastAPI, chạy migration/
smoke/E2E FastAPI, rồi deploy Pages. Worker legacy chỉ typecheck trong CI; không
được deploy theo push/tag.

| Hành động | Kết quả |
|-----------|---------|
| Release staging | Migrate + smoke/E2E FastAPI staging, sau đó deploy Pages với API staging |
| Release production | Backup/checklist, migrate + smoke/E2E FastAPI production, sau đó deploy Pages với API production |

Quy trình release: lint/typecheck/tests → migrate FastAPI → build Flutter Web với
`--dart-define=API_BASE_URL` đúng môi trường → deploy Pages (kèm
`_headers`/`_redirects`) → smoke test FastAPI `/health/live` và luồng E2E qua
FastAPI.

CI thường (`ci.yml`) chạy trên mỗi push/PR vào `main`: ruff, pytest, Flutter
analyze/test, legacy Worker typecheck và Docker build. Kết quả Worker typecheck
không là điều kiện chứng nhận deploy API.

---

## BƯỚC 5 — Custom Domain (tùy chọn)

**Pages:**
Vào Cloudflare Dashboard → Pages → bankops-web → Custom domains → Add domain


---

## Theo dõi & Monitoring

- **Cloudflare Analytics**: https://dash.cloudflare.com → Pages → project → Analytics
- **API logs/metrics**: quan sát từ deployment FastAPI đã chọn
- **Neon Monitoring**: https://console.neon.tech → Monitoring

---

## Troubleshooting

| Vấn đề | Giải pháp |
|--------|-----------|
| Flutter app không gọi được API | Kiểm tra `API_BASE_URL` trỏ FastAPI và CORS của FastAPI cho domain Pages |
| API health fail | Kiểm tra deployment/log/secret/migration FastAPI; không chuyển traffic sang Worker như fallback |
| Cloudflare AI provider fail | Kiểm tra secret provider tại deployment FastAPI và fallback/abstain của FastAPI |

---

## Chi phí (Free tier)

| Service | Free limit | BankOps dùng |
|---------|-----------|--------------|
| CF Pages | Unlimited bandwidth | ✅ |
| Neon PostgreSQL | 0.5 GB, 10 branches | ~50 MB ✅ |

**Tổng chi phí: \$0/tháng** 🎉
