/**
 * Inventory routes – mirror FastAPI /inventory/*
 */

import { Hono } from "hono";
import { Env } from "../index";
import { assessRequestRisk, requireSupervisorPin } from "./ai";
import { db } from "../db/client";
import { JwtPayload } from "../middleware/auth";

export const inventoryRoutes = new Hono<{ Bindings: Env }>();

function getUser(c: { get: (key: string) => unknown }): JwtPayload {
  return c.get("user") as JwtPayload;
}

interface InvItem {
  id: string;
  sku: string;
  name: string;
  unit: string;
  tracked_serial: boolean;
  active: boolean;
}

interface InvLocation {
  id: string;
  code: string;
  name: string;
  active: boolean;
}

interface InvBalance {
  item_id: string;
  location_id: string;
  quantity: string;
  version: number;
}

interface InvAsset {
  id: string;
  serial: string;
  item_id: string;
  location_id: string;
  assignee_demo: string | null;
  status: string;
}

interface InvMovement {
  id: string;
  request_id: string;
  line_id: string;
  item_id: string;
  location_id: string;
  quantity_signed: string;
  posted_at: string | null;
  created_at: string;
}

interface InvRequestRow {
  id: string;
  kind: string;
  status: string;
  maker_id: string;
  approver_id: string | null;
  source_id: string | null;
  dest_id: string | null;
  reason: string | null;
  version: number;
  created_at: string;
}

interface InvLineRow {
  id: string;
  request_id: string;
  item_id: string;
  quantity: string;
  serial: string | null;
}

// GET /inventory/items
inventoryRoutes.get("/items", async (c) => {
  const items = await db<InvItem>(c.env.DATABASE_URL)`
    SELECT id, sku, name, unit, tracked_serial, active
    FROM inv_items WHERE active = true
    ORDER BY name ASC
  `;
  return c.json({ items, simulation: true });
});

function canManageCatalog(user: JwtPayload): boolean {
  return user.caps.includes("inventory:manage_catalog") ||
    user.caps.includes("admin:user_management");
}

inventoryRoutes.post("/items", async (c) => {
  if (!canManageCatalog(getUser(c))) return c.json({ detail: "Bạn không có quyền quản lý danh mục kho." }, 403);
  const body = await c.req.json<{ sku?: string; name?: string; unit?: string; tracked_serial?: boolean }>().catch((): { sku?: string; name?: string; unit?: string; tracked_serial?: boolean } => ({}));
  const sku = body.sku?.trim().toUpperCase() ?? "";
  const name = body.name?.trim() ?? "";
  const unit = body.unit?.trim() || "đơn vị";
  if (!sku || !name) return c.json({ detail: "Cần nhập mã và tên mặt hàng." }, 422);
  const existing = await db<InvItem>(c.env.DATABASE_URL)`SELECT id FROM inv_items WHERE sku = ${sku} LIMIT 1`;
  if (existing.length) return c.json({ detail: "Mã mặt hàng đã tồn tại." }, 409);
  const id = crypto.randomUUID();
  const rows = await db<InvItem>(c.env.DATABASE_URL)`
    INSERT INTO inv_items (id, sku, name, unit, tracked_serial, active, created_at, updated_at)
    VALUES (${id}::uuid, ${sku}, ${name}, ${unit}, ${body.tracked_serial === true}, true, NOW(), NOW())
    RETURNING id, sku, name, unit, tracked_serial, active
  `;
  return c.json(rows[0], 201);
});

inventoryRoutes.put("/items/:id", async (c) => {
  if (!canManageCatalog(getUser(c))) return c.json({ detail: "Bạn không có quyền quản lý danh mục kho." }, 403);
  const id = c.req.param("id");
  if (!/^[0-9a-f-]{36}$/i.test(id)) return c.json({ detail: "Mã mặt hàng không hợp lệ." }, 422);
  const body = await c.req.json<{ name?: string; unit?: string; tracked_serial?: boolean }>().catch((): { name?: string; unit?: string; tracked_serial?: boolean } => ({}));
  const name = body.name?.trim();
  const unit = body.unit?.trim();
  if (body.name !== undefined && !name) return c.json({ detail: "Tên mặt hàng không được để trống." }, 422);
  if (body.unit !== undefined && !unit) return c.json({ detail: "Đơn vị tính không được để trống." }, 422);
  const rows = await db<InvItem>(c.env.DATABASE_URL)`
    UPDATE inv_items SET
      name = COALESCE(${name ?? null}, name),
      unit = COALESCE(${unit ?? null}, unit),
      tracked_serial = COALESCE(${body.tracked_serial ?? null}, tracked_serial),
      updated_at = NOW()
    WHERE id = ${id}::uuid AND active = true
    RETURNING id, sku, name, unit, tracked_serial, active
  `;
  if (!rows.length) return c.json({ detail: "Không tìm thấy mặt hàng." }, 404);
  return c.json(rows[0]);
});

inventoryRoutes.delete("/items/:id", async (c) => {
  if (!canManageCatalog(getUser(c))) return c.json({ detail: "Bạn không có quyền quản lý danh mục kho." }, 403);
  const id = c.req.param("id");
  if (!/^[0-9a-f-]{36}$/i.test(id)) return c.json({ detail: "Mã mặt hàng không hợp lệ." }, 422);
  const rows = await db<InvItem>(c.env.DATABASE_URL)`
    UPDATE inv_items SET active = false, updated_at = NOW() WHERE id = ${id}::uuid AND active = true RETURNING id
  `;
  if (!rows.length) return c.json({ detail: "Không tìm thấy mặt hàng." }, 404);
  return c.json({ status: "deleted", id });
});

// GET /inventory/locations
inventoryRoutes.get("/locations", async (c) => {
  const locations = await db<InvLocation>(c.env.DATABASE_URL)`
    SELECT id, code, name, active FROM inv_locations ORDER BY code ASC
  `;
  return c.json({ locations, simulation: true });
});

// GET /inventory/balances
inventoryRoutes.get("/balances", async (c) => {
  const locationId = c.req.query("location_id");
  const sql = db<InvBalance>(c.env.DATABASE_URL);
  const balances = locationId
    ? await sql`
        SELECT item_id, location_id, quantity, version
        FROM inv_balances
        WHERE location_id = ${locationId}::uuid
      `
    : await sql`
        SELECT item_id, location_id, quantity, version FROM inv_balances
      `;
  return c.json({ balances, simulation: true });
});

// GET /inventory/assets
inventoryRoutes.get("/assets", async (c) => {
  const assets = await db<InvAsset>(c.env.DATABASE_URL)`
    SELECT id, serial, item_id, location_id, assignee_demo, status
    FROM inv_assets
    ORDER BY serial ASC
  `;
  return c.json({ assets, simulation: true });
});

// GET /inventory/movements
inventoryRoutes.get("/movements", async (c) => {
  const movements = await db<InvMovement>(c.env.DATABASE_URL)`
    SELECT id, request_id, line_id, item_id, location_id, quantity_signed, posted_at, created_at
    FROM inv_movements
    ORDER BY created_at DESC
    LIMIT 200
  `;
  return c.json({ movements, simulation: true });
});

async function formatStockRequest(databaseUrl: string, r: InvRequestRow) {
  const lines = await db<InvLineRow>(databaseUrl)`
    SELECT id, request_id, item_id, quantity, serial
    FROM inv_request_lines
    WHERE request_id = ${r.id}::uuid
  `;
  return {
    id: r.id,
    kind: r.kind,
    status: r.status,
    maker_id: r.maker_id,
    approver_id: r.approver_id,
    source_id: r.source_id,
    dest_id: r.dest_id,
    reason: r.reason,
    version: r.version,
    created_at: r.created_at,
    lines: lines.map((l) => ({
      item_id: l.item_id,
      quantity: String(l.quantity),
      serial: l.serial,
    })),
    simulation: true,
  };
}

// GET /inventory/requests
inventoryRoutes.get("/requests", async (c) => {
  const user = getUser(c);
  const canApprove = user.caps.includes("inventory:approve_request");
  if (!canApprove && !user.caps.includes("inventory:create_request")) return c.json({ detail: "Bạn không có quyền xem phiếu kho." }, 403);
  const status = c.req.query("status");
  const sql = db<InvRequestRow>(c.env.DATABASE_URL);
  const rows = status
    ? await sql`
        SELECT id, kind, status, maker_id, approver_id,
               source_id, dest_id, reason, version, created_at
        FROM inv_requests
        WHERE status = ${status} AND (${canApprove} OR maker_id = ${user.sub}::uuid)
        ORDER BY created_at DESC
        LIMIT 100
      `
    : await sql`
        SELECT id, kind, status, maker_id, approver_id,
               source_id, dest_id, reason, version, created_at
        FROM inv_requests
        WHERE ${canApprove} OR maker_id = ${user.sub}::uuid
        ORDER BY created_at DESC
        LIMIT 100
      `;
  const requests = await Promise.all(rows.map((r) => formatStockRequest(c.env.DATABASE_URL, r)));
  return c.json({ requests, simulation: true });
});

// GET /inventory/requests/:id
inventoryRoutes.get("/requests/:id", async (c) => {
  const user = getUser(c);
  const id = c.req.param("id");
  const rows = await db<InvRequestRow>(c.env.DATABASE_URL)`
    SELECT id, kind, status, maker_id, approver_id,
           source_id, dest_id, reason, version, created_at
    FROM inv_requests
    WHERE id = ${id}::uuid
    LIMIT 1
  `;
  if (!rows.length) {
    return c.json({ error: { code: "NOT_FOUND", message: "Request not found" } }, 404);
  }
  if (rows[0].maker_id !== user.sub && !user.caps.includes("inventory:approve_request")) return c.json({ detail: "Bạn không có quyền xem phiếu này." }, 403);
  return c.json(await formatStockRequest(c.env.DATABASE_URL, rows[0]));
});

// POST /inventory/requests
inventoryRoutes.post("/requests", async (c) => {
  const user = getUser(c);
  if (!user.caps.includes("inventory:create_request")) return c.json({ detail: "Bạn không có quyền lập phiếu kho." }, 403);
  const body = await c.req.json<{
    kind: string;
    source_id?: string | null;
    dest_id?: string | null;
    reason?: string | null;
    lines: Array<{ item_id: string; quantity: string | number; serial?: string | null }>;
  }>();

  if (!body || !["receipt", "issue", "transfer", "adjustment"].includes(body.kind) || !Array.isArray(body.lines) || body.lines.length === 0 ||
      body.lines.some((line) => !line.item_id || !Number.isFinite(Number(line.quantity)) || Number(line.quantity) <= 0)) {
    return c.json(
      { error: { code: "VALIDATION_ERROR", message: "kind and lines are required" } },
      422
    );
  }

  const reqId = crypto.randomUUID();
  const sql = db(c.env.DATABASE_URL);
  await sql`
    INSERT INTO inv_requests
      (id, kind, status, maker_id, source_id, dest_id, reason, version, created_at, updated_at, created_by)
    VALUES
      (${reqId}::uuid, ${body.kind}, 'draft', ${user.sub}::uuid,
       ${body.source_id ?? null}, ${body.dest_id ?? null}, ${body.reason ?? null},
       1, NOW(), NOW(), ${user.sub}::uuid)
  `;

  for (const line of body.lines) {
    const lineId = crypto.randomUUID();
    await sql`
      INSERT INTO inv_request_lines
        (id, request_id, item_id, quantity, serial)
      VALUES
        (${lineId}::uuid, ${reqId}::uuid, ${line.item_id}::uuid, ${String(line.quantity)},
         ${line.serial ?? null})
    `;
  }

  const rows = await db<InvRequestRow>(c.env.DATABASE_URL)`
    SELECT id, kind, status, maker_id, approver_id,
           source_id, dest_id, reason, version, created_at
    FROM inv_requests WHERE id = ${reqId}::uuid LIMIT 1
  `;
  return c.json(await formatStockRequest(c.env.DATABASE_URL, rows[0]), 201);
});

// POST /inventory/requests/:id/submit
inventoryRoutes.post("/requests/:id/submit", async (c) => {
  const user = getUser(c);
  if (!user.caps.includes("inventory:create_request")) return c.json({ detail: "Bạn không có quyền gửi duyệt phiếu kho." }, 403);
  const id = c.req.param("id");
  const rows = await db<InvRequestRow>(c.env.DATABASE_URL)`
    SELECT id, kind, status, maker_id, approver_id,
           source_id, dest_id, reason, version, created_at
    FROM inv_requests WHERE id = ${id}::uuid LIMIT 1
  `;
  if (!rows.length) {
    return c.json({ error: { code: "NOT_FOUND", message: "Request not found" } }, 404);
  }
  const req = rows[0];
  if (req.maker_id !== user.sub) return c.json({ detail: "Chỉ người lập mới được gửi duyệt phiếu." }, 403);
  if (req.status !== "draft") {
    return c.json(
      { error: { code: "INVALID_STATE", message: "Only draft can be submitted" } },
      409
    );
  }
  await db(c.env.DATABASE_URL)`
    UPDATE inv_requests
    SET status = 'submitted', submitted_at = NOW(), version = version + 1, updated_at = NOW()
    WHERE id = ${id}::uuid
  `;
  const updated = await db<InvRequestRow>(c.env.DATABASE_URL)`
    SELECT id, kind, status, maker_id, approver_id,
           source_id, dest_id, reason, version, created_at
    FROM inv_requests WHERE id = ${id}::uuid LIMIT 1
  `;
  return c.json(await formatStockRequest(c.env.DATABASE_URL, updated[0]));
});

inventoryRoutes.delete("/requests/:id", async (c) => {
  const user = getUser(c);
  if (!user.caps.includes("inventory:create_request")) return c.json({ detail: "Bạn không có quyền xoá phiếu kho." }, 403);
  const id = c.req.param("id");
  if (!/^[0-9a-f-]{36}$/i.test(id)) return c.json({ detail: "Mã phiếu không hợp lệ." }, 422);
  const rows = await db<InvRequestRow>(c.env.DATABASE_URL)`SELECT id, status, maker_id FROM inv_requests WHERE id = ${id}::uuid LIMIT 1`;
  if (!rows.length) return c.json({ detail: "Không tìm thấy phiếu." }, 404);
  if (rows[0].maker_id !== user.sub) return c.json({ detail: "Chỉ người lập được xoá phiếu nháp." }, 403);
  if (rows[0].status !== "draft") return c.json({ detail: "Chỉ được xoá phiếu nháp." }, 409);
  await db(c.env.DATABASE_URL)`DELETE FROM inv_request_lines WHERE request_id = ${id}::uuid`;
  await db(c.env.DATABASE_URL)`DELETE FROM inv_requests WHERE id = ${id}::uuid AND status = 'draft' AND maker_id = ${user.sub}::uuid`;
  return c.json({ status: "deleted", id });
});

// POST /inventory/requests/:id/approve
inventoryRoutes.post("/requests/:id/approve", async (c) => {
  const user = getUser(c);
  const id = c.req.param("id");
  const rows = await db<InvRequestRow>(c.env.DATABASE_URL)`
    SELECT id, kind, status, maker_id, approver_id,
           source_id, dest_id, reason, version, created_at
    FROM inv_requests WHERE id = ${id}::uuid LIMIT 1
  `;
  if (!rows.length) {
    return c.json({ error: { code: "NOT_FOUND", message: "Request not found" } }, 404);
  }
  const req = rows[0];
  if (req.status !== "submitted") {
    return c.json(
      { error: { code: "INVALID_STATE", message: "Only submitted requests can be approved" } },
      409
    );
  }
  if (req.maker_id === user.sub) {
    return c.json(
      { error: { code: "MAKER_CHECKER_VIOLATION", message: "Maker cannot approve own request" } },
      403
    );
  }
  if (!user.caps.includes("inventory:approve_request")) {
    return c.json({ error: { code: "FORBIDDEN", message: "Missing inventory:approve_request" } }, 403);
  }

  const lines = await db<InvLineRow>(c.env.DATABASE_URL)`
    SELECT id, request_id, item_id, quantity, serial
    FROM inv_request_lines WHERE request_id = ${id}::uuid
  `;
  const needsPin = req.kind === "issue" || req.kind === "transfer"
    ? lines.reduce((total, line) => total + Number(line.quantity), 0) >= 50
    : false;
  if (needsPin) {
    try {
      const body = await c.req.json<{ supervisor_pin?: string }>().catch(() => ({} as { supervisor_pin?: string }));
      const userRows = await db<{ pin_hash?: string | null }>(c.env.DATABASE_URL)`
        SELECT pin_hash FROM iam_users WHERE id = ${user.sub}::uuid LIMIT 1
      `;
      const userPinHash = userRows[0]?.pin_hash;
      if (!(await requireSupervisorPin(body.supervisor_pin, c.env, userPinHash))) {
        return c.json({ error: { code: "SUPERVISOR_PIN_INVALID", message: "Mã PIN kiểm soát viên không đúng." } }, 403);
      }
    } catch {
      return c.json({ error: { code: "SUPERVISOR_PIN_UNCONFIGURED", message: "Xác thực kiểm soát viên chưa được cấu hình." } }, 503);
    }
  }
  const sql = db(c.env.DATABASE_URL);

  for (const line of lines) {
    const qty = Number(line.quantity);
    if (req.kind === "issue" || req.kind === "transfer") {
      const srcLoc = req.source_id!;
      await sql`
        INSERT INTO inv_movements
          (id, request_id, line_id, item_id, location_id, quantity_signed, posted_at, created_at, updated_at)
        VALUES
          (${crypto.randomUUID()}::uuid, ${id}::uuid, ${line.id}::uuid, ${line.item_id}::uuid, ${srcLoc}::uuid, ${-qty}, NOW(), NOW(), NOW())
      `;
      await sql`
        UPDATE inv_balances
        SET quantity = quantity - ${qty}, version = version + 1
        WHERE item_id = ${line.item_id}::uuid AND location_id = ${srcLoc}::uuid
      `;
    }
    if (req.kind === "receipt" || req.kind === "transfer") {
      const dstLoc = req.dest_id!;
      await sql`
        INSERT INTO inv_movements
          (id, request_id, line_id, item_id, location_id, quantity_signed, posted_at, created_at, updated_at)
        VALUES
          (${crypto.randomUUID()}::uuid, ${id}::uuid, ${line.id}::uuid, ${line.item_id}::uuid, ${dstLoc}::uuid, ${qty}, NOW(), NOW(), NOW())
      `;
      await sql`
        INSERT INTO inv_balances (location_id, item_id, quantity, version)
        VALUES (${dstLoc}::uuid, ${line.item_id}::uuid, ${qty}, 1)
        ON CONFLICT (location_id, item_id) DO UPDATE
        SET quantity = inv_balances.quantity + ${qty},
            version = inv_balances.version + 1
      `;
    }
  }

  await sql`
    UPDATE inv_requests
    SET status = 'posted', approver_id = ${user.sub}::uuid,
        version = version + 1, updated_at = NOW()
    WHERE id = ${id}::uuid
  `;
  const updated = await db<InvRequestRow>(c.env.DATABASE_URL)`
    SELECT id, kind, status, maker_id, approver_id,
           source_id, dest_id, reason, version, created_at
    FROM inv_requests WHERE id = ${id}::uuid LIMIT 1
  `;
  return c.json(await formatStockRequest(c.env.DATABASE_URL, updated[0]));
});

// POST /inventory/requests/:id/reject
inventoryRoutes.post("/requests/:id/reject", async (c) => {
  const user = getUser(c);
  const id = c.req.param("id");
  const rows = await db<InvRequestRow>(c.env.DATABASE_URL)`
    SELECT id, kind, status, maker_id, approver_id,
           source_id, dest_id, reason, version, created_at
    FROM inv_requests WHERE id = ${id}::uuid LIMIT 1
  `;
  if (!rows.length) {
    return c.json({ error: { code: "NOT_FOUND", message: "Request not found" } }, 404);
  }
  const req = rows[0];
  if (req.status !== "submitted") {
    return c.json(
      { error: { code: "INVALID_STATE", message: "Only submitted requests can be rejected" } },
      409
    );
  }
  if (req.maker_id === user.sub) {
    return c.json(
      { error: { code: "MAKER_CHECKER_VIOLATION", message: "Maker cannot reject own request" } },
      403
    );
  }
  await db(c.env.DATABASE_URL)`
    UPDATE inv_requests
    SET status = 'rejected', approver_id = ${user.sub}::uuid, version = version + 1, updated_at = NOW()
    WHERE id = ${id}::uuid
  `;
  const updated = await db<InvRequestRow>(c.env.DATABASE_URL)`
    SELECT id, kind, status, maker_id, approver_id,
           source_id, dest_id, reason, version, created_at
    FROM inv_requests WHERE id = ${id}::uuid LIMIT 1
  `;
  return c.json(await formatStockRequest(c.env.DATABASE_URL, updated[0]));
});
