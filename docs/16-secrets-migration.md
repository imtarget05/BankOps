# 16 — Secrets Migration Guide

> **Purpose**: Step-by-step guide to migrate from `.env` files to Cloudflare Wrangler secrets, handle transitions, rotate secrets, and respond to leaks.
>
> **Last reviewed**: 2026-10-13
>
> **⚠️ SUPERSEDED 2026-10-14.** Hướng dẫn này migrate secrets sang **Cloudflare Wrangler** — không còn là đích deploy
> (ADR-0001: API chạy trên Modal). Secrets production hiện nằm trong **Modal secret `bankops-api`**
> (`DATABASE_URL`, `BANKOPS_SIGNING_KEY`, `BANKOPS_SESSION_SECRET`, `ALLOWED_ORIGINS`, `SUPERVISOR_PIN`, `APP_ENV`, `AI_PROVIDER`).
> Các checkbox pre-migration dưới đây chỉ còn giá trị tham khảo — cố ý để trống vì luồng wrangler-secrets không được thực thi.

---

## Table of Contents

1. [Why Migrate from `.env` to Wrangler Secrets?](#why-migrate)
2. [Pre-Migration Checklist](#pre-migration-checklist)
3. [Migration Steps](#migration-steps)
4. [Handling the Transition Period](#transition-period)
5. [Rotating Secrets](#rotating-secrets)
6. [Emergency: What to Do If a Secret Leaks](#emergency-leak)
7. [Best Practices](#best-practices)

---

## Why Migrate from `.env` to Wrangler Secrets? {#why-migrate}

| Risk with `.env` | Wrangler Secrets Solution |
|-------------------|---------------------------|
| Accidentally committed to git | Never leaves your terminal; stored encrypted in Cloudflare |
| Visible in CI/CD logs | Injected at runtime; never logged |
| Shared via chat/email for debugging | No need to share; each developer sets their own |
| Same secret across environments | Separate secrets per environment (production, staging) |
| No audit trail | Cloudflare dashboard shows when secrets were last updated |

---

## Pre-Migration Checklist {#pre-migration-checklist}

Before starting the migration:

- [ ] `wrangler` is installed and authenticated (`npx wrangler whoami` works)
- [ ] You have a password manager ready (1Password, Bitwarden, etc.)
- [ ] You know which secrets are currently in `.env`
- [ ] You have access to the Cloudflare dashboard
- [ ] You have a staging environment to test the migration first
- [ ] All team members are aware of the migration timeline

---

## Migration Steps {#migration-steps}

### Step 1: Inventory Current Secrets

List all secrets currently in `.env`:

```bash
# Show secret names only (not values)
grep -oE '^[A-Z_]+=' .env | tr -d '='
```

Document each secret:

| Secret Name | Environment | Used In | Notes |
|-------------|-------------|---------|-------|
| `DATABASE_URL` | production, staging | Worker, Alembic | Neon pooled connection string |
| `JWT_SECRET` | production, staging | Worker | `openssl rand -base64 32` |
| `SESSION_SECRET` | production, staging | Worker | `openssl rand -base64 32` |
| `SUPERVISOR_PIN` | production, staging | Worker | 6+ digit PIN |
| `GOOGLE_CLIENT_ID` | production, staging | Worker | From Google Cloud Console |
| `GOOGLE_CLIENT_SECRET` | production, staging | Worker | From Google Cloud Console |

### Step 2: Generate New Secrets (Recommended)

For each secret, generate a fresh value. This ensures that even if the old `.env` was compromised, the new secrets are clean.

```bash
# JWT secret
openssl rand -base64 32

# Session secret
openssl rand -base64 32

# Supervisor PIN (choose a strong PIN, not 123456)
# Store in password manager
```

For `DATABASE_URL`, get the connection string from Neon console.

For Google OAuth, create new credentials in Google Cloud Console.

### Step 3: Set Secrets in Wrangler (Staging First)

Always migrate staging first to validate the process.

```bash
cd infra/cloudflare-worker

# Staging secrets
echo "<STAGING_DATABASE_URL>" | npx wrangler secret put DATABASE_URL --env staging
echo "<STAGING_JWT_SECRET>" | npx wrangler secret put JWT_SECRET --env staging
echo "<STAGING_SESSION_SECRET>" | npx wrangler secret put SESSION_SECRET --env staging
echo "<STAGING_SUPERVISOR_PIN>" | npx wrangler secret put SUPERVISOR_PIN --env staging
echo "<STAGING_GOOGLE_CLIENT_ID>" | npx wrangler secret put GOOGLE_CLIENT_ID --env staging
echo "<STAGING_GOOGLE_CLIENT_SECRET>" | npx wrangler secret put GOOGLE_CLIENT_SECRET --env staging
```

### Step 4: Verify Staging Deployment

```bash
# Deploy to staging
npx wrangler deploy --env staging

# Verify secrets are accessible
curl https://<staging-worker-url>/api/v1/health/live

# Run tests against staging
# (use your staging API URL)
```

If tests pass, proceed to production.

### Step 5: Set Secrets in Wrangler (Production)

```bash
# Production secrets
echo "<PROD_DATABASE_URL>" | npx wrangler secret put DATABASE_URL
echo "<PROD_JWT_SECRET>" | npx wrangler secret put JWT_SECRET
echo "<PROD_SESSION_SECRET>" | npx wrangler secret put SESSION_SECRET
echo "<PROD_SUPERVISOR_PIN>" | npx wrangler secret put SUPERVISOR_PIN
echo "<PROD_GOOGLE_CLIENT_ID>" | npx wrangler secret put GOOGLE_CLIENT_ID
echo "<PROD_GOOGLE_CLIENT_SECRET>" | npx wrangler secret put GOOGLE_CLIENT_SECRET
```

### Step 6: Verify All Secrets Are Set

```bash
# List production secrets
npx wrangler secret list

# List staging secrets
npx wrangler secret list --env staging
```

Verify each secret name appears in the output. **Values are never shown** — this is a security feature.

### Step 7: Remove Secrets from `.env`

```bash
# Edit .env and remove or comment out all production secrets
# Keep only non-sensitive config like:
# APP_ENV=production
# LOG_LEVEL=info
# API_PORT=8080
```

### Step 8: Update `.gitignore`

Ensure `.env` is in `.gitignore`:

```bash
# Check if .env is ignored
git check-ignore .env

# If not, add it to .gitignore
echo ".env" >> .gitignore
echo ".env.*" >> .gitignore
```

### Step 9: Update Application Code

Ensure your application reads secrets from the environment (which wrangler injects) rather than from `.env`:

```typescript
// Worker code — secrets are available as environment variables
const dbUrl = env.DATABASE_URL;  // Injected by wrangler at runtime
const jwtSecret = env.JWT_SECRET;
```

No code changes should be needed if your app already uses `process.env` or similar — wrangler secrets are injected as environment variables.

### Step 10: Verify Production Deployment

```bash
# Deploy to production
npx wrangler deploy

# Verify
curl https://<prod-worker-url>/api/v1/health/live
```

---

## Handling the Transition Period {#transition-period}

During migration, you may need both `.env` and wrangler secrets to coexist.

### Strategy: Environment Detection

```typescript
// In your worker code, detect the environment
const isLocal = !env.DATABASE_URL;  // No secret = local dev

if (isLocal) {
  // Load from .env (local development only)
  const dbUrl = process.env.DATABASE_URL;
} else {
  // Use wrangler-injected secret
  const dbUrl = env.DATABASE_URL;
}
```

### Strategy: Gradual Rollout

1. **Week 1**: Set wrangler secrets for staging only. Keep `.env` for local dev.
2. **Week 2**: Validate staging works. Set wrangler secrets for production.
3. **Week 3**: Remove secrets from `.env`. Update `.gitignore`.
4. **Week 4**: Audit — verify no secrets in git history, no secrets in logs.

### Local Development Without `.env`

For local development, use `.env.example` (committed) with placeholder values:

```bash
# .env.example — safe to commit
DATABASE_URL=postgresql://user:pass@localhost:5432/bankops
JWT_SECRET=replace-with-openssl-rand-base64-32
SESSION_SECRET=replace-with-openssl-rand-base64-32
SUPERVISOR_PIN=123456
```

```bash
# Local setup
cp .env.example .env
# Edit .env with real local values
```

---

## Rotating Secrets {#rotating-secrets}

### When to Rotate

| Secret | Rotation Frequency | Trigger |
|--------|-------------------|---------|
| `JWT_SECRET` | 90 days | Scheduled, or if a developer leaves |
| `SESSION_SECRET` | 90 days | Scheduled, or if a developer leaves |
| `DATABASE_URL` | 180 days | Scheduled, or if Neon credentials are compromised |
| `SUPERVISOR_PIN` | 90 days | Scheduled, or if shared/recorded anywhere |
| Google OAuth | 180 days | Scheduled, or if Google Cloud project is compromised |
| Cloudflare API token | 90 days | Scheduled, or if leaked |

### How to Rotate a Secret

1. **Generate a new value**:
   ```bash
   openssl rand -base64 32
   ```

2. **Set the new value in wrangler**:
   ```bash
   echo "<NEW_VALUE>" | npx wrangler secret put <SECRET_NAME>
   ```

3. **Verify the new value works**:
   ```bash
   curl https://<worker-url>/api/v1/health/live
   ```

4. **Update password manager** with the new value.

5. **For `DATABASE_URL`**: Create a new Neon branch or reset the password in Neon console, then update the wrangler secret.

6. **For `JWT_SECRET`**: Note that rotating this invalidates all existing JWTs. Users will need to log in again. Plan for this.

7. **For `SESSION_SECRET`**: Same as JWT — all sessions are invalidated.

### Zero-Downtime Rotation (Advanced)

For secrets that cause downtime when rotated (JWT_SECRET, SESSION_SECRET):

1. Deploy code that accepts **both** old and new secrets.
2. Set the new secret in wrangler.
3. Wait for all old tokens to expire (or force re-login).
4. Remove the old secret from code.
5. Deploy the cleaned-up code.

---

## Emergency: What to Do If a Secret Leaks {#emergency-leak}

### Immediate Actions (First 15 Minutes)

1. **Revoke/rotate the leaked secret immediately**:
   - Cloudflare API token → Delete in dashboard, create new one
   - `DATABASE_URL` → Reset password in Neon console
   - `JWT_SECRET` → Generate new one, set in wrangler
   - `SESSION_SECRET` → Generate new one, set in wrangler
   - Google OAuth → Reset client secret in Google Cloud Console

2. **Assess the blast radius**:
   - What could an attacker do with this secret?
   - Was it a read-only secret or a write-capable secret?
   - How long was it exposed?

3. **Check access logs**:
   - Cloudflare: Workers → Analytics → check for unusual traffic
   - Neon: Monitoring → check for unusual queries
   - Google Cloud: Audit logs → check for OAuth usage

### Short-Term Actions (First 24 Hours)

4. **Scrub git history** (if the leak was via git):
   ```bash
   # Install git-filter-repo
   pip install git-filter-repo

   # Remove the secret from all history
   git filter-repo --replace-text <(echo "SECRET_VALUE==>REDACTED")

   # Force push (coordinate with team first!)
   git push --force --all
   git push --force --tags
   ```

5. **Notify the team**:
   - What was leaked
   - What has been done
   - What actions team members need to take (e.g., re-clone, update local `.env`)

6. **Update all related secrets**:
   - If `DATABASE_URL` leaked, also check if `JWT_SECRET` was in the same commit
   - Rotate anything that was in the same file or commit

### Medium-Term Actions (First Week)

7. **Review and improve processes**:
   - How did the leak happen?
   - What guardrails can prevent it? (pre-commit hooks, secret scanning, etc.)
   - Update this runbook with lessons learned

8. **Set up secret scanning** (if not already):
   - GitHub: Enable push protection in Settings → Code security
   - Pre-commit: `pip install detect-secrets` and add to `.pre-commit-config.yaml`
   - CI: Add `gitleaks` or `trufflehog` to CI pipeline

9. **Document the incident**:
   - Timeline of events
   - Root cause
   - Remediation steps
   - Prevention measures

### Leak Response Checklist

- [ ] Secret revoked/rotated
- [ ] New secret set in wrangler
- [ ] Git history scrubbed (if applicable)
- [ ] Access logs reviewed
- [ ] Team notified
- [ ] Related secrets checked
- [ ] Secret scanning enabled
- [ ] Incident documented

---

## Best Practices {#best-practices}

### DO

- ✅ Use `openssl rand -base64 32` for cryptographic secrets
- ✅ Store secrets in a password manager (1Password, Bitwarden)
- ✅ Use separate secrets for staging and production
- ✅ Rotate secrets on a schedule (see table above)
- ✅ Use `echo "value" | npx wrangler secret put NAME` (not `wrangler secret put NAME` with value as argument — it may appear in shell history)
- ✅ Verify `.env` is in `.gitignore`
- ✅ Use `.env.example` with placeholder values for local dev
- ✅ Enable secret scanning in git/CI

### DON'T

- ❌ Never commit real secrets to git
- ❌ Never store secrets in `.env` files that could be committed
- ❌ Never share secrets in chat, Slack, or email
- ❌ Never log secret values (`console.log(SECRET)`)
- ❌ Never use the same secret for staging and production
- ❌ Never use default/weak secrets (`123456`, `password`, `secret`)
- ❌ Never include secrets in error messages or crash reports
- ❌ Never store secrets in frontend code (Flutter, JS, etc.)

### Pre-Commit Hook Setup

Add to `.pre-commit-config.yaml`:

```yaml
repos:
  - repo: https://github.com/Yelp/detect-secrets
    rev: v1.4.0
    hooks:
      - id: detect-secrets
        args: ['--baseline', '.secrets.baseline']
```

```bash
# Install pre-commit
pip install pre-commit

# Install hooks
pre-commit install

# Generate baseline
detect-secrets scan > .secrets.baseline
```

---

## Quick Reference

### Wrangler Secret Commands

```bash
# Set a secret
echo "value" | npx wrangler secret put SECRET_NAME

# Set a secret for staging
echo "value" | npx wrangler secret put SECRET_NAME --env staging

# List all secrets (names only, never values)
npx wrangler secret list

# Delete a secret
npx wrangler secret delete SECRET_NAME
```

### Generating Secrets

```bash
# JWT / Session secret (32 bytes, base64-encoded)
openssl rand -base64 32

# Database password (16 chars)
openssl rand -hex 16

# Supervisor PIN (6 digits)
echo $((RANDOM % 900000 + 100000))
```

### Verifying No Secrets in Git

```bash
# Check for common secret patterns
git log --all -p | grep -iE '(api[_-]?key|secret|password|token|BEGIN.*PRIVATE|cfut_)'

# Check for high-entropy strings
git log --all -p | grep -E '[A-Za-z0-9+/]{40,}={0,2}'
```

Expected: **0 results** (excluding false positives from lock files, etc.)
