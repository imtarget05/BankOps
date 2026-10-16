/**
 * Quản Lý Kho Trà Sữa Cloudflare Worker – Retired boundary (health only)
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
  // Secret (wrangler secret put DATABASE_URL) – only fallback /health/ready uses it.
  DATABASE_URL?: string;
  APP_ENV: string;
  // Upstream canonical API (FastAPI on Render or Modal)
  UPSTREAM_API_URL?: string;
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
  "https://quan-ly-kho-tra-sua.tanmainguyenbinh.workers.dev",
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

// ─── 410 Gone (retired business surface fallback) ───────────────────────────
// Same error envelope as the 404/500 handlers below.
function gone(c: Context<AppEnv>) {
  const rid = c.get("rid") || crypto.randomUUID();
  return c.json(
    { error: { code: "GONE", message: GONE_MESSAGE, request_id: rid } },
    410,
    { "X-Request-ID": rid }
  );
}

// ─── Reverse Proxy to Canonical FastAPI (when UPSTREAM_API_URL is set) ──────
async function proxyToUpstream(c: Context<AppEnv>) {
  const upstream = c.env.UPSTREAM_API_URL?.replace(/\/+$/, "");
  if (!upstream) {
    return gone(c);
  }

  const url = new URL(c.req.raw.url);
  const targetUrl = `${upstream}${url.pathname}${url.search}`;

  const headers = new Headers(c.req.raw.headers);
  headers.set("X-Forwarded-Host", url.host);
  headers.set("X-Forwarded-Proto", url.protocol.replace(":", ""));
  const rid = c.get("rid") || crypto.randomUUID();
  headers.set("X-Request-ID", rid);
  headers.set("X-Correlation-ID", rid);

  const isBodyAllowed = !["GET", "HEAD"].includes(c.req.method);

  try {
    const upstreamResponse = await fetch(targetUrl, {
      method: c.req.method,
      headers,
      body: isBodyAllowed ? c.req.raw.body : undefined,
      redirect: "follow",
    });

    const respHeaders = new Headers(upstreamResponse.headers);
    // Strip upstream CORS headers to avoid duplicate header errors with Hono cors() middleware
    respHeaders.delete("access-control-allow-origin");
    respHeaders.delete("access-control-allow-credentials");
    respHeaders.delete("access-control-allow-methods");
    respHeaders.delete("access-control-allow-headers");
    respHeaders.delete("access-control-expose-headers");
    respHeaders.delete("access-control-max-age");

    respHeaders.set("X-Request-ID", rid);
    respHeaders.set("X-Correlation-ID", rid);

    return new Response(upstreamResponse.body, {
      status: upstreamResponse.status,
      statusText: upstreamResponse.statusText,
      headers: respHeaders,
    });
  } catch (err: unknown) {
    const errMsg = err instanceof Error ? err.message : String(err);
    console.error(`[PROXY_ERROR] ${c.req.method} ${targetUrl}:`, errMsg);
    return c.json(
      {
        error: {
          code: "BAD_GATEWAY",
          message: "Không thể kết nối đến máy chủ backend (Upstream API).",
          details: { error: errMsg },
          request_id: rid,
        },
      },
      502,
      { "X-Request-ID": rid }
    );
  }
}

// ─── Routes ─────────────────────────────────────────────────────────────────

// The retired boundary local health check (only used when UPSTREAM_API_URL is unset)
app.route("/api/v1/health", healthRoutes);

// If UPSTREAM_API_URL is configured, proxy /api/*, /docs, /openapi.json to canonical FastAPI
app.all("/api/*", async (c, next) => {
  if (c.env.UPSTREAM_API_URL) {
    return proxyToUpstream(c);
  }
  if (c.req.path.startsWith("/api/v1/health")) return next();
  return gone(c);
});

// Documentation endpoints
app.all("/docs", async (c) => {
  if (c.env.UPSTREAM_API_URL) return proxyToUpstream(c);
  return gone(c);
});

app.all("/openapi.json", async (c) => {
  if (c.env.UPSTREAM_API_URL) return proxyToUpstream(c);
  return gone(c);
});

// Root: status pointer
app.get("/", (c) =>
  c.json({
    service: "Quản Lý Kho Trà Sữa Cloudflare Worker",
    status: c.env.UPSTREAM_API_URL ? "proxy" : "retired",
    upstream: c.env.UPSTREAM_API_URL ? "configured" : "none",
    message: c.env.UPSTREAM_API_URL
      ? "Forwarding to canonical FastAPI"
      : GONE_MESSAGE,
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
