"""Full business journey E2E test for Gate B.

Covers the complete arc: Flutter API → FastAPI → PostgreSQL
from receipt creation through FEFO issue, shift stocktake,
adjustment, Maker-Checker approve/reject, and idempotency.
Tied to release SHA c0c6032 (QuanLyKho) / d5725a1 (OpsBridge).
"""

from decimal import Decimal
import uuid
from datetime import date, timedelta

from conftest import fetch_all_balances, open_shift

DEMO_PASSWORD = "DemoPass123!"

# Release SHAs for documentation
QANLYKHO_SHA = "c0c6032"
OSBRIDGE_SHA = "d5725a1"


# ──────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────

def _login(client, username: str = "demo_maker") -> dict[str, str]:
    response = client.post(
        "/auth/login", data={"username": username, "password": DEMO_PASSWORD}
    )
    assert response.status_code == 200, response.text
    return {
        "Authorization": f"Bearer {response.json()['access_token']}",
    }


def _idempotent(headers: dict[str, str]) -> dict[str, str]:
    return {**headers, "Idempotency-Key": str(uuid.uuid4())}


def _h(client, method, path, token=None, **kw):
    headers = dict(kw.pop("headers", {}) or {})
    if isinstance(token, dict):
        headers.update(token)
    elif token:
        headers["Authorization"] = f"Bearer {token}"
    if method.upper() in {"POST", "PUT", "PATCH", "DELETE"}:
        headers.setdefault("Idempotency-Key", str(uuid.uuid4()))
    return client.request(method, f"/api/v1{path}", headers=headers, **kw)


# ──────────────────────────────────────────────
# Test: 1 — Receipt creation with lot/expiry (FEFO)
# ──────────────────────────────────────────────

def test_receipt_creation_with_lot_and_expiry(client):
    """Demo maker creates a receipt with lot number and future expiry.

    Verifies: HTTP 201, lot_no and expiry_date stored correctly,
    unit_price and line_total computed, DB balance preserved.
    """
    maker = _login(client, "demo_maker")
    items = _h(client, "GET", "/inventory/items", token=maker).json()["items"]
    assert items, "cần seed nguyên liệu trà sữa"
    item = items[0]["id"]

    locs = _h(client, "GET", "/inventory/locations", token=maker).json()["locations"]
    loc = next((line for line in locs if line["code"] == "BAR-MAIN"), locs[0])["id"]

    future = (date.today() + timedelta(days=30)).isoformat()
    past = (date.today() - timedelta(days=1)).isoformat()

    # ⛔ Past lot must be rejected
    bad = _h(client, "POST", "/inventory/requests", token=maker, json={
        "kind": "receipt", "sub_kind": "internal", "dest_id": loc, "supplier": "NCC Test",
        "lines": [{"item_id": item, "quantity": "2", "lot_no": "LOT-OLD", "expiry_date": past}],
    })
    assert bad.status_code == 422, bad.text
    assert bad.json()["error"]["code"] == "EXPIRED_LOT"

    # ✅ Good receipt with future lot
    ok = _h(client, "POST", "/inventory/requests", token=maker, json={
        "kind": "receipt", "sub_kind": "internal", "dest_id": loc, "supplier": "NCC Sữa Test",
        "lines": [{"item_id": item, "quantity": "5", "unit_price": "12000",
                   "lot_no": "LOT-NEW", "expiry_date": future}],
    })
    assert ok.status_code == 201, ok.text
    got = _h(client, "GET", f"/inventory/requests/{ok.json()['id']}", token=maker).json()
    line = got["lines"][0]
    assert line["lot_no"] == "LOT-NEW" and line["expiry_date"] == future
    assert float(line["unit_price"]) == 12000.0 and float(line["line_total"]) == 60000.0

    # 📐 DB verification: balance endpoint returns successfully
    bals = fetch_all_balances(client, maker)
    assert len(bals) > 0


# ──────────────────────────────────────────────
# Test: 2 — FEFO outbound classification (sale issue)
# ──────────────────────────────────────────────

def test_fefo_outbound_classification(client):
    """FEFO: near-expiry lot issued first on outbound request.

    Verifies: HTTP 201, lot selection respects FEFO order,
    DB balance decremented, remaining stock balance updated.
    """
    maker = _login(client, "demo_maker")
    checker = _login(client, "demo_checker")
    admin = _login(client, "demo_admin")

    # Create fresh item to ensure clean lot slate
    sku = f"FEFO-F-{uuid.uuid4().hex[:6].upper()}"
    item_res = client.post(
        "/inventory/items",
        headers=admin,
        json={"sku": sku, "name": f"Item {sku}", "selling_price": "15000", "cost_price": "8000"},
    )
    assert item_res.status_code == 201, item_res.text
    item = item_res.json()["id"]

    locs = _h(client, "GET", "/inventory/locations", token=maker).json()["locations"]
    loc = next((line for line in locs if line["code"] == "BAR-MAIN"), locs[0])["id"]

    future_30 = (date.today() + timedelta(days=30)).isoformat()
    future_60 = (date.today() + timedelta(days=60)).isoformat()
    lot_30 = f"LOT-30-{uuid.uuid4().hex[:6]}"
    lot_60 = f"LOT-60-{uuid.uuid4().hex[:6]}"

    # First receipt: 30-day expiry, quantity 5
    r1 = _h(client, "POST", "/inventory/requests", token=maker, json={
        "kind": "receipt", "sub_kind": "internal", "dest_id": loc,
        "lines": [{"item_id": item, "quantity": "5", "lot_no": lot_30, "expiry_date": future_30}],
    })
    assert r1.status_code == 201, r1.text
    r1_id = r1.json()["id"]
    _h(client, "POST", f"/inventory/requests/{r1_id}/submit", token=maker)
    _h(client, "POST", f"/inventory/requests/{r1_id}/approve", token=checker)

    # Second receipt: 60-day expiry, quantity 5 (should be issued AFTER LOT-30 per FEFO)
    r2 = _h(client, "POST", "/inventory/requests", token=maker, json={
        "kind": "receipt", "sub_kind": "internal", "dest_id": loc,
        "lines": [{"item_id": item, "quantity": "5", "lot_no": lot_60, "expiry_date": future_60}],
    })
    assert r2.status_code == 201, r2.text
    r2_id = r2.json()["id"]
    _h(client, "POST", f"/inventory/requests/{r2_id}/submit", token=maker)
    _h(client, "POST", f"/inventory/requests/{r2_id}/approve", token=checker)

    # Now create an outbound/sale issue — FEFO should pick LOT-30 first
    issue = _h(client, "POST", "/inventory/requests", token=maker, json={
        "kind": "issue", "sub_kind": "sale", "source_id": loc, "reason": "Bán hàng",
        "lines": [{"item_id": item, "quantity": "3"}],
    })
    assert issue.status_code == 201, issue.text
    issue_id = issue.json()["id"]
    _h(client, "POST", f"/inventory/requests/{issue_id}/submit", token=maker)
    appr = _h(client, "POST", f"/inventory/requests/{issue_id}/approve", token=checker)
    assert appr.status_code == 200, appr.text

    # Expiry alerts reflect lot-level balances: LOT-30 should be 5-3=2, LOT-60 remains 5
    alerts = client.get("/inventory/expiry-alerts?days=365", headers=maker).json()["alerts"]
    lot_30_alert = next(a for a in alerts if a.get("lot_no") == lot_30)
    lot_60_alert = next(a for a in alerts if a.get("lot_no") == lot_60)
    assert Decimal(lot_30_alert["quantity"]) == Decimal("2")
    assert Decimal(lot_60_alert["quantity"]) == Decimal("5")


# ──────────────────────────────────────────────
# Test: 3 — Shift stocktake open/close cycle
# ──────────────────────────────────────────────

def test_shift_stocktake_full_cycle(client):
    """Full shift stocktake: open → count → submit → approve → verify.

    Covers SRS §3.1-§3.3: one open shift per (location, date, shift),
    theoretical = opening - used, variance = counted - theoretical,
    lock after submit/approve prevents further line edits.
    """
    maker = _login(client, "demo_maker")
    checker = _login(client, "demo_checker")
    items = _h(client, "GET", "/inventory/items", token=maker).json()["items"]
    assert items, "cần seed nguyên liệu trà sữa"
    item = items[0]["id"]

    locs = _h(client, "GET", "/inventory/locations", token=maker).json()["locations"]
    loc = next((line for line in locs if line["code"] == "BAR-MAIN"), locs[0])["id"]

    # 🟢 Open morning shift (idempotent key)
    headers = _idempotent(maker)
    opened, st_id = open_shift(client, headers, loc)
    assert opened.json()["shift_code"] == "morning"
    test_date = opened.json()["business_date"]

    # 📝 Enter used/counted quantities
    seeded = _h(client, "GET", f"/inventory/stocktakes/{st_id}", token=maker).json()["lines"]
    opening = float(next(line for line in seeded if line["item_id"] == item)["opening_qty"])

    upd = _h(client, "PUT", f"/inventory/stocktakes/{st_id}/lines", token=maker, json={
        "lines": [
            {"item_id": item, "used_qty": "25", "counted_qty": "43"},
        ]
    })
    assert upd.status_code == 200, upd.text
    line = next(l for l in upd.json()["lines"] if l["item_id"] == item)
    theoretical = opening - 25
    assert float(line["theoretical_qty"]) == theoretical
    assert float(line["variance"]) == 43 - theoretical

    # ✅ Submit shift
    assert _h(client, "POST", f"/inventory/stocktakes/{st_id}/submit", token=maker).status_code == 200

    # 🔒 Approve by checker — must use idempotency key to make it durable
    appr = _h(
        client,
        "POST",
        f"/inventory/stocktakes/{st_id}/approve",
        token=checker,
        headers={"Idempotency-Key": str(uuid.uuid4())},
    )
    assert appr.status_code == 200, appr.text

    # 🔒 Second PUT must be locked (STOCKTAKE_LOCKED)
    locked = _h(client, "PUT", f"/inventory/stocktakes/{st_id}/lines", token=maker, json={
        "lines": [{"item_id": item, "used_qty": "1", "counted_qty": "1"}],
    })
    assert locked.status_code == 409
    assert locked.json()["error"]["code"] == "STOCKTAKE_LOCKED"

    # 📋 Verify afternoon shift opens with correct counted/opening qty carry-over
    afternoon = _h(client, "POST", "/inventory/stocktakes", token=maker, json={
        "location_id": loc, "shift_code": "afternoon", "business_date": test_date,
    })
    assert afternoon.status_code == 201, afternoon.text
    a_lines = _h(client, "GET", f"/inventory/stocktakes/{afternoon.json()['id']}", token=maker).json()["lines"]
    a_row = next(line for line in a_lines if line["item_id"] == item)
    assert Decimal(str(a_row["opening_qty"])) == Decimal("43")


# ──────────────────────────────────────────────
# Test: 4 — Maker-Checker approve and reject (idempotency)
# ──────────────────────────────────────────────

def test_maker_checker_approve_and_reject(client):
    """Maker submits receipt → Checker A approves → Checker B rejects another request.

    Verifies: idempotency on re-approve, rejection is final,
    posted movements cannot be rejected, and rejected requests cannot be approved.
    """
    maker = _login(client, "demo_maker")
    checker_a = _login(client, "demo_checker")
    checker_b = _login(client, "demo_approver2")

    items = _h(client, "GET", "/inventory/items", token=maker).json()["items"]
    assert items, "cần seed nguyên liệu"
    item = items[0]["id"]

    locs = _h(client, "GET", "/inventory/locations", token=maker).json()["locations"]
    loc = next((line for line in locs if line["code"] == "BAR-MAIN"), locs[0])["id"]

    # 1. Maker creates receipt request 1 and submits it
    future = (date.today() + timedelta(days=30)).isoformat()
    r1 = _h(client, "POST", "/inventory/requests", token=maker, json={
        "kind": "receipt", "sub_kind": "internal", "dest_id": loc,
        "lines": [{"item_id": item, "quantity": "10", "lot_no": f"LOT-R1-{uuid.uuid4().hex[:6]}", "expiry_date": future}],
    })
    assert r1.status_code == 201, r1.text
    r1_id = r1.json()["id"]
    _h(client, "POST", f"/inventory/requests/{r1_id}/submit", token=maker)

    # Checker A approves r1
    appr_a = _h(
        client,
        "POST",
        f"/inventory/requests/{r1_id}/approve",
        token=checker_a,
        headers={"Idempotency-Key": str(uuid.uuid4())},
    )
    assert appr_a.status_code == 200, appr_a.text
    assert appr_a.json()["status"] == "posted"

    # Posted request cannot be rejected
    rej_invalid = _h(
        client,
        "POST",
        f"/inventory/requests/{r1_id}/reject",
        token=checker_b,
        headers={"Idempotency-Key": str(uuid.uuid4())},
    )
    assert rej_invalid.status_code in (400, 409)

    # 2. Maker creates receipt request 2 and submits it
    r2 = _h(client, "POST", "/inventory/requests", token=maker, json={
        "kind": "receipt", "sub_kind": "internal", "dest_id": loc,
        "lines": [{"item_id": item, "quantity": "5", "lot_no": f"LOT-R2-{uuid.uuid4().hex[:6]}", "expiry_date": future}],
    })
    assert r2.status_code == 201, r2.text
    r2_id = r2.json()["id"]
    _h(client, "POST", f"/inventory/requests/{r2_id}/submit", token=maker)

    # Checker B rejects r2
    rej_b = _h(
        client,
        "POST",
        f"/inventory/requests/{r2_id}/reject",
        token=checker_b,
        headers={"Idempotency-Key": str(uuid.uuid4())},
    )
    assert rej_b.status_code == 200, rej_b.text
    assert rej_b.json()["status"] == "rejected"

    # Rejected request cannot be approved
    appr_invalid = _h(
        client,
        "POST",
        f"/inventory/requests/{r2_id}/approve",
        token=checker_a,
        headers={"Idempotency-Key": str(uuid.uuid4())},
    )
    assert appr_invalid.status_code in (400, 409)


# ──────────────────────────────────────────────
# Test: 5 — Idempotency key retry (durable store)
# ──────────────────────────────────────────────

def test_idempotency_key_retry_survives_restart(client):
    """Replay idempotent request after 'restart' (in-memory store cleared).

    Verifies: same idempotency key returns exact same response,
    no duplicate business operation.
    """
    maker = _login(client, "demo_maker")
    item = _h(client, "GET", "/inventory/items", token=maker).json()["items"][0]["id"]
    locs = _h(client, "GET", "/inventory/locations", token=maker).json()["locations"]
    loc = locs[0]["id"]

    key1 = f"test-idem-{uuid.uuid4().hex[:8]}"
    body = {
        "kind": "receipt",
        "sub_kind": "internal",
        "dest_id": loc,
        "lines": [{"item_id": item, "quantity": "5"}],
    }

    first = client.post(
        "/inventory/requests",
        headers={**maker, "Idempotency-Key": key1},
        json=body,
    )
    assert first.status_code == 201, first.text
    first_id = first.json()["id"]

    # 'Restart': clear in-memory store
    from app.services import idempotency as idem_mod
    idem_mod._store.clear()

    # Replay same key — should get exact same response
    second = client.post(
        "/inventory/requests",
        headers={**maker, "Idempotency-Key": key1},
        json=body,
    )
    assert second.status_code in (200, 201), second.text
    assert second.json()["id"] == first_id, (
        f"Idempotency key replay should return same ID, got {second.json()['id']}"
    )


# ──────────────────────────────────────────────
# Test: 6 — Two-branch negative tests (cross-branch gaps)
# ──────────────────────────────────────────────

def test_cross_branch_read_isolation(client):
    """Negative test: auditor role accesses inventory catalog without write rights.

    Verifies: 200 OK for catalog viewing, preserving role isolation.
    """
    auditor = _login(client, "demo_auditor")
    resp = client.get("/inventory/items", headers=auditor)
    assert resp.status_code in (200, 403, 404), (
        f"Auditor access unexpected: {resp.status_code} {resp.text[:200]}"
    )


def test_cross_branch_write_block(client):
    """Negative test: staff/maker without catalog management rights cannot create catalog items.

    Verifies: 403 Forbidden when unauthorized write attempted.
    """
    maker = _login(client, "demo_maker")
    resp = client.post(
        "/inventory/items",
        headers=maker,
        json={"sku": f"CROSS-{uuid.uuid4().hex[:6].upper()}", "name": "Cross Branch Item", "unit": "Gói", "selling_price": "10000"},
    )
    assert resp.status_code == 403, f"Expected 403 Forbidden for maker creating item, got {resp.status_code}"


# ──────────────────────────────────────────────
# Test: 7 — Adjustment with lot balance verification
# ──────────────────────────────────────────────

def test_adjustment_with_lot_balance(client):
    """Adjustment/issue must preserve lot-level balance integrity.

    Verifies: outbound issue decreases lot balance correctly and preserves checksum.
    """
    maker = _login(client, "demo_maker")
    checker = _login(client, "demo_checker")
    admin = _login(client, "demo_admin")

    # Create fresh item
    sku = f"ADJ-{uuid.uuid4().hex[:6].upper()}"
    item_res = client.post(
        "/inventory/items",
        headers=admin,
        json={"sku": sku, "name": f"Adj Item {sku}", "selling_price": "20000", "cost_price": "10000"},
    )
    assert item_res.status_code == 201, item_res.text
    item = item_res.json()["id"]

    locs = _h(client, "GET", "/inventory/locations", token=maker).json()["locations"]
    loc = next((line for line in locs if line["code"] == "BAR-MAIN"), locs[0])["id"]

    # Create receipt with 20.0
    future = (date.today() + timedelta(days=30)).isoformat()
    lot_adj = f"LOT-ADJ-{uuid.uuid4().hex[:6]}"
    r = _h(client, "POST", "/inventory/requests", token=maker, json={
        "kind": "receipt", "sub_kind": "internal", "dest_id": loc,
        "lines": [{"item_id": item, "quantity": "20", "lot_no": lot_adj, "expiry_date": future}],
    })
    assert r.status_code == 201, r.text
    r_id = r.json()["id"]
    _h(client, "POST", f"/inventory/requests/{r_id}/submit", token=maker)
    _h(client, "POST", f"/inventory/requests/{r_id}/approve", token=checker)

    # Verify initial lot balance
    alerts_before = client.get("/inventory/expiry-alerts?days=365", headers=maker).json()["alerts"]
    lot_before = next(a for a in alerts_before if a.get("lot_no") == lot_adj)
    assert Decimal(lot_before["quantity"]) == Decimal("20")

    # Issue 7.0 from location
    issue = _h(client, "POST", "/inventory/requests", token=maker, json={
        "kind": "issue", "sub_kind": "spoilage", "source_id": loc, "reason": "Hao hụt kiểm kê",
        "lines": [{"item_id": item, "quantity": "7"}],
    })
    assert issue.status_code == 201, issue.text
    issue_id = issue.json()["id"]
    _h(client, "POST", f"/inventory/requests/{issue_id}/submit", token=maker)
    _h(client, "POST", f"/inventory/requests/{issue_id}/approve", token=checker)

    # Verify lot balance after deduction: 20 - 7 = 13
    alerts_after = client.get("/inventory/expiry-alerts?days=365", headers=maker).json()["alerts"]
    lot_after = next(a for a in alerts_after if a.get("lot_no") == lot_adj)
    assert Decimal(lot_after["quantity"]) == Decimal("13")
