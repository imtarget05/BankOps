# 11 — Docker, devops, deploy demo

## Local compose đề xuất

Services `postgres`, `api`, `worker`, `frontend-web` (hoặc Flutter run riêng), tùy chọn `mock-google` cho contract test. Chỉ publish API/web cần thiết; DB nội bộ. `docker compose up --build` → migrate → seed demo idempotent → health. Không bake secret vào image. `.env.example` chỉ placeholder: `DATABASE_URL`, `JWT_SIGNING_KEY_REF`, `APP_ENV=demo`, `ALLOWED_ORIGINS`, `CONNECTOR_SECRET_REF`, `SSE_RETENTION_DAYS`.

### Local secrets

Compose starts the demo with email disabled. This is intentional: `docker-compose.yml`
contains no SMTP account, password, or provider default. To test outbound email locally,
copy `backend/.env.example` to the ignored `backend/.env` and put locally-managed SMTP
values in that file. Compose loads that file only when it exists:

```bash
docker compose up --build
```

Never use a real production credential for the demo. Deployment environments must inject
their values from the platform secret manager. Rotate any credential that was ever present
in source, terminal output, or chat, remove it from local files that were shared, and
invalidate active sessions/tokens where the provider supports it.

Before pushing, run the repository guard:

```bash
python3 scripts/check_no_secrets.py
```

## Pipeline

1. Format/lint/typecheck Python/Dart.
2. Unit + PostgreSQL integration tests + OpenAPI diff.
3. Flutter widget/web build; Android/iOS/desktop builds ở runner phù hợp.
4. Dependency/secret scan (`python3 scripts/check_no_secrets.py`, and a CI-integrated
   scanner); build pinned image tags + SBOM nếu pipeline hỗ trợ.
5. Migrate staging, smoke E2E, deploy demo với rollback image; DB rollback bằng forward fix/restore đã diễn tập.

## Deploy topology

Reverse proxy TLS → API; worker process; managed PostgreSQL; secret manager; object storage chỉ nếu file staging cần lưu và có TTL. Health live không phụ thuộc DB, ready có kiểm tra DB. Metrics: API latency/errors, job queue depth/age/failures, outbox lag, SSE connections, reconciliation exceptions, DB pool. Structured logs có trace ID, không log token/raw rows.

## Backup/restore

Backup DB hằng ngày demo, kiểm tra khôi phục định kỳ vào môi trường riêng. Tài liệu hóa RPO/RTO sau khi chọn hạ tầng; trước đó không tuyên bố SLA. Migration trước deploy có snapshot; không seed vào môi trường không phải demo. Feature flags cho connector; mặc định off.
