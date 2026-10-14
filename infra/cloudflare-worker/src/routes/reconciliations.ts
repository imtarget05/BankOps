/**
 * Reconciliations routes – mirror FastAPI /reconciliations
 */

import { Hono } from "hono";
import { Env } from "../index";
import { db } from "../db/client";
import { JwtPayload } from "../middleware/auth";

export const reconciliationsRoutes = new Hono<{ Bindings: Env }>();

interface ReconRunRow {
  id: string;
  scope: string;
  status: string;
  auto_fixed: boolean;
  created_at: string;
}

interface ReconExcRow {
  subject: string;
  expected_json: Record<string, unknown>;
  actual_json: Record<string, unknown>;
}

function userOf(c: { get: (key: string) => unknown }): JwtPayload {
  return c.get("user") as JwtPayload;
}

function mayRead(user: JwtPayload): boolean {
  return user.caps.some((cap) => ["cash:reconcile", "audit:view", "approval:view_inbox"].includes(cap));
}

// GET /reconciliations
reconciliationsRoutes.get("/", async (c) => {
  if (!mayRead(userOf(c))) return c.json({ detail: "Bạn không có quyền xem đối soát." }, 403);
  try {
    const runs = await db<ReconRunRow>(c.env.DATABASE_URL)`
      SELECT id, scope, status, auto_fixed, created_at
      FROM reconciliation_runs
      ORDER BY created_at DESC
      LIMIT 50
    `;
    const out = await Promise.all(
      runs.map(async (r) => {
        const excs = await db<ReconExcRow>(c.env.DATABASE_URL)`
          SELECT subject, expected_json, actual_json
          FROM reconciliation_exceptions
          WHERE run_id = ${r.id}::uuid
        `;
        return {
          id: r.id,
          scope: r.scope,
          status: r.status,
          auto_fixed: r.auto_fixed,
          created_at: r.created_at,
          exceptions: excs.map((e) => ({
            subject: e.subject,
            expected: e.expected_json,
            actual: e.actual_json,
          })),
        };
      })
    );
    return c.json({ runs: out, next_cursor: null, limit: 50, simulation: true });
  } catch {
    return c.json({ detail: "Không thể tải dữ liệu đối soát." }, 503);
  }
});

// POST /reconciliations
reconciliationsRoutes.post("/", async (c) => {
  if (!userOf(c).caps.includes("cash:reconcile")) return c.json({ detail: "Bạn không có quyền chạy đối soát." }, 403);
  const body = await c.req.json<{ scope?: string }>().catch(() => ({ scope: "cash" }));
  const scope = (body.scope ?? "cash").toLowerCase();
  if (scope !== "cash" && scope !== "inventory") return c.json({ detail: "Phạm vi đối soát không hợp lệ." }, 422);
  const runId = crypto.randomUUID();
  try {
    const exceptions: Array<{ subject: string; expected: Record<string, unknown>; actual: Record<string, unknown> }> = [];
    if (scope === "cash") {
      const rows = await db<{ id: string; debit: string; credit: string }>(c.env.DATABASE_URL)`
        SELECT j.id, COALESCE(SUM(e.debit), 0)::text AS debit, COALESCE(SUM(e.credit), 0)::text AS credit
        FROM cash_journals j LEFT JOIN cash_entries e ON e.journal_id = j.id
        GROUP BY j.id
      `;
      for (const row of rows) {
        if (Math.abs(Number(row.debit) - Number(row.credit)) > 0.000001) {
          exceptions.push({ subject: `journal:${row.id}`, expected: { debit: row.debit, credit: row.debit }, actual: { debit: row.debit, credit: row.credit } });
        }
      }
    } else {
      const rows = await db<{ location_id: string; item_id: string; expected: string; actual: string | null }>(c.env.DATABASE_URL)`
        SELECT COALESCE(m.location_id, b.location_id) AS location_id,
               COALESCE(m.item_id, b.item_id) AS item_id,
               COALESCE(SUM(m.quantity_signed), 0)::text AS expected,
               b.quantity::text AS actual
        FROM inv_movements m FULL OUTER JOIN inv_balances b
          ON b.location_id = m.location_id AND b.item_id = m.item_id
        GROUP BY COALESCE(m.location_id, b.location_id), COALESCE(m.item_id, b.item_id), b.quantity
      `;
      for (const row of rows) {
        if (row.actual === null || Math.abs(Number(row.expected) - Number(row.actual)) > 0.000001) {
          exceptions.push({ subject: `balance:${row.location_id}:${row.item_id}`, expected: { quantity: row.expected }, actual: { quantity: row.actual } });
        }
      }
    }
    const status = exceptions.length ? "exception" : "matched";
    await db(c.env.DATABASE_URL)`
      INSERT INTO reconciliation_runs (id, scope, status, auto_fixed, created_at, updated_at)
      VALUES (${runId}::uuid, ${scope}, ${status}, false, NOW(), NOW())
    `;
    for (const exception of exceptions) {
      const id = crypto.randomUUID();
      await db(c.env.DATABASE_URL)`
        INSERT INTO reconciliation_exceptions (id, run_id, subject, expected_json, actual_json)
        VALUES (${id}::uuid, ${runId}::uuid, ${exception.subject}, ${JSON.stringify(exception.expected)}::json, ${JSON.stringify(exception.actual)}::json)
      `;
    }
    return c.json({ id: runId, scope, status, auto_fixed: false, exceptions, simulation: true }, 201);
  } catch {
    return c.json({ detail: "Không thể chạy đối soát. Vui lòng thử lại." }, 503);
  }
});
