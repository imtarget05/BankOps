# 15 — Pre-Deploy Security Checklist

> **Purpose**: Block public deploy until every item is checked. Do NOT deploy to production until all phases are complete.
>
> **Last reviewed**: 2026-10-13

---

## Phase 1: Token Rotation — CRITICAL

A Cloudflare API token was committed to git history. This must be rotated **before** any other step.

- [ ] **Revoke the leaked token** in Cloudflare dashboard:
  - Go to https://dash.cloudflare.com/profile/api-tokens
  - Find the token with prefix `cfut_WtI4hAp3…` (xem danh sách token đầy đủ trong dashboard)
  - Click **Delete** / **Revoke**
  - Confirm revocation

- [ ] **Create a new API token** with least-privilege scopes:
  - Template: **"Edit Cloudflare Workers"** (or custom)
  - Required permissions only:
    - `Workers Scripts` → Edit
    - `Account` → Read (for `wrangler whoami`)
  - Do NOT grant: Zone Edit, DNS Edit, Account Settings, or any admin scope
  - Set Account Resources to your specific account only
  - Set TTL to 90 days (or shorter)

- [ ] **Store the new token in a password manager** (1Password, Bitwarden, etc.)
  - Never commit to git
  - Never store in `.env` files that could be committed
  - Never share in chat/Slack/email

- [ ] **Verify git history has been scrubbed**:
  ```bash
  git log --all -p | grep cfut_
  ```
  Expected: **0 results**. If results appear, the token is still in history — use `git filter-repo` or BFG Repo-Cleaner to purge it, then force-push and have all collaborators re-clone.

- [ ] **Verify no other secrets in git history**:
  ```bash
  git log --all -p | grep -iE '(api[_-]?key|secret|password|token|BEGIN.*PRIVATE)'
  ```
  Expected: **0 results** (excluding false positives from dependency files)

---

## Phase 2: Cloudflare Resources

- [ ] **Rate Limiting bindings dùng số tự chọn (không cần KV)**:
  - `AI_CHAT_LIMIT` / `AI_ASSESSMENT_LIMIT`: `namespace_id` là số tự chọn 1–9999999999, KHÔNG phải KV namespace ID — không cần tạo KV namespace
  - Production (`1001`/`1002`) và staging (`2001`/`2002`) phải dùng số khác nhau; đổi nếu số đó đã được Worker khác trong account dùng
  - Yêu cầu wrangler >= 4.36.0

- [ ] **Verify `wrangler.toml`**:
  - KV namespace đã bị loại khỏi config (binding `BANKOPS_KV` không được dùng trong code)
  - Verify with: `npx wrangler deploy --dry-run` — bindings `AI`, `AI_CHAT_LIMIT`, `AI_ASSESSMENT_LIMIT` phải xuất hiện trong output

- [ ] **Set secrets in wrangler** (production):
  ```bash
  echo "<DATABASE_URL>" | npx wrangler secret put DATABASE_URL
  echo "<JWT_SECRET>" | npx wrangler secret put JWT_SECRET
  echo "<SESSION_SECRET>" | npx wrangler secret put SESSION_SECRET
  echo "<GOOGLE_CLIENT_ID>" | npx wrangler secret put GOOGLE_CLIENT_ID
  echo "<SUPERVISOR_PIN>" | npx wrangler secret put SUPERVISOR_PIN
  ```

- [ ] **Set secrets in wrangler** (staging — separate values):
  ```bash
  echo "<STAGING_DATABASE_URL>" | npx wrangler secret put DATABASE_URL --env staging
  echo "<STAGING_JWT_SECRET>" | npx wrangler secret put JWT_SECRET --env staging
  echo "<STAGING_SESSION_SECRET>" | npx wrangler secret put SESSION_SECRET --env staging
  echo "<STAGING_SUPERVISOR_PIN>" | npx wrangler secret put SUPERVISOR_PIN --env staging
  ```

- [ ] **Verify `wrangler whoami`** works with the new token:
  ```bash
  npx wrangler whoami
  ```
  Expected: shows your account name and ID, no auth errors.

---

## Phase 3: Production Secrets

- [ ] **Provision Neon project**:
  - Go to https://console.neon.tech
  - Create project: `bankops-production`
  - Region: **Asia Pacific (Singapore)** (or closest to users)
  - Copy the **pooled** connection string (contains `-pooler` in host)

- [ ] **Create production database**:
  - Neon auto-creates a `neondb` database; rename or create `bankops` if preferred
  - Run migrations: `poetry run alembic upgrade head`
  - Run seed: `poetry run python -c "from app.seed import seed_demo; import asyncio; asyncio.run(seed_demo())"`

- [ ] **Generate JWT secret**:
  ```bash
  openssl rand -base64 32
  ```
  Store the output in password manager. Use for `JWT_SECRET`.

- [ ] **Generate session secret**:
  ```bash
  openssl rand -base64 32
  ```
  Store the output in password manager. Use for `SESSION_SECRET`.

- [ ] **Set up Google OAuth credentials** (if using Google sign-in):
  - Go to https://console.cloud.google.com
  - Create OAuth 2.0 Client ID (Web application)
  - Add authorized redirect URIs:
    - `https://<production-domain>/api/v1/auth/google/callback`
    - `https://<staging-domain>/api/v1/auth/google/callback`
  - Store Client ID and Client Secret in password manager
  - Set as wrangler secrets: `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`

- [ ] **Verify ALL secrets are in wrangler secret store** (NOT in `.env`):
  ```bash
  npx wrangler secret list
  npx wrangler secret list --env staging
  ```
  Expected: DATABASE_URL, JWT_SECRET, SESSION_SECRET, SUPERVISOR_PIN, GOOGLE_CLIENT_ID (if applicable)

- [ ] **Remove secrets from `.env`**:
  - Delete or empty all production secret values from `.env`
  - Ensure `.env` is in `.gitignore`
  - Verify: `git diff .env` shows no secret values

---

## Phase 4: Domain & DNS

- [ ] **Register domain** (if not already done):
  - Use any registrar (Namecheap, Cloudflare Registrar, GoDaddy, etc.)
  - Recommended: transfer to Cloudflare for unified DNS management

- [ ] **Add domain to Cloudflare**:
  - Go to https://dash.cloudflare.com → Add Site
  - Enter your domain
  - Update nameservers at your registrar to point to Cloudflare

- [ ] **Create DNS record pointing to worker**:
  - Type: `CNAME`
  - Name: `api` (or your preferred subdomain)
  - Target: `<worker-name>.<account>.workers.dev`
  - Proxy status: **Proxied** (orange cloud)

- [ ] **Enable SSL/TLS**:
  - Go to SSL/TLS → Overview
  - Set encryption mode: **Full (strict)**
  - Enable "Always Use HTTPS"
  - Enable "Automatic HTTPS Rewrites"

- [ ] **Verify SSL works**:
  ```bash
  curl -vI https://api.<your-domain>/api/v1/health/live
  ```
  Expected: HTTP 200, valid certificate, no SSL warnings.

---

## Phase 5: Validation

- [ ] **Deploy to staging**:
  ```bash
  npx wrangler deploy --env staging
  ```
  Expected: successful deployment, no errors.

- [ ] **Verify health endpoint**:
  ```bash
  curl https://<staging-url>/api/v1/health/live
  ```
  Expected: `{"status":"alive","runtime":"cloudflare-workers",...}`

- [ ] **Run full test suite**:
  ```bash
  # Backend tests
  cd backend && poetry run pytest

  # Frontend tests
  cd frontend && flutter test

  # Worker tests
  cd infra/cloudflare-worker && npm test
  ```
  Expected: all tests pass, no failures.

- [ ] **Verify AI endpoints work** (no real token in code):
  ```bash
  curl -X POST https://<staging-url>/api/v1/ai/chat \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer <test-token>" \
    -d '{"message":"hello"}'
  ```
  Expected: valid AI response, no 500 errors.

- [ ] **Verify rate limiting works**:
  ```bash
  # Send rapid requests to trigger rate limit
  for i in $(seq 1 20); do
    curl -s -o /dev/null -w "%{http_code}\n" \
      -X POST https://<staging-url>/api/v1/ai/chat \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer <test-token>" \
      -d '{"message":"test"}'
  done
  ```
  Expected: some requests return HTTP 429 after threshold.

- [ ] **Verify CORS is restrictive** (not `*` for production):
  - Check `wrangler.toml` or worker code for CORS config
  - Production should only allow your specific domain(s)

---

## Phase 6: Public Deploy Gate

**Do NOT deploy to production until every item below is checked.**

- [ ] All production secrets provisioned and verified in wrangler
- [ ] Domain + SSL configured and verified
- [ ] Staging validation passed (all tests green)
- [ ] Monitoring/alerting set up:
  - Cloudflare Analytics enabled
  - Neon monitoring enabled
  - Error tracking configured (Sentry, Logpush, or similar)
  - Uptime monitoring (optional but recommended)
- [ ] Rollback plan documented:
  - How to revert worker to previous version: `npx wrangler rollback`
  - How to restore Neon database from backup
  - How to revoke/rotate secrets if compromised
  - Contact list for incident response
- [ ] `.env` contains no production secrets
- [ ] Git history is clean (no secrets in any commit)
- [ ] Team has reviewed and signed off on this checklist

### ONLY THEN — deploy to production:

```bash
npx wrangler deploy
```

---

## Quick Reference: Emergency Contacts

| Issue | Action |
|-------|--------|
| Token leaked again | Revoke immediately → rotate → scrub git history |
| Database compromised | Rotate DATABASE_URL → restore from backup → audit logs |
| SSL broken | Check Cloudflare SSL/TLS settings → set to Full (strict) |
| Worker down | `npx wrangler rollback` → check logs with `npx wrangler tail` |
| Rate limit not working | Verify namespace IDs in `wrangler.toml` → check wrangler version ≥ 4.36.0 |

---

## Sign-off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Developer | | | |
| Security Reviewer | | | |
| Team Lead | | | |
