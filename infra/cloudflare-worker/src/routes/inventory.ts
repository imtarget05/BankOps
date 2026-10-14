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
  reserved_quantity?: string;
  available_quantity?: string;
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
  return_reason?: string | null;
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
        SELECT item_id, location_id, quantity,
               COALESCE(reserved_quantity, 0)::text as reserved_quantity,
               GREATEST(0, quantity - COALESCE(reserved_quantity, 0))::text as available_quantity,
               version
        FROM inv_balances
        WHERE location_id = ${locationId}::uuid
      `
    : await sql`
        SELECT item_id, location_id, quantity,
               COALESCE(reserved_quantity, 0)::text as reserved_quantity,
               GREATEST(0, quantity - COALESCE(reserved_quantity, 0))::text as available_quantity,
               version
        FROM inv_balances
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
    return_reason: r.return_reason ?? null,
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
  if (req.status !== "draft" && req.status !== "returned") {
    return c.json(
      { error: { code: "INVALID_STATE", message: "Only draft or returned can be submitted" } },
      409
    );
  }
  if (req.kind === "issue" || req.kind === "transfer") {
    const lines = await db<InvLineRow>(c.env.DATABASE_URL)`
      SELECT item_id, quantity FROM inv_request_lines WHERE request_id = ${id}::uuid
    `;
    for (const line of lines) {
      await db(c.env.DATABASE_URL)`
        UPDATE inv_balances
        SET reserved_quantity = COALESCE(reserved_quantity, 0) + ${Number(line.quantity)}
        WHERE item_id = ${line.item_id}::uuid AND location_id = ${req.source_id}::uuid
      `;
    }
  }
  await db(c.env.DATABASE_URL)`
    UPDATE inv_requests
    SET status = 'submitted', submitted_at = NOW(), version = version + 1, updated_at = NOW()
    WHERE id = ${id}::uuid
  `;
  const updated = await db<InvRequestRow>(c.env.DATABASE_URL)`
    SELECT id, kind, status, maker_id, approver_id,
           source_id, dest_id, reason, return_reason, version, created_at
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
           source_id, dest_id, reason, return_reason, version, created_at
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
  const canApprove =
    user.caps.includes("inventory:approve_request") ||
    user.roles?.some((r) =>
      ["admin", "system_admin", "approver", "checker", "supervisor"].includes(r.toLowerCase())
    );
  if (!canApprove) {
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
        SET quantity = quantity - ${qty},
            reserved_quantity = GREATEST(0, COALESCE(reserved_quantity, 0) - ${qty}),
            version = version + 1
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
    if (line.serial) {
      const assets = (await sql`SELECT id, status FROM inv_assets WHERE serial = ${line.serial} LIMIT 1`) as unknown as { id: string; status: string }[];
      if (assets.length) {
        const a = assets[0];
        const newStatus = req.kind === "issue" ? "issued" : "available";
        const targetLoc = req.kind === "transfer" ? req.dest_id : null;
        await sql`
          INSERT INTO inv_asset_logs (id, asset_id, serial, from_location_id, to_location_id, status_before, status_after, request_id, actor_id, notes, created_at)
          VALUES (${crypto.randomUUID()}::uuid, ${a.id}::uuid, ${line.serial}, ${req.source_id}::uuid, ${targetLoc ? targetLoc + "::uuid" : null}, ${a.status}, ${newStatus}, ${id}::uuid, ${user.sub}::uuid, ${req.kind === "issue" ? "Xuất kho" : "Chuyển kho"}, NOW())
        `;
        if (req.kind === "transfer" && req.dest_id) {
          await sql`UPDATE inv_assets SET location_id = ${req.dest_id}::uuid, updated_at = NOW() WHERE id = ${a.id}::uuid`;
        } else if (req.kind === "issue") {
          await sql`UPDATE inv_assets SET status = 'issued', updated_at = NOW() WHERE id = ${a.id}::uuid`;
        }
      }
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
           source_id, dest_id, reason, return_reason, version, created_at
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
           source_id, dest_id, reason, return_reason, version, created_at
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
  const canApprove =
    user.caps.includes("inventory:approve_request") ||
    user.roles?.some((r) =>
      ["admin", "system_admin", "approver", "checker", "supervisor"].includes(r.toLowerCase())
    );
  if (!canApprove) {
    return c.json({ error: { code: "FORBIDDEN", message: "Missing approval permissions" } }, 403);
  }

  if (req.kind === "issue" || req.kind === "transfer") {
    const lines = await db<InvLineRow>(c.env.DATABASE_URL)`
      SELECT item_id, quantity FROM inv_request_lines WHERE request_id = ${id}::uuid
    `;
    for (const line of lines) {
      await db(c.env.DATABASE_URL)`
        UPDATE inv_balances
        SET reserved_quantity = GREATEST(0, COALESCE(reserved_quantity, 0) - ${Number(line.quantity)})
        WHERE item_id = ${line.item_id}::uuid AND location_id = ${req.source_id}::uuid
      `;
    }
  }

  await db(c.env.DATABASE_URL)`
    UPDATE inv_requests
    SET status = 'rejected', approver_id = ${user.sub}::uuid, version = version + 1, updated_at = NOW()
    WHERE id = ${id}::uuid
  `;
  const updated = await db<InvRequestRow>(c.env.DATABASE_URL)`
    SELECT id, kind, status, maker_id, approver_id,
           source_id, dest_id, reason, return_reason, version, created_at
    FROM inv_requests WHERE id = ${id}::uuid LIMIT 1
  `;
  return c.json(await formatStockRequest(c.env.DATABASE_URL, updated[0]));
});

// POST /inventory/requests/:id/return
inventoryRoutes.post("/requests/:id/return", async (c) => {
  const user = getUser(c);
  const id = c.req.param("id");
  const rows = await db<InvRequestRow>(c.env.DATABASE_URL)`
    SELECT id, kind, status, maker_id, approver_id,
           source_id, dest_id, reason, return_reason, version, created_at
    FROM inv_requests WHERE id = ${id}::uuid LIMIT 1
  `;
  if (!rows.length) {
    return c.json({ error: { code: "NOT_FOUND", message: "Request not found" } }, 404);
  }
  const req = rows[0];
  if (req.status !== "submitted") {
    return c.json(
      { error: { code: "INVALID_STATE", message: "Only submitted requests can be returned" } },
      409
    );
  }
  if (req.maker_id === user.sub) {
    return c.json(
      { error: { code: "MAKER_CHECKER_VIOLATION", message: "Maker cannot return own request" } },
      403
    );
  }
  const canApprove =
    user.caps.includes("inventory:approve_request") ||
    user.roles?.some((r) =>
      ["admin", "system_admin", "approver", "checker", "supervisor"].includes(r.toLowerCase())
    );
  if (!canApprove) {
    return c.json({ error: { code: "FORBIDDEN", message: "Missing approval permissions" } }, 403);
  }

  const body = await c.req.json<{ reason?: string }>().catch(() => ({} as { reason?: string }));
  const returnReason = String(body.reason || "").trim();
  if (returnReason.length < 3) {
    return c.json({ detail: "Lý do trả về phải có ít nhất 3 ký tự." }, 422);
  }

  if (req.kind === "issue" || req.kind === "transfer") {
    const lines = await db<InvLineRow>(c.env.DATABASE_URL)`
      SELECT item_id, quantity FROM inv_request_lines WHERE request_id = ${id}::uuid
    `;
    for (const line of lines) {
      await db(c.env.DATABASE_URL)`
        UPDATE inv_balances
        SET reserved_quantity = GREATEST(0, COALESCE(reserved_quantity, 0) - ${Number(line.quantity)})
        WHERE item_id = ${line.item_id}::uuid AND location_id = ${req.source_id}::uuid
      `;
    }
  }

  await db(c.env.DATABASE_URL)`
    UPDATE inv_requests
    SET status = 'returned', return_reason = ${returnReason},
        approver_id = ${user.sub}::uuid, version = version + 1, updated_at = NOW()
    WHERE id = ${id}::uuid
  `;
  const updated = await db<InvRequestRow>(c.env.DATABASE_URL)`
    SELECT id, kind, status, maker_id, approver_id,
           source_id, dest_id, reason, return_reason, version, created_at
    FROM inv_requests WHERE id = ${id}::uuid LIMIT 1
  `;
  return c.json(await formatStockRequest(c.env.DATABASE_URL, updated[0]));
});

// POST /inventory/assets
inventoryRoutes.post("/assets", async (c) => {
  const user = getUser(c);
  if (!user.caps.includes("inventory:create_request")) return c.json({ detail: "Bạn không có quyền tạo ấn chỉ." }, 403);
  const body = await c.req.json<{ serial: string; item_id: string; location_id: string; status?: string }>();
  if (!body.serial || !body.item_id || !body.location_id) {
    return c.json({ detail: "serial, item_id, location_id là bắt buộc" }, 422);
  }
  const assetId = crypto.randomUUID();
  const sql = db(c.env.DATABASE_URL);
  await sql`
    INSERT INTO inv_assets (id, serial, item_id, location_id, status, created_at, updated_at)
    VALUES (${assetId}::uuid, ${body.serial}, ${body.item_id}::uuid, ${body.location_id}::uuid, ${body.status ?? "available"}, NOW(), NOW())
  `;
  await sql`
    INSERT INTO inv_asset_logs (id, asset_id, serial, from_location_id, to_location_id, status_before, status_after, actor_id, notes, created_at)
    VALUES (${crypto.randomUUID()}::uuid, ${assetId}::uuid, ${body.serial}, NULL, ${body.location_id}::uuid, NULL, ${body.status ?? "available"}, ${user.sub}::uuid, 'Khởi tạo số serial ấn chỉ vào hệ thống', NOW())
  `;
  return c.json({ id: assetId, serial: body.serial, item_id: body.item_id, location_id: body.location_id, status: body.status ?? "available" }, 201);
});

// GET /inventory/assets/:id/history
inventoryRoutes.get("/assets/:id/history", async (c) => {
  const id = c.req.param("id");
  const sql = db(c.env.DATABASE_URL);
  const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id);
  const assets = isUuid
    ? ((await sql`
        SELECT id, serial, status, location_id, assignee_demo FROM inv_assets WHERE id = ${id}::uuid LIMIT 1
      `) as unknown as { id: string; serial: string; status: string; location_id: string; assignee_demo: string | null }[])
    : ((await sql`
        SELECT id, serial, status, location_id, assignee_demo FROM inv_assets WHERE serial = ${id} LIMIT 1
      `) as unknown as { id: string; serial: string; status: string; location_id: string; assignee_demo: string | null }[]);
  if (!assets.length) return c.json({ detail: "Không tìm thấy ấn chỉ." }, 404);
  const asset = assets[0];
  const logs = await sql`
    SELECT l.id, l.serial, l.from_location_id, l.to_location_id, l.from_assignee, l.to_assignee,
           l.status_before, l.status_after, l.actor_id, l.request_id, l.notes, l.created_at,
           fl.name as from_location_name, tl.name as to_location_name,
           u.display_name_demo as actor_name
    FROM inv_asset_logs l
    LEFT JOIN inv_locations fl ON fl.id = l.from_location_id
    LEFT JOIN inv_locations tl ON tl.id = l.to_location_id
    LEFT JOIN iam_users u ON u.id = l.actor_id
    WHERE l.asset_id = ${asset.id}::uuid
    ORDER BY l.created_at DESC
  `;
  return c.json({
    asset,
    history: logs,
    simulation: true,
  });
});

// POST /inventory/assets/:id/handover
inventoryRoutes.post("/assets/:id/handover", async (c) => {
  const user = getUser(c);
  const id = c.req.param("id");
  const sql = db(c.env.DATABASE_URL);
  const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id);
  const assets = isUuid
    ? ((await sql`
        SELECT id, serial, status, location_id, assignee_demo FROM inv_assets WHERE id = ${id}::uuid LIMIT 1
      `) as unknown as { id: string; serial: string; status: string; location_id: string; assignee_demo: string | null }[])
    : ((await sql`
        SELECT id, serial, status, location_id, assignee_demo FROM inv_assets WHERE serial = ${id} LIMIT 1
      `) as unknown as { id: string; serial: string; status: string; location_id: string; assignee_demo: string | null }[]);
  if (!assets.length) return c.json({ detail: "Không tìm thấy ấn chỉ." }, 404);
  const asset = assets[0];
  const body = await c.req.json<{ to_location_id?: string; to_assignee?: string; status?: string; notes?: string }>();
  const newStatus = body.status || asset.status;
  const toLoc = body.to_location_id || asset.location_id;
  const toAssignee = body.to_assignee !== undefined ? body.to_assignee : asset.assignee_demo;
  const notes = body.notes || "Bàn giao ấn chỉ nội bộ";

  await sql`
    UPDATE inv_assets
    SET location_id = ${toLoc}::uuid, assignee_demo = ${toAssignee}, status = ${newStatus}, updated_at = NOW()
    WHERE id = ${asset.id}::uuid
  `;
  const logId = crypto.randomUUID();
  await sql`
    INSERT INTO inv_asset_logs (id, asset_id, serial, from_location_id, to_location_id, from_assignee, to_assignee, status_before, status_after, actor_id, notes, created_at)
    VALUES (${logId}::uuid, ${asset.id}::uuid, ${asset.serial}, ${asset.location_id}::uuid, ${toLoc}::uuid, ${asset.assignee_demo}, ${toAssignee}, ${asset.status}, ${newStatus}, ${user.sub}::uuid, ${notes}, NOW())
  `;
  return c.json({ id: asset.id, serial: asset.serial, status: newStatus, location_id: toLoc, assignee: toAssignee, log_id: logId });
});

interface InvStockLevel {
  id: string;
  location_id: string;
  item_id: string;
  min_qty: string;
  max_qty: string | null;
  created_at: string;
  updated_at: string;
}

interface InvStocktake {
  id: string;
  location_id: string;
  status: string;
  note: string | null;
  maker_id: string;
  approver_id: string | null;
  adjustment_request_id: string | null;
  created_at: string;
  completed_at: string | null;
}

interface InvStocktakeLine {
  id: string;
  stocktake_id: string;
  item_id: string;
  book_qty: string;
  counted_qty: string;
  variance: string;
  reason: string | null;
}

function formatQty(val: string | number | null | undefined): string | null {
  if (val === null || val === undefined) return null;
  const num = Number(val);
  if (isNaN(num)) return String(val);
  if (Number.isInteger(num)) return num.toString();
  return num.toString();
}

// PUT /inventory/stock-levels
inventoryRoutes.put("/stock-levels", async (c) => {
  const user = getUser(c);
  if (!canManageCatalog(user)) {
    return c.json({ detail: "Bạn không có quyền quản lý định mức kho." }, 403);
  }
  interface StockLevelPayload {
    location_id?: string;
    item_id?: string;
    min_qty?: string | number;
    max_qty?: string | number | null;
  }
  const body = await c.req.json<StockLevelPayload>().catch((): StockLevelPayload => ({}));

  if (!body.location_id || !body.item_id) {
    return c.json({ error: { code: "VALIDATION_ERROR", message: "location_id và item_id là bắt buộc" } }, 422);
  }
  if (body.min_qty === undefined || body.min_qty === null) {
    return c.json({ error: { code: "MISSING_MIN_QTY", message: "min_qty là bắt buộc" } }, 422);
  }
  const minQty = Number(body.min_qty);
  if (isNaN(minQty) || minQty < 0) {
    return c.json({ error: { code: "INVALID_MIN_QTY", message: "min_qty không được âm" } }, 422);
  }
  let maxQty: number | null = null;
  if (body.max_qty !== undefined && body.max_qty !== null && body.max_qty !== "") {
    maxQty = Number(body.max_qty);
    if (isNaN(maxQty) || maxQty < minQty) {
      return c.json({ error: { code: "INVALID_STOCK_LEVEL", message: "max_qty phải lớn hơn hoặc bằng min_qty" } }, 422);
    }
  }

  const existing = await db<InvStockLevel>(c.env.DATABASE_URL)`
    SELECT id, location_id, item_id, min_qty, max_qty, created_at, updated_at
    FROM inv_stock_levels
    WHERE location_id = ${body.location_id}::uuid AND item_id = ${body.item_id}::uuid
    LIMIT 1
  `;

  let row: InvStockLevel;
  if (existing.length > 0) {
    const updated = await db<InvStockLevel>(c.env.DATABASE_URL)`
      UPDATE inv_stock_levels
      SET min_qty = ${minQty}, max_qty = ${maxQty}, updated_at = NOW()
      WHERE id = ${existing[0].id}::uuid
      RETURNING id, location_id, item_id, min_qty, max_qty, created_at, updated_at
    `;
    row = updated[0];
  } else {
    const inserted = await db<InvStockLevel>(c.env.DATABASE_URL)`
      INSERT INTO inv_stock_levels (id, location_id, item_id, min_qty, max_qty, created_at, updated_at)
      VALUES (${crypto.randomUUID()}::uuid, ${body.location_id}::uuid, ${body.item_id}::uuid, ${minQty}, ${maxQty}, NOW(), NOW())
      RETURNING id, location_id, item_id, min_qty, max_qty, created_at, updated_at
    `;
    row = inserted[0];
  }

  return c.json({
    id: row.id,
    location_id: row.location_id,
    item_id: row.item_id,
    min_qty: formatQty(row.min_qty),
    max_qty: formatQty(row.max_qty),
  });
});

// GET /inventory/stock-levels
inventoryRoutes.get("/stock-levels", async (c) => {
  const locId = c.req.query("location_id");
  const itemId = c.req.query("item_id");
  let levels: InvStockLevel[];
  if (locId && itemId) {
    levels = await db<InvStockLevel>(c.env.DATABASE_URL)`
      SELECT id, location_id, item_id, min_qty, max_qty, created_at, updated_at
      FROM inv_stock_levels
      WHERE location_id = ${locId}::uuid AND item_id = ${itemId}::uuid
    `;
  } else if (locId) {
    levels = await db<InvStockLevel>(c.env.DATABASE_URL)`
      SELECT id, location_id, item_id, min_qty, max_qty, created_at, updated_at
      FROM inv_stock_levels
      WHERE location_id = ${locId}::uuid
    `;
  } else if (itemId) {
    levels = await db<InvStockLevel>(c.env.DATABASE_URL)`
      SELECT id, location_id, item_id, min_qty, max_qty, created_at, updated_at
      FROM inv_stock_levels
      WHERE item_id = ${itemId}::uuid
    `;
  } else {
    levels = await db<InvStockLevel>(c.env.DATABASE_URL)`
      SELECT id, location_id, item_id, min_qty, max_qty, created_at, updated_at
      FROM inv_stock_levels
    `;
  }

  return c.json({
    stock_levels: levels.map((l) => ({
      id: l.id,
      location_id: l.location_id,
      item_id: l.item_id,
      min_qty: formatQty(l.min_qty),
      max_qty: formatQty(l.max_qty),
    })),
  });
});

// GET /inventory/low-stock
inventoryRoutes.get("/low-stock", async (c) => {
  const locId = c.req.query("location_id");
  let levels: InvStockLevel[];
  if (locId) {
    levels = await db<InvStockLevel>(c.env.DATABASE_URL)`
      SELECT id, location_id, item_id, min_qty, max_qty, created_at, updated_at
      FROM inv_stock_levels WHERE location_id = ${locId}::uuid
    `;
  } else {
    levels = await db<InvStockLevel>(c.env.DATABASE_URL)`
      SELECT id, location_id, item_id, min_qty, max_qty, created_at, updated_at
      FROM inv_stock_levels
    `;
  }

  const itemsOut: Array<{
    location_id: string;
    location_code: string;
    location_name: string;
    item_id: string;
    sku: string;
    item_name: string;
    unit: string;
    current_qty: string;
    min_qty: string;
    max_qty: string | null;
    status: string;
    deficit: string;
    suggested_action: string;
  }> = [];

  for (const level of levels) {
    const balRows = await db<InvBalance>(c.env.DATABASE_URL)`
      SELECT location_id, item_id, quantity, version
      FROM inv_balances
      WHERE location_id = ${level.location_id}::uuid AND item_id = ${level.item_id}::uuid
      LIMIT 1
    `;
    const curQty = balRows.length > 0 ? Number(balRows[0].quantity) : 0;
    const minQty = Number(level.min_qty);
    if (curQty < minQty) {
      const locRows = await db<InvLocation>(c.env.DATABASE_URL)`
        SELECT id, code, name, active FROM inv_locations WHERE id = ${level.location_id}::uuid LIMIT 1
      `;
      const itemRows = await db<InvItem>(c.env.DATABASE_URL)`
        SELECT id, sku, name, unit, tracked_serial, active FROM inv_items WHERE id = ${level.item_id}::uuid LIMIT 1
      `;
      const loc = locRows[0];
      const it = itemRows[0];
      const deficit = minQty - curQty;
      const status = curQty <= 0 ? "empty" : "low";
      const unit = it?.unit || "đơn vị";
      const deficitStr = formatQty(deficit)!;
      itemsOut.push({
        location_id: level.location_id,
        location_code: loc?.code || "N/A",
        location_name: loc?.name || "N/A",
        item_id: level.item_id,
        sku: it?.sku || "N/A",
        item_name: it?.name || "N/A",
        unit,
        current_qty: formatQty(curQty)!,
        min_qty: formatQty(minQty)!,
        max_qty: formatQty(level.max_qty),
        status,
        deficit: deficitStr,
        suggested_action: `Đề xuất lập phiếu nhập kho hoặc chuyển kho bổ sung tối thiểu ${deficitStr} ${unit}`,
      });
    }
  }

  return c.json({ items: itemsOut });
});

async function formatStocktake(databaseUrl: string, st: InvStocktake) {
  const lines = await db<InvStocktakeLine>(databaseUrl)`
    SELECT id, stocktake_id, item_id, book_qty, counted_qty, variance, reason
    FROM inv_stocktake_lines
    WHERE stocktake_id = ${st.id}::uuid
    ORDER BY id ASC
  `;
  return {
    id: st.id,
    location_id: st.location_id,
    status: st.status,
    note: st.note,
    maker_id: st.maker_id,
    approver_id: st.approver_id,
    adjustment_request_id: st.adjustment_request_id,
    created_at: st.created_at,
    completed_at: st.completed_at,
    lines: lines.map((l) => ({
      id: l.id,
      item_id: l.item_id,
      book_qty: formatQty(l.book_qty),
      counted_qty: formatQty(l.counted_qty),
      variance: formatQty(l.variance),
      reason: l.reason,
    })),
  };
}

// POST /inventory/stocktakes
inventoryRoutes.post("/stocktakes", async (c) => {
  const user = getUser(c);
  interface StocktakePayload {
    location_id?: string;
    note?: string;
  }
  const body = await c.req.json<StocktakePayload>().catch((): StocktakePayload => ({}));
  if (!body.location_id) {
    return c.json({ error: { code: "VALIDATION_ERROR", message: "location_id là bắt buộc" } }, 422);
  }
  const id = crypto.randomUUID();
  const rows = await db<InvStocktake>(c.env.DATABASE_URL)`
    INSERT INTO inv_stocktakes (id, location_id, status, note, maker_id, created_at)
    VALUES (${id}::uuid, ${body.location_id}::uuid, 'open', ${body.note || null}, ${user.sub}::uuid, NOW())
    RETURNING id, location_id, status, note, maker_id, approver_id, adjustment_request_id, created_at, completed_at
  `;
  return c.json(await formatStocktake(c.env.DATABASE_URL, rows[0]), 201);
});

// GET /inventory/stocktakes
inventoryRoutes.get("/stocktakes", async (c) => {
  const locId = c.req.query("location_id");
  let rows: InvStocktake[];
  if (locId) {
    rows = await db<InvStocktake>(c.env.DATABASE_URL)`
      SELECT id, location_id, status, note, maker_id, approver_id, adjustment_request_id, created_at, completed_at
      FROM inv_stocktakes
      WHERE location_id = ${locId}::uuid
      ORDER BY created_at DESC
    `;
  } else {
    rows = await db<InvStocktake>(c.env.DATABASE_URL)`
      SELECT id, location_id, status, note, maker_id, approver_id, adjustment_request_id, created_at, completed_at
      FROM inv_stocktakes
      ORDER BY created_at DESC
    `;
  }
  const stocktakes = await Promise.all(rows.map((st) => formatStocktake(c.env.DATABASE_URL, st)));
  return c.json({ stocktakes });
});

// GET /inventory/stocktakes/:id
inventoryRoutes.get("/stocktakes/:id", async (c) => {
  const id = c.req.param("id");
  const rows = await db<InvStocktake>(c.env.DATABASE_URL)`
    SELECT id, location_id, status, note, maker_id, approver_id, adjustment_request_id, created_at, completed_at
    FROM inv_stocktakes WHERE id = ${id}::uuid LIMIT 1
  `;
  if (!rows.length) {
    return c.json({ error: { code: "NOT_FOUND", message: "Đợt kiểm kê không tồn tại" } }, 404);
  }
  return c.json(await formatStocktake(c.env.DATABASE_URL, rows[0]));
});

// PUT /inventory/stocktakes/:id/lines
inventoryRoutes.put("/stocktakes/:id/lines", async (c) => {
  const id = c.req.param("id");
  interface StocktakeLinesPayload {
    lines?: Array<{ item_id: string; counted_qty: string | number; reason?: string }>;
  }
  const body = await c.req.json<StocktakeLinesPayload>().catch((): StocktakeLinesPayload => ({}));
  const rows = await db<InvStocktake>(c.env.DATABASE_URL)`
    SELECT id, location_id, status, note, maker_id, approver_id, adjustment_request_id, created_at, completed_at
    FROM inv_stocktakes WHERE id = ${id}::uuid LIMIT 1
  `;
  if (!rows.length) {
    return c.json({ error: { code: "NOT_FOUND", message: "Đợt kiểm kê không tồn tại" } }, 404);
  }
  const st = rows[0];
  if (st.status !== "open") {
    return c.json({ error: { code: "INVALID_STATE", message: "Chỉ được cập nhật dòng kiểm kê khi trạng thái là open" } }, 409);
  }

  for (const line of body.lines || []) {
    const balRows = await db<InvBalance>(c.env.DATABASE_URL)`
      SELECT quantity FROM inv_balances
      WHERE location_id = ${st.location_id}::uuid AND item_id = ${line.item_id}::uuid
      LIMIT 1
    `;
    const bookQty = balRows.length > 0 ? Number(balRows[0].quantity) : 0;
    const countedQty = Number(line.counted_qty);
    const variance = countedQty - bookQty;
    const reason = line.reason || null;

    await db(c.env.DATABASE_URL)`
      INSERT INTO inv_stocktake_lines (id, stocktake_id, item_id, book_qty, counted_qty, variance, reason)
      VALUES (${crypto.randomUUID()}::uuid, ${id}::uuid, ${line.item_id}::uuid, ${bookQty}, ${countedQty}, ${variance}, ${reason})
      ON CONFLICT (stocktake_id, item_id) DO UPDATE
      SET book_qty = ${bookQty}, counted_qty = ${countedQty}, variance = ${variance}, reason = ${reason}
    `;
  }

  return c.json(await formatStocktake(c.env.DATABASE_URL, st));
});

// POST /inventory/stocktakes/:id/submit
inventoryRoutes.post("/stocktakes/:id/submit", async (c) => {
  const id = c.req.param("id");
  const rows = await db<InvStocktake>(c.env.DATABASE_URL)`
    SELECT id, location_id, status, note, maker_id, approver_id, adjustment_request_id, created_at, completed_at
    FROM inv_stocktakes WHERE id = ${id}::uuid LIMIT 1
  `;
  if (!rows.length) {
    return c.json({ error: { code: "NOT_FOUND", message: "Đợt kiểm kê không tồn tại" } }, 404);
  }
  const st = rows[0];
  if (st.status !== "open") {
    return c.json({ error: { code: "INVALID_STATE", message: "Chỉ đợt kiểm kê đang open mới có thể đệ trình" } }, 409);
  }
  await db(c.env.DATABASE_URL)`
    UPDATE inv_stocktakes SET status = 'submitted' WHERE id = ${id}::uuid
  `;
  const updated = await db<InvStocktake>(c.env.DATABASE_URL)`
    SELECT id, location_id, status, note, maker_id, approver_id, adjustment_request_id, created_at, completed_at
    FROM inv_stocktakes WHERE id = ${id}::uuid LIMIT 1
  `;
  return c.json(await formatStocktake(c.env.DATABASE_URL, updated[0]));
});

// POST /inventory/stocktakes/:id/approve
inventoryRoutes.post("/stocktakes/:id/approve", async (c) => {
  const user = getUser(c);
  const id = c.req.param("id");
  const rows = await db<InvStocktake>(c.env.DATABASE_URL)`
    SELECT id, location_id, status, note, maker_id, approver_id, adjustment_request_id, created_at, completed_at
    FROM inv_stocktakes WHERE id = ${id}::uuid LIMIT 1
  `;
  if (!rows.length) {
    return c.json({ error: { code: "NOT_FOUND", message: "Đợt kiểm kê không tồn tại" } }, 404);
  }
  const st = rows[0];
  if (st.status !== "submitted") {
    return c.json({ error: { code: "INVALID_STATE", message: "Chỉ đợt kiểm kê đã submit mới có thể phê duyệt" } }, 409);
  }
  if (st.maker_id === user.sub) {
    return c.json({ error: { code: "SELF_APPROVAL_FORBIDDEN", message: "Người tạo không được tự phê duyệt kiểm kê (nguyên tắc kiểm soát kép)" } }, 403);
  }

  const lines = await db<InvStocktakeLine>(c.env.DATABASE_URL)`
    SELECT id, stocktake_id, item_id, book_qty, counted_qty, variance, reason
    FROM inv_stocktake_lines WHERE stocktake_id = ${id}::uuid
  `;

  const varianceLines = lines.filter((l) => Number(l.variance) !== 0);
  let adjReqId: string | null = null;

  if (varianceLines.length > 0) {
    adjReqId = crypto.randomUUID();
    await db(c.env.DATABASE_URL)`
      INSERT INTO inv_requests (id, kind, status, maker_id, approver_id, source_id, dest_id, reason, version, created_at, updated_at)
      VALUES (${adjReqId}::uuid, 'adjustment', 'submitted', ${st.maker_id}::uuid, NULL, NULL, ${st.location_id}::uuid, ${'Điều chỉnh tồn sau kiểm kê ' + id}, 1, NOW(), NOW())
    `;
    for (const vl of varianceLines) {
      await db(c.env.DATABASE_URL)`
        INSERT INTO inv_request_lines (id, request_id, item_id, quantity, serial)
        VALUES (${crypto.randomUUID()}::uuid, ${adjReqId}::uuid, ${vl.item_id}::uuid, ${Math.abs(Number(vl.variance))}, NULL)
      `;
    }
  }

  if (adjReqId) {
    await db(c.env.DATABASE_URL)`
      UPDATE inv_stocktakes
      SET status = 'closed', approver_id = ${user.sub}::uuid, completed_at = NOW(), adjustment_request_id = ${adjReqId}::uuid
      WHERE id = ${id}::uuid
    `;
  } else {
    await db(c.env.DATABASE_URL)`
      UPDATE inv_stocktakes
      SET status = 'closed', approver_id = ${user.sub}::uuid, completed_at = NOW()
      WHERE id = ${id}::uuid
    `;
  }

  const updated = await db<InvStocktake>(c.env.DATABASE_URL)`
    SELECT id, location_id, status, note, maker_id, approver_id, adjustment_request_id, created_at, completed_at
    FROM inv_stocktakes WHERE id = ${id}::uuid LIMIT 1
  `;
  return c.json(await formatStocktake(c.env.DATABASE_URL, updated[0]));
});

