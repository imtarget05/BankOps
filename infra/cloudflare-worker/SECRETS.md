# BankOps Worker — Secrets & Deployment Guide

## ⚠️ Security Warnings

- **NEVER** commit real tokens, secrets, or API keys to git.
- **NEVER** use a Cloudflare API token inside worker code — the worker uses the native `AI` binding (`c.env.AI`), not an API token.
- The API token is only for `wrangler` CLI operations (deploy, secrets).
- All secrets are injected at runtime via `wrangler secret put` — they are NOT stored in `wrangler.toml`.

---

## 1. Rate Limiting bindings (không cần KV)

`AI_CHAT_LIMIT` và `AI_ASSESSMENT_LIMIT` là **Rate Limiting bindings**. Trường
`namespace_id` trong `wrangler.toml` là **số tự chọn (1–9999999999)** — KHÔNG phải
KV namespace ID và KHÔNG cần tạo KV namespace nào.

- Production đang dùng `1001` / `1002`; staging dùng `2001` / `2002`.
- Nếu số đó đã được Worker khác trong account của bạn dùng, đổi sang số khác;
  production và staging phải dùng số khác nhau.
- Yêu cầu wrangler >= 4.36.0. Xác minh: `npx wrangler deploy --dry-run` — hai
  binding phải xuất hiện trong output.

---

## 2. Set Secrets

### Production
```bash
wrangler secret put DATABASE_URL
wrangler secret put JWT_SECRET
wrangler secret put SESSION_SECRET
wrangler secret put GOOGLE_CLIENT_ID
wrangler secret put SUPERVISOR_PIN
```

### Staging
```bash
wrangler secret put DATABASE_URL --env staging
wrangler secret put JWT_SECRET --env staging
wrangler secret put SESSION_SECRET --env staging
wrangler secret put GOOGLE_CLIENT_ID --env staging
wrangler secret put SUPERVISOR_PIN --env staging
```

Each command prompts you to paste the secret value. The value is encrypted and stored by Cloudflare — it never appears in your source code.

---

## 3. Required Secrets

| Secret | Description |
|--------|-------------|
| `DATABASE_URL` | Neon PostgreSQL connection string (pooled) |
| `JWT_SECRET` | HS256 signing key for JWT tokens |
| `SESSION_SECRET` | Starlette session secret (kept for compatibility; unused on Worker) |
| `GOOGLE_CLIENT_ID` | OAuth audience for Google sign-in |
| `SUPERVISOR_PIN` | Server-side PIN for high-risk approvals. MUST be unique in production; `123456` is accepted only when `APP_ENV=demo` |

---

## 4. Deploy

### Production
```bash
wrangler deploy
```

### Staging
```bash
wrangler deploy --env staging
```

---

## 5. Verify

After deploying, check that the worker is live:

```bash
# Production
curl https://bankops-api.<your-subdomain>.workers.dev/api/v1/health

# Staging
curl https://bankops-api-staging.<your-subdomain>.workers.dev/api/v1/health
```

---

## 6. Checklist Before First Deploy

- [ ] Rate limit `namespace_id` values are unused numbers in your account (prod ≠ staging)
- [ ] All 5 secrets set for prod (`DATABASE_URL`, `JWT_SECRET`, `SESSION_SECRET`, `GOOGLE_CLIENT_ID`, `SUPERVISOR_PIN`)
- [ ] All 5 secrets set for staging (separate values)
- [ ] `APP_ENV` is `"production"` in the top-level `[vars]` and `"staging"` in `[env.staging.vars]`
- [ ] No real secrets or tokens are committed to git