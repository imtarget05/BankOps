# BankOps legacy Worker — no business secrets

This Worker is a compatibility boundary, not a BankOps API runtime. It must not
receive database, JWT, Google OAuth, AI, approval PIN, or integration secrets.
Every `/api/v1` business route returns `410 LEGACY_API_DISABLED`; FastAPI is the
only canonical business API.

See `docs/03-architecture.md` and `docs/14-cloudflare-deploy.md` for the
supported deployment path.
