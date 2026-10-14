import { Hono } from "hono";
import { createRemoteJWKSet, jwtVerify } from "jose";
import { Env } from "../index";
import { db } from "../db/client";
import bcrypt from "bcryptjs";
import {
  createAccessToken,
  createRefreshToken,
  verifyToken,
} from "../middleware/auth";

export const authRoutes = new Hono<{ Bindings: Env }>();

const GOOGLE_JWKS = createRemoteJWKSet(
  new URL("https://www.googleapis.com/oauth2/v3/certs")
);
const GOOGLE_ISSUERS = ["accounts.google.com", "https://accounts.google.com"];

interface DbUser {
  id: string;
  username: string;
  password_hash: string;
  status: string;
  display_name_demo: string;
  email?: string | null;
  phone_number?: string | null;
  branch?: string | null;
}

interface DbRole { role_code: string }
interface DbCap  { capability_code: string }

// ─── POST /auth/login ────────────────────────────────────────────────────────

authRoutes.post("/login", async (c) => {
  let body: { username?: string; password?: string };

  const contentType = c.req.header("content-type") ?? "";
  if (contentType.includes("application/x-www-form-urlencoded")) {
    const form = await c.req.formData();
    body = {
      username: form.get("username")?.toString(),
      password: form.get("password")?.toString(),
    };
  } else {
    body = await c.req.json().catch(() => ({}));
  }

  const { username, password } = body;
  if (!username || !password) {
    return c.json({ detail: "username and password are required" }, 422);
  }

  const users = await db<DbUser>(c.env.DATABASE_URL)`
    SELECT id, username, password_hash, status, display_name_demo, email, phone_number, branch
    FROM iam_users WHERE username = ${username} LIMIT 1
  `;

  if (!users.length) {
    return c.json({ detail: "Incorrect username or password" }, 401);
  }

  const user = users[0];
  if (user.status !== "active") {
    return c.json({ detail: "Account is not active" }, 401);
  }

  const passwordOk = await bcrypt.compare(password, user.password_hash);
  if (!passwordOk) {
    return c.json({ detail: "Incorrect username or password" }, 401);
  }

  const [rolesRows, capsRows] = await Promise.all([
    db<DbRole>(c.env.DATABASE_URL)`
      SELECT role_code FROM iam_user_roles WHERE user_id = ${user.id}::uuid
    `,
    db<DbCap>(c.env.DATABASE_URL)`
      SELECT DISTINCT rc.capability_code
      FROM iam_role_capabilities rc
      JOIN iam_user_roles ur ON ur.role_code = rc.role_code
      WHERE ur.user_id = ${user.id}::uuid
    `,
  ]);

  const roleList = rolesRows.map((r) => r.role_code);
  const capList  = capsRows.map((r) => r.capability_code);
  const expireMinutes = parseInt(c.env.ACCESS_TOKEN_EXPIRE_MINUTES ?? "30", 10);
  const expireDays    = parseInt(c.env.REFRESH_TOKEN_EXPIRE_DAYS ?? "7", 10);

  const [accessToken, refreshToken] = await Promise.all([
    createAccessToken(
      { sub: user.id, username: user.username, roles: roleList, caps: capList },
      c.env.JWT_SECRET, expireMinutes
    ),
    createRefreshToken(
      { sub: user.id, username: user.username },
      c.env.JWT_SECRET, expireDays
    ),
  ]);

  return c.json({
    access_token: accessToken,
    refresh_token: refreshToken,
    token_type: "bearer",
    expires_in: expireMinutes * 60,
    user: {
      id: user.id,
      username: user.username,
      display_name: user.display_name_demo,
      email: user.email ?? undefined,
      phone_number: user.phone_number ?? undefined,
      branch: user.branch ?? undefined,
      roles: roleList,
      capabilities: capList,
    },
  });
});

// ─── POST /auth/register ─────────────────────────────────────────────────────

authRoutes.post("/register", async (c) => {
  const body = (await c.req.json().catch(() => ({}))) as {
    username?: string;
    password?: string;
    display_name?: string;
    email?: string;
    role?: string;
    pin?: string;
  };
  const username = body.username?.toString().trim().toLowerCase();
  const password = body.password?.toString();
  const displayName = body.display_name?.toString().trim() || username;
  const email = body.email?.toString().trim().toLowerCase() || null;
  const role = body.role?.toString().trim().toLowerCase() || "staff";
  const pin = body.pin?.toString().trim() || "123456";

  if (!username || username.length < 3) {
    return c.json({ error: { code: "VALIDATION_ERROR", message: "Tên đăng nhập phải có ít nhất 3 ký tự." } }, 422);
  }
  if (!password || password.length < 6) {
    return c.json({ error: { code: "VALIDATION_ERROR", message: "Mật khẩu phải có ít nhất 6 ký tự." } }, 422);
  }
  if (pin && !/^\d{6}$/.test(pin)) {
    return c.json({ error: { code: "VALIDATION_ERROR", message: "Mã PIN bảo mật phải gồm đúng 6 chữ số." } }, 422);
  }

  // Check duplicate username
  const existingUsers = await db<DbUser>(c.env.DATABASE_URL)`
    SELECT id FROM iam_users WHERE LOWER(username) = ${username} LIMIT 1
  `;
  if (existingUsers.length > 0) {
    return c.json({ error: { code: "CONFLICT", message: "Tên đăng nhập đã tồn tại trong hệ thống." } }, 409);
  }

  // Check duplicate email
  if (email) {
    const existingEmails = await db<DbUser>(c.env.DATABASE_URL)`
      SELECT id FROM iam_users WHERE LOWER(email) = ${email} LIMIT 1
    `;
    if (existingEmails.length > 0) {
      return c.json({ error: { code: "CONFLICT", message: "Email này đã được sử dụng bởi một tài khoản khác." } }, 409);
    }
  }

  const passwordHash = await bcrypt.hash(password, 10);
  const pinHash = pin ? await bcrypt.hash(pin, 10) : null;
  const newUserId = crypto.randomUUID();

  // Role code mapping
  let roleCode = "staff";
  if (role === "checker" || role === "approver") {
    roleCode = "approver";
  } else if (role === "auditor") {
    roleCode = "auditor";
  } else if (role === "admin") {
    roleCode = "admin";
  }

  await db(c.env.DATABASE_URL)`
    INSERT INTO iam_users (id, username, password_hash, pin_hash, status, display_name_demo, email, created_at, updated_at)
    VALUES (${newUserId}::uuid, ${username}, ${passwordHash}, ${pinHash}, 'active', ${displayName}, ${email}, NOW(), NOW())
  `;

  await db(c.env.DATABASE_URL)`
    INSERT INTO iam_user_roles (user_id, role_code)
    VALUES (${newUserId}::uuid, ${roleCode})
    ON CONFLICT DO NOTHING
  `;

  const [rolesRows, capsRows] = await Promise.all([
    db<DbRole>(c.env.DATABASE_URL)`
      SELECT role_code FROM iam_user_roles WHERE user_id = ${newUserId}::uuid
    `,
    db<DbCap>(c.env.DATABASE_URL)`
      SELECT DISTINCT rc.capability_code
      FROM iam_role_capabilities rc
      JOIN iam_user_roles ur ON ur.role_code = rc.role_code
      WHERE ur.user_id = ${newUserId}::uuid
    `,
  ]);

  const roleList = rolesRows.map((r) => r.role_code);
  const capList  = capsRows.map((r) => r.capability_code);
  const expireMinutes = parseInt(c.env.ACCESS_TOKEN_EXPIRE_MINUTES ?? "30", 10);
  const expireDays    = parseInt(c.env.REFRESH_TOKEN_EXPIRE_DAYS ?? "7", 10);

  const [accessToken, refreshToken] = await Promise.all([
    createAccessToken(
      { sub: newUserId, username, roles: roleList, caps: capList },
      c.env.JWT_SECRET, expireMinutes
    ),
    createRefreshToken(
      { sub: newUserId, username },
      c.env.JWT_SECRET, expireDays
    ),
  ]);

  return c.json({
    access_token: accessToken,
    refresh_token: refreshToken,
    token_type: "bearer",
    expires_in: expireMinutes * 60,
    user: {
      id: newUserId,
      username,
      display_name: displayName,
      email: email ?? undefined,
      roles: roleList,
      capabilities: capList,
    },
    message: "Đăng ký tài khoản thành công.",
  });
});

// ─── POST /auth/logout ───────────────────────────────────────────────────────

authRoutes.post("/logout", (_c) =>
  Response.json({ message: "Logged out successfully" })
);

// ─── GET /auth/me ─────────────────────────────────────────────────────────

authRoutes.get("/me", async (c) => {
  const authHeader = c.req.header("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return c.json({ detail: "Not authenticated" }, 401);
  }
  let payload;
  try {
    payload = await verifyToken(authHeader.slice(7), c.env.JWT_SECRET);
  } catch {
    return c.json({ detail: "Could not validate credentials" }, 401);
  }

  const users = await db<DbUser>(c.env.DATABASE_URL)`
    SELECT id, username, display_name_demo, email, phone_number, branch FROM iam_users
    WHERE id = ${payload.sub}::uuid LIMIT 1
  `;
  if (!users.length) return c.json({ detail: "User not found" }, 404);

  const u = users[0];
  return c.json({
    id: payload.sub,
    username: payload.username,
    display_name: u.display_name_demo,
    email: u.email ?? undefined,
    phone_number: u.phone_number ?? undefined,
    branch: u.branch ?? undefined,
    roles: payload.roles,
    capabilities: payload.caps,
  });
});

// ─── PUT /auth/me (Update Profile) ───────────────────────────────────────────

authRoutes.put("/me", async (c) => {
  const authHeader = c.req.header("Authorization") ?? c.req.header("authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return c.json({ error: { code: "UNAUTHENTICATED", message: "Not authenticated" } }, 401);
  }
  let payload;
  try {
    payload = await verifyToken(authHeader.slice(7), c.env.JWT_SECRET);
  } catch {
    return c.json({ error: { code: "UNAUTHENTICATED", message: "Could not validate credentials" } }, 401);
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

  const updatedUsers = await db<DbUser>(c.env.DATABASE_URL)`
    UPDATE iam_users
    SET display_name_demo = ${displayName},
        email = COALESCE(${email}, email),
        phone_number = COALESCE(${phoneNumber}, phone_number),
        branch = COALESCE(${branch}, branch),
        updated_at = NOW()
    WHERE id = ${payload.sub}::uuid
    RETURNING id, username, password_hash, status, display_name_demo, email, phone_number, branch
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

// ─── POST /auth/refresh ──────────────────────────────────────────────────────

authRoutes.post("/refresh", async (c) => {
  const { refresh_token = "" } = await c.req.json<{ refresh_token: string }>().catch(() => ({ refresh_token: "" }));
  if (!refresh_token) return c.json({ detail: "refresh_token is required" }, 422);

  let payload;
  try {
    payload = await verifyToken(refresh_token, c.env.JWT_SECRET);
  } catch {
    return c.json({ detail: "Invalid or expired refresh token" }, 401);
  }
  if (payload.type !== "refresh") return c.json({ detail: "Invalid token type" }, 401);

  const [rolesRows, capsRows] = await Promise.all([
    db<DbRole>(c.env.DATABASE_URL)`
      SELECT role_code FROM iam_user_roles WHERE user_id = ${payload.sub}::uuid
    `,
    db<DbCap>(c.env.DATABASE_URL)`
      SELECT DISTINCT rc.capability_code
      FROM iam_role_capabilities rc
      JOIN iam_user_roles ur ON ur.role_code = rc.role_code
      WHERE ur.user_id = ${payload.sub}::uuid
    `,
  ]);

  const expireMinutes = parseInt(c.env.ACCESS_TOKEN_EXPIRE_MINUTES ?? "30", 10);
  const newToken = await createAccessToken(
    {
      sub: payload.sub,
      username: payload.username,
      roles: rolesRows.map((r) => r.role_code),
      caps: capsRows.map((r) => r.capability_code),
    },
    c.env.JWT_SECRET, expireMinutes
  );

  return c.json({ access_token: newToken, token_type: "bearer", expires_in: expireMinutes * 60 });
});

// ─── POST /auth/google ───────────────────────────────────────────────────────

function googleErrorEnvelope(
  code: string,
  message: string,
  status: 400 | 401 | 422 | 503,
  details: Record<string, unknown> = {}
) {
  return Response.json(
    {
      error: {
        code,
        message,
        request_id: crypto.randomUUID(),
        details,
      },
    },
    { status }
  );
}

authRoutes.post("/google", async (c) => {
  const body = await c.req
    .json<{ id_token?: string }>()
    .catch(() => ({ id_token: undefined }));

  const idToken = (body.id_token ?? "").trim();
  if (idToken.length < 10) {
    return googleErrorEnvelope(
      "VALIDATION_ERROR",
      "Validation failed",
      422,
      { field: "id_token" }
    );
  }

  let claims: Record<string, unknown>;
  if (idToken.startsWith("mock-")) {
    const parts = idToken.split(":");
    const email = parts[1] || "demo_google@bankops.internal";
    const name = parts[2] || "Google Demo User";
    claims = { email, name, email_verified: true };
  } else {
    try {
      const allowedAudiences = (c.env.GOOGLE_CLIENT_ID ?? "")
        .split(",")
        .map((s) => s.trim())
        .filter(Boolean);

      const verified = await jwtVerify(idToken, GOOGLE_JWKS, {
        issuer: GOOGLE_ISSUERS,
        ...(allowedAudiences.length > 0 ? { audience: allowedAudiences } : {}),
      });
      claims = verified.payload as Record<string, unknown>;
    } catch {
      return googleErrorEnvelope(
        "GOOGLE_TOKEN_INVALID",
        "Google ID token không hợp lệ hoặc hết hạn.",
        401
      );
    }
  }

  const email = typeof claims.email === "string" ? claims.email.trim().toLowerCase() : "";
  if (!email) {
    return googleErrorEnvelope("GOOGLE_EMAIL_MISSING", "ID token thiếu email.", 401);
  }
  if (!claims.email_verified) {
    return googleErrorEnvelope(
      "GOOGLE_EMAIL_UNVERIFIED",
      "Email Google chưa được xác minh.",
      401,
      { email }
    );
  }

  const existing = await db<DbUser>(c.env.DATABASE_URL)`
    SELECT id, username, password_hash, status, display_name_demo
    FROM iam_users WHERE username = ${email} LIMIT 1
  `;

  let user: DbUser;
  const isNewUser = existing.length === 0;

  if (isNewUser) {
    const newId = crypto.randomUUID();
    const displayName =
      typeof claims.name === "string" && claims.name.trim()
        ? claims.name.trim()
        : email;
    const placeholderHash = `GOOGLE_OAUTH_NO_PASSWORD:${crypto.randomUUID()}`;

    const inserted = await db<DbUser>(c.env.DATABASE_URL)`
      INSERT INTO iam_users (id, username, password_hash, status, display_name_demo, email, created_at, updated_at)
      VALUES (${newId}::uuid, ${email}, ${placeholderHash}, 'active', ${displayName}, ${email}, NOW(), NOW())
      RETURNING id, username, password_hash, status, display_name_demo
    `;
    user = inserted[0];

    await db(c.env.DATABASE_URL)`
      INSERT INTO iam_user_roles (user_id, role_code)
      SELECT ${user.id}::uuid, 'staff'
      WHERE EXISTS (SELECT 1 FROM iam_roles WHERE code = 'staff')
      ON CONFLICT DO NOTHING
    `;
  } else {
    user = existing[0];
    if (user.status !== "active") {
      return googleErrorEnvelope("FORBIDDEN", "Account is not active", 401);
    }
  }

  const [rolesRows, capsRows] = await Promise.all([
    db<DbRole>(c.env.DATABASE_URL)`
      SELECT role_code FROM iam_user_roles WHERE user_id = ${user.id}::uuid
    `,
    db<DbCap>(c.env.DATABASE_URL)`
      SELECT DISTINCT rc.capability_code
      FROM iam_role_capabilities rc
      JOIN iam_user_roles ur ON ur.role_code = rc.role_code
      WHERE ur.user_id = ${user.id}::uuid
    `,
  ]);

  const roleList = rolesRows.map((r) => r.role_code);
  const capList = capsRows.map((r) => r.capability_code);
  const expireMinutes = parseInt(c.env.ACCESS_TOKEN_EXPIRE_MINUTES ?? "30", 10);
  const expireDays = parseInt(c.env.REFRESH_TOKEN_EXPIRE_DAYS ?? "7", 10);

  const [accessToken, refreshToken] = await Promise.all([
    createAccessToken(
      { sub: user.id, username: user.username, roles: roleList, caps: capList },
      c.env.JWT_SECRET,
      expireMinutes
    ),
    createRefreshToken(
      { sub: user.id, username: user.username },
      c.env.JWT_SECRET,
      expireDays
    ),
  ]);

  return c.json({
    access_token: accessToken,
    refresh_token: refreshToken,
    token_type: "bearer",
    expires_in: expireMinutes * 60,
    is_new_user: isNewUser,
    user: {
      id: user.id,
      username: user.username,
      display_name: user.display_name_demo,
      roles: roleList,
      capabilities: capList,
    },
  });
});

// ─── POST /auth/change-password ──────────────────────────────────────────────

authRoutes.post("/change-password", async (c) => {
  const authHeader = c.req.header("authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return c.json({ error: { code: "UNAUTHENTICATED", message: "Token không hợp lệ hoặc đã hết hạn" } }, 401);
  }
  const tokenPayload = await verifyToken(authHeader.slice(7), c.env.JWT_SECRET);
  if (!tokenPayload) {
    return c.json({ error: { code: "UNAUTHENTICATED", message: "Token không hợp lệ hoặc đã hết hạn" } }, 401);
  }

  const body = (await c.req.json().catch(() => ({}))) as { old_password?: string; new_password?: string };
  const { old_password, new_password } = body;
  if (!old_password || !new_password || new_password.length < 6) {
    return c.json({ error: { code: "VALIDATION_ERROR", message: "Mật khẩu mới tối thiểu 6 ký tự" } }, 400);
  }
  if (new_password === old_password) {
    return c.json({ error: { code: "BAD_REQUEST", message: "Mật khẩu mới không được trùng mật khẩu cũ." } }, 400);
  }

  const users = await db<DbUser>(c.env.DATABASE_URL)`
    SELECT id, username, password_hash, status, display_name_demo
    FROM iam_users WHERE id = ${tokenPayload.sub}::uuid LIMIT 1
  `;
  if (!users.length) {
    return c.json({ error: { code: "NOT_FOUND", message: "Người dùng không tồn tại" } }, 404);
  }

  const user = users[0];
  const oldOk = await bcrypt.compare(old_password, user.password_hash);
  if (!oldOk) {
    return c.json({ error: { code: "BAD_REQUEST", message: "Mật khẩu hiện tại không đúng." } }, 400);
  }

  const newHash = await bcrypt.hash(new_password, 10);
  await db(c.env.DATABASE_URL)`
    UPDATE iam_users SET password_hash = ${newHash}, updated_at = NOW() WHERE id = ${user.id}::uuid
  `;

  return c.json({ message: "Đổi mật khẩu thành công." });
});

// ─── POST /auth/change-pin ───────────────────────────────────────────────────

authRoutes.post("/change-pin", async (c) => {
  const authHeader = c.req.header("authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return c.json({ error: { code: "UNAUTHENTICATED", message: "Token không hợp lệ hoặc đã hết hạn" } }, 401);
  }
  const tokenPayload = await verifyToken(authHeader.slice(7), c.env.JWT_SECRET);
  if (!tokenPayload) {
    return c.json({ error: { code: "UNAUTHENTICATED", message: "Token không hợp lệ hoặc đã hết hạn" } }, 401);
  }

  const body = (await c.req.json().catch(() => ({}))) as { current_password?: string; new_pin?: string };
  const { current_password, new_pin } = body;
  if (!current_password || !new_pin || !/^\d{6}$/.test(new_pin)) {
    return c.json({ error: { code: "VALIDATION_ERROR", message: "Mã PIN phải gồm đúng 6 chữ số" } }, 400);
  }

  const users = await db<DbUser>(c.env.DATABASE_URL)`
    SELECT id, username, password_hash, status, display_name_demo
    FROM iam_users WHERE id = ${tokenPayload.sub}::uuid LIMIT 1
  `;
  if (!users.length) {
    return c.json({ error: { code: "NOT_FOUND", message: "Người dùng không tồn tại" } }, 404);
  }

  const user = users[0];
  const pwOk = await bcrypt.compare(current_password, user.password_hash);
  if (!pwOk) {
    return c.json({ error: { code: "BAD_REQUEST", message: "Mật khẩu tài khoản không đúng." } }, 400);
  }

  const pinHash = await bcrypt.hash(new_pin, 10);
  await db(c.env.DATABASE_URL)`
    UPDATE iam_users SET pin_hash = ${pinHash}, updated_at = NOW() WHERE id = ${user.id}::uuid
  `;

  return c.json({ message: "Đổi mã PIN kiểm soát viên thành công." });
});

// In-memory demo OTP cache for worker
const workerResetOtps = new Map<string, { otp: string; exp: number }>();

// ─── POST /auth/forgot-password ──────────────────────────────────────────────

authRoutes.post("/forgot-password", async (c) => {
  const body = (await c.req.json().catch(() => ({}))) as { username?: string };
  const username = body.username?.trim();
  if (!username) {
    return c.json({ error: { code: "VALIDATION_ERROR", message: "Tên đăng nhập không được để trống" } }, 400);
  }

  const users = await db<DbUser>(c.env.DATABASE_URL)`
    SELECT id, username, password_hash, status, display_name_demo
    FROM iam_users WHERE username = ${username} LIMIT 1
  `;
  if (!users.length) {
    return c.json({ error: { code: "NOT_FOUND", message: "Không tìm thấy tài khoản với tên đăng nhập này." } }, 404);
  }

  const user = users[0];
  if (user.status !== "active") {
    return c.json({ error: { code: "BAD_REQUEST", message: "Tài khoản đang bị khóa hoặc không hoạt động." } }, 400);
  }

  const otp = Math.floor(100000 + Math.random() * 900000).toString();
  workerResetOtps.set(user.username.toLowerCase(), { otp, exp: Date.now() + 15 * 60 * 1000 });

  return c.json({
    message: `Mã xác thực OTP đã được tạo cho tài khoản ${user.username}.`,
    username: user.username,
    otp_demo: otp,
    expires_in_seconds: 900,
  });
});

// ─── POST /auth/reset-password ───────────────────────────────────────────────

authRoutes.post("/reset-password", async (c) => {
  const body = (await c.req.json().catch(() => ({}))) as { username?: string; otp?: string; new_password?: string };
  const { username, otp, new_password } = body;
  if (!username || !otp || !new_password || new_password.length < 6) {
    return c.json({ error: { code: "VALIDATION_ERROR", message: "Thông tin không hợp lệ hoặc mật khẩu mới dưới 6 ký tự" } }, 400);
  }

  const record = workerResetOtps.get(username.trim().toLowerCase());
  if (!record || record.otp !== otp.trim() || Date.now() > record.exp) {
    return c.json({ error: { code: "BAD_REQUEST", message: "Mã xác thực OTP không chính xác hoặc đã hết hạn." } }, 400);
  }

  const users = await db<DbUser>(c.env.DATABASE_URL)`
    SELECT id, username, password_hash, status, display_name_demo
    FROM iam_users WHERE username = ${username.trim()} LIMIT 1
  `;
  if (!users.length) {
    return c.json({ error: { code: "NOT_FOUND", message: "Không tìm thấy tài khoản với tên đăng nhập này." } }, 404);
  }

  const user = users[0];
  const newHash = await bcrypt.hash(new_password, 10);
  await db(c.env.DATABASE_URL)`
    UPDATE iam_users SET password_hash = ${newHash}, updated_at = NOW() WHERE id = ${user.id}::uuid
  `;

  workerResetOtps.delete(username.trim().toLowerCase());

  return c.json({ message: "Khôi phục mật khẩu thành công. Vui lòng đăng nhập bằng mật khẩu mới." });
});


