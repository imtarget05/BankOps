"""Tea-shift regression: shift open/carry-over, receipt lot/expiry, alerts, reports."""

import uuid
from datetime import date, timedelta

import pytest

DEMO_PASSWORD = "DemoPass123!"


@pytest.fixture(scope="module")
def tea_tokens(client):
    def login(username):
        r = client.post("/auth/login", data={"username": username, "password": DEMO_PASSWORD})
        assert r.status_code == 200, f"login({username}) {r.status_code}: {r.text[:300]}"
        return r.json()["access_token"]

    return {"staff": login("staff_morning"), "manager": login("manager_demo")}


def _h(client, method, path, token=None, **kw):
    headers = dict(kw.pop("headers", {}) or {})
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if method.upper() in {"POST", "PUT", "PATCH", "DELETE"}:
        headers.setdefault("Idempotency-Key", str(uuid.uuid4()))
    return client.request(method, f"/api/v1{path}", headers=headers, **kw)


def test_shift_formula_carryover_and_duplicate_guard(client, tea_tokens):
    maker, checker = tea_tokens["staff"], tea_tokens["manager"]
    locs = _h(client, "GET", "/inventory/locations", token=maker).json()["locations"]
    loc = next((line for line in locs if line["code"] == "BAR-MAIN"), locs[0])["id"]
    items = _h(client, "GET", "/inventory/items", token=maker).json()["items"]
    assert items, "cần seed nguyên liệu trà sữa"
    item = items[0]["id"]
    base_date = date(2026, 12, 1)
    offset = int(uuid.uuid4().hex[:4], 16) % 28
    test_date = (base_date + timedelta(days=offset)).isoformat()
    while date.fromisoformat(test_date).weekday() >= 5:  # Sat/Sun
        test_date = (date.fromisoformat(test_date) + timedelta(days=1)).isoformat()

    morning = _h(client, "POST", "/inventory/stocktakes", token=maker, json={
        "location_id": loc, "shift_code": "morning", "business_date": test_date,
        "note": "Ca sáng test",
    })
    assert morning.status_code == 201, morning.text
    m = morning.json()
    assert m["shift_code"] == "morning" and m["business_date"] == test_date

    dup = _h(client, "POST", "/inventory/stocktakes", token=maker, json={
        "location_id": loc, "shift_code": "morning", "business_date": test_date,
    })
    assert dup.status_code == 409
    assert dup.json()["error"]["code"] == "SHIFT_ALREADY_OPEN"

    lines = _h(client, "GET", f"/inventory/stocktakes/{m['id']}", token=maker).json()["lines"]
    target = next(line for line in lines if line["item_id"] == item)
    opening = float(target["opening_qty"])
    upd = _h(client, "PUT", f"/inventory/stocktakes/{m['id']}/lines", token=maker, json={
        "lines": [{"item_id": item, "used_qty": "5.000", "counted_qty": str(opening - 4)}],
    })
    assert upd.status_code == 200, upd.text
    row = next(line for line in upd.json()["lines"] if line["item_id"] == item)
    # Còn lại = Tồn đầu + Nhập − Sử dụng; Lệch = Thực tế − Còn lại
    assert abs(float(row["theoretical_qty"]) - (opening - 5.0)) < 1e-6
    assert abs(float(row["variance"]) - 1.0) < 1e-6

    assert _h(client, "POST", f"/inventory/stocktakes/{m['id']}/submit", token=maker).status_code == 200
    import uuid as _uuid_mod

    appr = _h(
        client,
        "POST",
        f"/inventory/stocktakes/{m['id']}/approve",
        token=checker,
        headers={"Idempotency-Key": str(_uuid_mod.uuid4())},
    )
    assert appr.status_code == 200, appr.text

    afternoon = _h(client, "POST", "/inventory/stocktakes", token=maker, json={
        "location_id": loc, "shift_code": "afternoon", "business_date": test_date,
    })
    assert afternoon.status_code == 201, afternoon.text
    a_lines = _h(client, "GET", f"/inventory/stocktakes/{afternoon.json()['id']}", token=maker).json()["lines"]
    a_row = next(line for line in a_lines if line["item_id"] == item)
    # Tồn đầu ca chiều = kiểm thực tế ca sáng đã chốt
    assert abs(float(a_row["opening_qty"]) - (opening - 4)) < 1e-6

    locked = _h(client, "PUT", f"/inventory/stocktakes/{m['id']}/lines", token=maker, json={
        "lines": [{"item_id": item, "used_qty": "1", "counted_qty": "1"}],
    })
    assert locked.status_code == 409
    assert locked.json()["error"]["code"] == "STOCKTAKE_LOCKED"


def test_receipt_lot_expiry_validation(client, tea_tokens):
    maker = tea_tokens["staff"]
    items = _h(client, "GET", "/inventory/items", token=maker).json()["items"]
    locs = _h(client, "GET", "/inventory/locations", token=maker).json()["locations"]
    item = items[0]["id"]
    loc = next((line for line in locs if line["code"] == "BAR-MAIN"), locs[0])["id"]
    future = (date.today() + timedelta(days=30)).isoformat()
    past = (date.today() - timedelta(days=1)).isoformat()

    bad = _h(client, "POST", "/inventory/requests", token=maker, json={
        "kind": "receipt", "dest_location_id": loc, "supplier": "NCC Test",
        "lines": [{"item_id": item, "quantity": "2", "lot_no": "LOT-OLD", "expiry_date": past}],
    })
    assert bad.status_code == 422
    assert bad.json()["error"]["code"] == "EXPIRED_LOT"

    ok = _h(client, "POST", "/inventory/requests", token=maker, json={
        "kind": "receipt", "dest_location_id": loc, "supplier": "NCC Sữa Test",
        "lines": [{"item_id": item, "quantity": "5", "unit_price": "12000",
                   "lot_no": "LOT-NEW", "expiry_date": future}],
    })
    assert ok.status_code == 201, ok.text
    got = _h(client, "GET", f"/inventory/requests/{ok.json()['id']}", token=maker).json()
    line = got["lines"][0]
    assert line["lot_no"] == "LOT-NEW" and line["expiry_date"] == future
    assert float(line["unit_price"]) == 12000.0 and float(line["line_total"]) == 60000.0


def test_low_stock_alert_rule(client, tea_tokens):
    maker = tea_tokens["staff"]
    res = _h(client, "GET", "/inventory/low-stock-alerts", token=maker)
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["rule"] == "quantity <= min_qty"
    for a in body["alerts"]:
        assert float(a["quantity"]) <= float(a["min_qty"])
        assert a["severity"] == "critical"


def test_expiry_alert_and_new_reports(client, tea_tokens):
    maker = tea_tokens["staff"]
    exp = _h(client, "GET", "/inventory/expiry-alerts?days=365", token=maker)
    assert exp.status_code == 200, exp.text
    top = _h(client, "GET", "/reports/consumption-top?limit=5", token=maker)
    assert top.status_code == 200, top.text
    hist = _h(client, "GET", "/reports/shift-history", token=maker)
    assert hist.status_code == 200, hist.text
    assert "shifts" in hist.json() and "items" in top.json()
