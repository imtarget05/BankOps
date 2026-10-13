# 🚀 BankOps — Hướng dẫn Deploy Cloudflare (Zero Cold Start)

> **Mục tiêu**: Nhân viên thu chi mở app lúc **bất kỳ giờ nào** đều dùng được ngay, không chờ server khởi động.

## Trạng thái triển khai (2026-10-13)

- Worker config/typecheck/dry-run đã xác minh cho production và staging; chưa deploy thật.
- Revoke/rotate mọi Cloudflare API token đã từng có trong repository history trước khi cấp credentials mới.
- Production cần secret `SUPERVISOR_PIN` riêng, Neon `DATABASE_URL`, `JWT_SECRET`; staging secrets phải set tách riêng.
- Chỉ dùng `123456` khi `APP_ENV=demo`; không dùng PIN demo như production credential.

## Tổng quan kiến trúc

```
[Nhân viên] → [Cloudflare Pages - Flutter Web] → [Cloudflare Workers API] → [Neon PostgreSQL]
                 CDN toàn cầu, instant             V8 isolate, < 5ms           Serverless pool
                 (không cold start)                (không cold start)           (HTTP transport)
```

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

## BƯỚC 3 — Setup Cloudflare Workers API (10 phút)

### 3a. Đăng nhập Cloudflare

```bash
cd infra/cloudflare-worker
npm install  # cài dependencies
npx wrangler login  # mở browser đăng nhập
```

### 3b. Workers AI và rate limits

`infra/cloudflare-worker/wrangler.toml` đã khai báo Workers AI binding (`AI`) và hai Rate Limiting bindings (`AI_CHAT_LIMIT`, `AI_ASSESSMENT_LIMIT`). Chọn các `namespace_id` dạng số chưa dùng trong account Cloudflare của bạn; production và staging phải dùng namespace IDs riêng. Wrangler v4.36.0 trở lên là bắt buộc cho Rate Limiting bindings.

Cloudflare Rate Limiting là permissive/eventually consistent và được tính riêng theo Cloudflare location; dùng để giới hạn chi phí AI, không làm ràng buộc kiểm soát nghiệp vụ hay kế toán chính xác.

### 3c. Đặt secrets

```bash
# DATABASE_URL từ Neon (dùng pooled endpoint, không cần đổi sang asyncpg)
echo "postgresql://user:password@ep-xxx.ap-southeast-1.aws.neon.tech/bankops?sslmode=require" \
  | npx wrangler secret put DATABASE_URL

# JWT secret (tạo ngẫu nhiên)
openssl rand -hex 32 | npx wrangler secret put JWT_SECRET

# Session secret (giữ tương thích ứng dụng)
openssl rand -hex 32 | npx wrangler secret put SESSION_SECRET

# High-risk approval PIN: MUST be unique and secret in production.
# The fixed PIN 123456 is accepted only when APP_ENV=demo.
read -s "SUPERVISOR_PIN?Enter production supervisor PIN: "
echo "$SUPERVISOR_PIN" | npx wrangler secret put SUPERVISOR_PIN
unset SUPERVISOR_PIN

# Secrets for staging must be set separately with --env staging.
```

Also configure the required Workers AI REST credentials only on FastAPI deployments that use `AI_PROVIDER=cloudflare` (`CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_API_TOKEN`). Store them as provider secrets, not in Wrangler vars or source.

### 3d. Deploy Worker

After replacing the example rate-limit namespace IDs with unused numeric IDs for your Cloudflare account, and setting production secrets:

```bash
npx wrangler deploy --env=""
# Output: https://bankops-api.<account-name>.workers.dev
```

Staging needs its own secrets and namespaces before deployment:

```bash
npx wrangler secret put DATABASE_URL --env staging
npx wrangler secret put JWT_SECRET --env staging
npx wrangler secret put SESSION_SECRET --env staging
npx wrangler secret put SUPERVISOR_PIN --env staging
npx wrangler deploy --env staging
```

### 3e. Test

```bash
curl https://bankops-api.<account-name>.workers.dev/api/v1/health/live
# {"status":"alive","runtime":"cloudflare-workers",...}

curl -X POST https://bankops-api.<account-name>.workers.dev/api/v1/auth/login \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin&password=demo123"
# {"access_token":"...","user":{...}}
```

---

## BƯỚC 4 — Build & Deploy Flutter Web (15 phút)

### 4a. Build

```bash
cd frontend
flutter pub get

# Thay <WORKER_URL> bằng URL Worker ở bước 3d
flutter build web \
  --release \
  --web-renderer canvaskit \
  --dart-define=API_BASE_URL=https://bankops-api.<account-name>.workers.dev

# Output: frontend/build/web/
```

### 4b. Deploy lên Cloudflare Pages

```bash
cd infra/cloudflare-worker  # wrangler đang ở đây
npx wrangler pages project create bankops-web  # lần đầu

npx wrangler pages deploy ../../frontend/build/web \
  --project-name=bankops-web
# URL: https://bankops-web.pages.dev
```

### 4c. Copy _headers và _redirects vào build

```bash
cp infra/cloudflare-pages/_headers frontend/build/web/
cp infra/cloudflare-pages/_redirects frontend/build/web/
# Redeploy nếu cần
```

---

## BƯỚC 5 — Cấu hình CI/CD GitHub Actions

Vào **GitHub → Settings → Secrets and variables → Actions**, thêm:

| Secret | Giá trị |
|--------|---------|
| `CLOUDFLARE_API_TOKEN` | Tạo tại https://dash.cloudflare.com/profile/api-tokens (template: "Edit Cloudflare Workers") |
| `CLOUDFLARE_ACCOUNT_ID` | Xem ở sidebar Cloudflare dashboard |
| `API_BASE_URL` | `https://bankops-api.<account>.workers.dev` |

Từ nay, mỗi khi push lên `main`:
- `backend/**` thay đổi → không deploy (Worker không cần Python)
- `infra/cloudflare-worker/**` thay đổi → tự deploy Worker
- `frontend/**` thay đổi → tự build Flutter + deploy Pages

---

## BƯỚC 6 — Custom Domain (tùy chọn)

**Worker:**
```bash
# Thêm vào wrangler.toml:
routes = [{ pattern = "api.bankops.example.com/*", zone_name = "example.com" }]
```

**Pages:**
Vào Cloudflare Dashboard → Pages → bankops-web → Custom domains → Add domain

---

## Kiểm tra Zero Cold Start

```bash
# Test nhiều lần liên tiếp - thời gian phải đồng đều
for i in 1 2 3 4 5; do
  time curl -s https://bankops-api.<account>.workers.dev/api/v1/health/live -o /dev/null
done

# Kết quả mong đợi: ~50-200ms mỗi request, không có spike lớn
```

---

## Theo dõi & Monitoring

- **Cloudflare Analytics**: https://dash.cloudflare.com → Workers → bankops-api → Analytics
- **Logs thời gian thực**: `npx wrangler tail` (từ terminal local)
- **Neon Monitoring**: https://console.neon.tech → Monitoring

---

## Troubleshooting

| Vấn đề | Giải pháp |
|--------|-----------|
| `DATABASE_URL not set` | Chạy lại `wrangler secret put DATABASE_URL` |
| Rate limit binding lỗi khi deploy | Dùng wrangler >= 4.36.0; `namespace_id` là số tự chọn (1–9999999999), không phải KV ID |
| Flutter app không gọi được API | Kiểm tra `API_BASE_URL` trong build args |
| CORS error | CORS đã cấu hình `*` cho demo; nếu production thêm domain vào `cors()` trong `index.ts` |
| `bcrypt verify failed` | Password hash từ FastAPI cũ vẫn dùng được vì `bcryptjs` tương thích |

---

## Chi phí (Free tier)

| Service | Free limit | BankOps dùng |
|---------|-----------|--------------|
| CF Workers | 100,000 req/ngày | ~1,000 req/ngày (team nhỏ) ✅ |
| CF Pages | Unlimited bandwidth | ✅ |
| Neon PostgreSQL | 0.5 GB, 10 branches | ~50 MB ✅ |

**Tổng chi phí: \$0/tháng** 🎉
