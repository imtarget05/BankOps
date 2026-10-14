/**
 * BankOps Cloudflare Worker – API Gateway
 *
 * Stack: Hono.js + Neon Serverless PostgreSQL + jose JWT
 * Zero cold start: V8 isolate, không container, không Python startup time.
 *
 * Tất cả routes mirror FastAPI backend hiện tại tại /api/v1/*
 */

import { Hono } from "hono";
import { cors } from "hono/cors";
import { logger } from "hono/logger";
import { secureHeaders } from "hono/secure-headers";

import { authMiddleware, verifyToken } from "./middleware/auth";
import { healthRoutes } from "./routes/health";
import { authRoutes } from "./routes/auth";
import { inventoryRoutes } from "./routes/inventory";
import { cashSimRoutes } from "./routes/cash-sim";
import { approvalsRoutes } from "./routes/approvals";
import { activityRoutes } from "./routes/activity";
import { reportsRoutes } from "./routes/reports";
import { integrationsRoutes } from "./routes/integrations";
import { reconciliationsRoutes } from "./routes/reconciliations";
import { aiRoutes } from "./routes/ai";
import { db } from "./db/client";
import openapiData from "./openapi.json";

const SWAGGER_HTML = `<!DOCTYPE html>
<html>
<head>
  <title>BankOps API - Swagger UI</title>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="stylesheet" type="text/css" href="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui.css">
  <link rel="shortcut icon" href="https://fastapi.tiangolo.com/img/favicon.png">
  <style>
    body { margin: 0; background: #fafafa; }
    .topbar { display: none; }
  </style>
</head>
<body>
  <div id="swagger-ui"></div>
  <script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
  <script>
    window.onload = () => {
      window.ui = SwaggerUIBundle({
        url: '/api/v1/openapi.json',
        dom_id: '#swagger-ui',
        deepLinking: true,
        presets: [
          SwaggerUIBundle.presets.apis,
          SwaggerUIBundle.SwaggerUIStandalonePreset
        ],
        layout: "BaseLayout"
      });
    };
  </script>
</body>
</html>`;

export interface Env {
  // Secrets (qua wrangler secret put)
  DATABASE_URL: string;
  JWT_SECRET: string;
  SESSION_SECRET: string;
  GOOGLE_CLIENT_ID: string;

  // AI model service binding
  AI: Ai;
  AI_MODEL?: string;
  // Backend LLM tự host (Hugging Face Space llama.cpp, OpenAI-compatible).
  // Khi HF_LLM_BASE_URL được set, AI requests ưu tiên backend này; Workers AI là fallback.
  HF_LLM_BASE_URL?: string;
  HF_LLM_API_KEY?: string;
  HF_LLM_MODEL?: string;
  HF_LLM_TIMEOUT_MS?: string;
  HF_LLM_MAX_TOKENS?: string;
  AI_CHAT_LIMIT: RateLimit;
  AI_ASSESSMENT_LIMIT: RateLimit;
  // Optional server-side PIN for high-risk approvals; production must set it.
  SUPERVISOR_PIN?: string;
  APP_ENV: string;

  // Vars
  APP_NAME: string;
  ACCESS_TOKEN_EXPIRE_MINUTES: string;
  REFRESH_TOKEN_EXPIRE_DAYS: string;
}

type AppEnv = { Bindings: Env; Variables: { rid: string } };

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

// ─── Routes ─────────────────────────────────────────────────────────────────

const api = new Hono<AppEnv>();

// Public
api.route("/health", healthRoutes);
api.route("/auth", authRoutes);

// GET /me (top-level alias for /auth/me used by AuthService)
api.get("/me", async (c) => {
  const authHeader = c.req.header("Authorization") ?? c.req.header("authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return c.json({ error: { code: "UNAUTHENTICATED", message: "Not authenticated" } }, 401);
  }
  let payload;
  try {
    payload = await verifyToken(authHeader.slice(7), c.env.JWT_SECRET);
  } catch {
    return c.json({ error: { code: "UNAUTHENTICATED", message: "Invalid token" } }, 401);
  }
  const users = await db<{
    id: string;
    username: string;
    display_name_demo: string;
    email: string | null;
    phone_number: string | null;
    branch: string | null;
  }>(c.env.DATABASE_URL)`
    SELECT id, username, display_name_demo, email, phone_number, branch FROM iam_users
    WHERE id = ${payload.sub}::uuid LIMIT 1
  `;
  const u = users[0];
  return c.json({
    id: payload.sub,
    username: payload.username,
    display_name: u?.display_name_demo ?? payload.username,
    email: u?.email ?? undefined,
    phone_number: u?.phone_number ?? undefined,
    branch: u?.branch ?? undefined,
    roles: payload.roles,
    capabilities: payload.caps,
  });
});

// PUT /me (top-level alias for /auth/me used by AuthService)
api.put("/me", async (c) => {
  const authHeader = c.req.header("Authorization") ?? c.req.header("authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return c.json({ error: { code: "UNAUTHENTICATED", message: "Not authenticated" } }, 401);
  }
  let payload;
  try {
    payload = await verifyToken(authHeader.slice(7), c.env.JWT_SECRET);
  } catch {
    return c.json({ error: { code: "UNAUTHENTICATED", message: "Invalid token" } }, 401);
  }

  const body = (await c.req.json().catch(() => ({}))) as {
    display_name?: string;
    email?: string;
    phone_number?: string;
    branch?: string;
  };

  const displayName = body.display_name?.trim();
  if (!displayName) {
    return c.json({ detail: "Họ và tên không được để trống." }, 422);
  }

  const email = body.email !== undefined ? body.email.trim() : null;
  const phoneNumber = body.phone_number !== undefined ? body.phone_number.trim() : null;
  const branch = body.branch !== undefined ? body.branch.trim() : null;

  const updatedUsers = await db<{
    id: string;
    username: string;
    display_name_demo: string;
    email: string | null;
    phone_number: string | null;
    branch: string | null;
  }>(c.env.DATABASE_URL)`
    UPDATE iam_users
    SET display_name_demo = ${displayName},
        email = COALESCE(${email}, email),
        phone_number = COALESCE(${phoneNumber}, phone_number),
        branch = COALESCE(${branch}, branch),
        updated_at = NOW()
    WHERE id = ${payload.sub}::uuid
    RETURNING id, username, display_name_demo, email, phone_number, branch
  `;
  if (!updatedUsers.length) {
    return c.json({ error: { code: "NOT_FOUND", message: "User not found" } }, 404);
  }

  const u = updatedUsers[0];
  return c.json({
    id: payload.sub,
    username: payload.username,
    display_name: u.display_name_demo,
    email: u.email ?? undefined,
    phone_number: u.phone_number ?? undefined,
    branch: u.branch ?? undefined,
    roles: payload.roles,
    capabilities: payload.caps,
    message: "Cập nhật hồ sơ thành công.",
  });
});

// Protected (JWT required)
api.use("/ai/*", authMiddleware);
api.route("/ai", aiRoutes);

api.use("/inventory/*", authMiddleware);
api.route("/inventory", inventoryRoutes);

api.use("/cash-sim/*", authMiddleware);
api.route("/cash-sim", cashSimRoutes);

api.use("/approvals/*", authMiddleware);
api.route("/approvals", approvalsRoutes);

api.use("/activity/*", authMiddleware);
api.route("/activity", activityRoutes);

api.use("/reports/*", authMiddleware);
api.route("/reports", reportsRoutes);

api.use("/integrations/*", authMiddleware);
api.route("/integrations", integrationsRoutes);

api.use("/reconciliations", authMiddleware);
api.use("/reconciliations/*", authMiddleware);
api.route("/reconciliations", reconciliationsRoutes);

// Mount tại /api/v1 (mirror FastAPI)
app.route("/api/v1", api);

// ─── Swagger UI & OpenAPI documentation ─────────────────────────────────────
app.get("/docs", (c) => c.html(SWAGGER_HTML));
app.get("/api/v1/docs", (c) => c.html(SWAGGER_HTML));
app.get("/openapi.json", (c) => c.json(openapiData));
app.get("/api/v1/openapi.json", (c) => c.json(openapiData));

// ─── Cron Handler (keep-warm ping) ──────────────────────────────────────────
// Workers đã zero cold start, nhưng cron này log metrics
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
