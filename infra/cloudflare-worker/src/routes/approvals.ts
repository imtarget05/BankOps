/**
 * Approvals routes – mirror FastAPI /approvals/*
 */

import { Hono } from "hono";
import { streamSSE } from "hono/streaming";
import { Env } from "../index";
import { db } from "../db/client";

export const approvalsRoutes = new Hono<{ Bindings: Env }>();

interface InvPendingRow {
  id: string;
  kind: string;
  status: string;
  maker_id: string;
  reason: string | null;
  maker_name: string | null;
  total_quantity: string;
}

interface CashPendingRow {
  id: string;
  kind: string;
  status: string;
  maker_id: string;
  amount: string;
  currency: string;
  reason: string | null;
  maker_name: string | null;
}

// GET /approvals/inbox – danh sách request đang chờ duyệt (kho + quỹ)
approvalsRoutes.get("/inbox", async (c) => {
  const user = c.get("user" as never) as { sub: string; caps: string[] };
  if (!user.caps.includes("approval:view_inbox")) {
    return c.json({ detail: "Bạn không có quyền xem phiếu chờ duyệt." }, 403);
  }
  const [invRows, cashRows] = await Promise.all([
    db<InvPendingRow>(c.env.DATABASE_URL)`
      SELECT r.id, r.kind, r.status, r.maker_id, r.reason,
             COALESCE(u.display_name_demo, u.username, r.maker_id::text) as maker_name,
             COALESCE(SUM(l.quantity), 0)::text AS total_quantity
      FROM inv_requests r
      LEFT JOIN inv_request_lines l ON l.request_id = r.id
      LEFT JOIN iam_users u ON u.id = r.maker_id
      WHERE r.status = 'submitted'
      GROUP BY r.id, u.display_name_demo, u.username
      ORDER BY r.created_at DESC
    `,
    db<CashPendingRow>(c.env.DATABASE_URL)`
      SELECT r.id, r.kind, r.status, r.maker_id, r.amount, b.currency, r.reason,
             COALESCE(u.display_name_demo, u.username, r.maker_id::text) as maker_name
      FROM cash_requests r
      LEFT JOIN iam_users u ON u.id = r.maker_id
      LEFT JOIN cash_boxes b ON b.id = r.cashbox_id
      WHERE r.status = 'submitted'
      ORDER BY r.created_at DESC
    `,
  ]);

  const approvals = [
    ...invRows.filter((r) => r.maker_id !== user.sub).map((r) => ({
      id: r.id,
      kind: "inventory",
      sub_kind: r.kind,
      status: r.status,
      maker_id: r.maker_id,
      maker: r.maker_name ?? r.maker_id,
      impact: `Kho (${r.kind}) · ${r.total_quantity} đơn vị`,
      approval_detail: JSON.stringify({
        kind: r.kind,
        total_quantity: r.total_quantity,
      }),
      detail: r.reason || r.id,
    })),
    ...cashRows.filter((r) => r.maker_id !== user.sub).map((r) => {
      const sign = r.kind === "payment" ? "-" : "+";
      return {
        id: r.id,
        kind: "cash",
        sub_kind: r.kind,
        status: r.status,
        maker_id: r.maker_id,
        maker: r.maker_name ?? r.maker_id,
        impact: `${sign}${r.amount} ${r.currency ?? "VND"}`,
        detail: r.reason || r.id,
      };
    }),
  ];

  return c.json({ approvals, total: approvals.length, simulation: true });
});

// GET /approvals/stream – Server-Sent Events (SSE) cho realtime approvals
approvalsRoutes.get("/stream", async (c) => {
  const user = c.get("user" as never) as
    | { sub: string; username: string; caps: string[] }
    | undefined;

  const allowedCaps = [
    "approval:view_inbox",
    "inventory:view_requests",
    "cash:view_requests",
  ];
  if (user?.caps && !user.caps.some((cap) => allowedCaps.includes(cap))) {
    return c.json(
      { detail: "User does not have permission to subscribe to approval stream" },
      403
    );
  }

  return streamSSE(c, async (stream) => {
    // 1. Initial connected event (matches FastAPI format)
    await stream.writeSSE({
      event: "connected",
      data: JSON.stringify({
        status: "connected",
        username: user?.username ?? "unknown",
        user_id: user?.sub ?? "",
      }),
    });

    // 2. Keepalive ping loop every 15 seconds
    while (!stream.aborted) {
      await stream.sleep(15000);
      if (stream.aborted) break;
      await stream.writeSSE({
        event: "ping",
        data: JSON.stringify({ time: new Date().toISOString() }),
      });
    }
  });
});
