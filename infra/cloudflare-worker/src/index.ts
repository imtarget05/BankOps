/**
 * BankOps Cloudflare Worker – Retired boundary (health only)
 *
 * ADR 0001 (docs/adr/0001-canonical-api-fastapi-worker-proxy-deprecation.md):
 * FastAPI (backend/) is the ONLY business API. This Worker is a thin,
 * non-business boundary: it serves /api/v1/health/* and answers every
 * previously-mounted business path with 410 Gone.
 */

import { Hono, type Context } from "hono";
import { cors } from "hono/cors";
import { logger } from "hono/logger";
import { secureHeaders } from "hono/secure-headers";

import { healthRoutes } from "./routes/health";

export interface Env {
  // Secret (wrangler secret put DATABASE_URL) – only /health/ready uses it.
  DATABASE_URL: string;
  APP_ENV: string;
}

type AppEnv = { Bindings: Env; Variables: { rid: string } };

const GONE_MESSAGE =
  "Cloudflare Worker is retired. Use the canonical FastAPI API.";

const app = new Hono<AppEnv>();

// Allowlist mirror docker-compose ALLOWED_ORIGINS — never echo arbitrary origin with credentials.
const ALLOWED_ORIGINS = [
  "http://localhost:3000",
  "http://localhost:5000",
  "http://localhost:8080",
  "http://127.0.0.1:8080",
  "https://bankops-web.pages.dev",
];

// ─── Global Middleware ───────────────────────────────────────────────────────

app.use("*", logger());
app.use("*", secureHeaders());
app.use(
  "*",
  cors({
    origin: (o) => {
      if (ALLOWED_ORIGINS.includes(o)) return o;
      if (/^https:\/\/[a-z0-9-]+\.pages\.dev$/.test(o)) return o;
      return ALLOWED_ORIGINS[0];
    },
    allowMethods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allowHeaders: [
      "Content-Type",
      "Authorization",
      "X-Request-ID",
      "Idempotency-Key",
      "If-Match",
      "Last-Event-ID",
    ],
    exposeHeaders: ["X-Request-ID", "X-Correlation-ID"],
    credentials: true,
    maxAge: 600,
  })
);

// ─── Correlation ID ──────────────────────────────────────────────────────────
app.use("*", async (c, next) => {
  const reqId =
    c.req.header("X-Request-ID") ||
    c.req.header("CF-Ray") ||
    crypto.randomUUID();
  c.set("rid", reqId);
  await next();
  c.header("X-Request-ID", reqId);
  c.header("X-Correlation-ID", reqId);
});

// ─── 410 Gone (retired business surface) ─────────────────────────────────────
// Same error envelope as the 404/500 handlers below.
function gone(c: Context<AppEnv>) {
  const rid = c.get("rid") || crypto.randomUUID();
  return c.json(
    { error: { code: "GONE", message: GONE_MESSAGE, request_id: rid } },
    410,
    { "X-Request-ID": rid }
  );
}

// ─── Routes ─────────────────────────────────────────────────────────────────

// The ONLY capability this retired boundary still serves.
app.route("/api/v1/health", healthRoutes);

// Every business API path ever mounted here (auth, inventory, cash-sim,
// approvals, activity, reports, integrations, reconciliations, ai,
// ai-knowledge, me, openapi, docs, …) → 410 Gone.
app.all("/api/*", (c, next) => {
  if (c.req.path.startsWith("/api/v1/health")) return next();
  return gone(c);
});

// Retired business documentation endpoints (root-level).
app.all("/docs", gone);
app.all("/openapi.json", gone);

// Root: small status pointer — no business data.
app.get("/", (c) =>
  c.json({
    service: "BankOps Cloudflare Worker",
    status: "retired",
    message: GONE_MESSAGE,
    health: "/api/v1/health/live",
  })
);

// ─── Cron Handler (keep-warm ping) ──────────────────────────────────────────
app.get("/_cron/health", (c) =>
  c.json({ status: "ok", ts: new Date().toISOString() })
);

// ─── 404 fallback ────────────────────────────────────────────────────────────
app.notFound((c) => {
  const rid =
    c.req.header("X-Request-ID") ||
    c.req.header("CF-Ray") ||
    crypto.randomUUID();
  return c.json(
    {
      error: {
        code: "NOT_FOUND",
        message: "Route không tồn tại",
        request_id: rid,
      },
    },
    404,
    { "X-Request-ID": rid }
  );
});

// ─── Error handler ───────────────────────────────────────────────────────────
app.onError((err, c) => {
  console.error(`[ERROR] ${c.req.method} ${c.req.path}:`, err);
  let rid = "";
  try {
    rid = c.get("rid") || c.req.header("X-Request-ID") || crypto.randomUUID();
  } catch {
    rid = c.req.header("X-Request-ID") || crypto.randomUUID();
  }
  const message =
    c.env.APP_ENV === "production" ? "Internal server error" : err.message;
  return c.json(
    {
      error: { code: "INTERNAL_ERROR", message, request_id: rid },
    },
    500,
    { "X-Request-ID": rid }
  );
});

export default {
  fetch: app.fetch,

  // Cron scheduled handler
  async scheduled(_event: ScheduledEvent, env: Env, _ctx: ExecutionContext) {
    console.log(
      `[CRON] Health ping – ${new Date().toISOString()} env=${env.APP_ENV}`
    );
  },
};
