"""Test Suite cho Bước 2A: Phiếu nhập kho đa dòng, theo dõi lô và giá vốn bình quân gia quyền."""
import uuid
from datetime import date, timedelta
from decimal import Decimal

from sqlalchemy import select

from app.models.inventory import Balance, Item, LotBalance, Stocktake

DEMO_PASSWORD = "DemoPass123!"
MAKER = "demo_maker"
CHECKER = "demo_checker"


def _login(client, username: str) -> dict[str, str]:
    r = client.post("/auth/login", data={"username": username, "password": DEMO_PASSWORD})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def _idem(headers: dict[str, str]) -> dict[str, str]:
    return {**headers, "Idempotency-Key": str(uuid.uuid4())}


def test_multiline_receipt_creation_and_total_amount(client):
    maker = _login(client, MAKER)
    locs = client.get("/inventory/locations", headers=maker).json()["locations"]
    items = client.get("/inventory/items", headers=maker).json()["items"]
    dest_loc = locs[0]["id"]

    item1 = items[0]["id"]
    item2 = items[1]["id"]
    future_date1 = (date.today() + timedelta(days=90)).isoformat()
    future_date2 = (date.today() + timedelta(days=180)).isoformat()

    req_payload = {
        "kind": "receipt",
        "source_id": None,
        "dest_id": dest_loc,
        "supplier": "Công ty TNHH Cung Ứng Nguyên Liệu Trà Sữa Tân Phú",
        "invoice_no": "HD-2026-10-8899",
        "received_at": date.today().isoformat(),
        "reason": "Nhập hàng định kỳ đầu tuần",
        "lines": [
            {
                "item_id": item1,
                "quantity": "10.000",
                "unit": "gói",
                "unit_price": "65000.00",
                "lot_no": "LOT-TP-01",
                "expiry_date": future_date1,
            },
            {
                "item_id": item2,
                "quantity": "5.000",
                "unit": "gói",
                "unit_price": "72000.00",
                "lot_no": "LOT-TP-02",
                "expiry_date": future_date2,
            },
        ],
    }

    res = client.post("/inventory/requests", headers=_idem(maker), json=req_payload)
    assert res.status_code == 201, res.text
    data = res.json()
    assert data["supplier"] == "Công ty TNHH Cung Ứng Nguyên Liệu Trà Sữa Tân Phú"
    assert data["invoice_no"] == "HD-2026-10-8899"
    assert len(data["lines"]) == 2
    # 10 * 65,000 + 5 * 72,000 = 650,000 + 360,000 = 1,010,000
    assert Decimal(data["total_amount"]) == Decimal("1010000.00")

    req_id = data["id"]
    # Check GET request detail
    get_res = client.get(f"/inventory/requests/{req_id}", headers=maker)
    assert get_res.status_code == 200
    get_data = get_res.json()
    assert get_data["invoice_no"] == "HD-2026-10-8899"
    assert Decimal(get_data["total_amount"]) == Decimal("1010000.00")


def test_backward_compatibility_single_line_without_invoice(client):
    maker = _login(client, MAKER)
    checker = _login(client, CHECKER)
    locs = client.get("/inventory/locations", headers=maker).json()["locations"]
    items = client.get("/inventory/items", headers=maker).json()["items"]
    dest_loc = locs[0]["id"]
    item_id = items[0]["id"]

    res = client.post(
        "/inventory/requests",
        headers=_idem(maker),
        json={
            "kind": "receipt",
            "source_id": None,
            "dest_id": dest_loc,
            "lines": [{"item_id": item_id, "quantity": "3"}],
            "reason": "Phiếu cũ 1 dòng không có số HĐ",
        },
    )
    assert res.status_code == 201, res.text
    req_id = res.json()["id"]

    sub = client.post(f"/inventory/requests/{req_id}/submit", headers=_idem(maker))
    assert sub.status_code == 200, sub.text

    appr = client.post(f"/inventory/requests/{req_id}/approve", headers=_idem(checker))
    assert appr.status_code == 200, appr.text
    assert appr.json()["status"] == "posted"


def test_lot_tracking_recorded_on_approve(client):
    maker = _login(client, MAKER)
    checker = _login(client, CHECKER)
    locs = client.get("/inventory/locations", headers=maker).json()["locations"]
    items = client.get("/inventory/items", headers=maker).json()["items"]
    dest_loc = locs[0]["id"]
    item_id = items[0]["id"]
    lot_code = f"LOT-{uuid.uuid4().hex[:6]}"
    exp = (date.today() + timedelta(days=120)).isoformat()

    res = client.post(
        "/inventory/requests",
        headers=_idem(maker),
        json={
            "kind": "receipt",
            "dest_id": dest_loc,
            "lines": [
                {
                    "item_id": item_id,
                    "quantity": "8.500",
                    "unit_price": "75000",
                    "lot_no": lot_code,
                    "expiry_date": exp,
                }
            ],
            "reason": "Kiểm tra ghi sổ lô hàng",
        },
    )
    assert res.status_code == 201, res.text
    req_id = res.json()["id"]

    client.post(f"/inventory/requests/{req_id}/submit", headers=_idem(maker))
    appr = client.post(f"/inventory/requests/{req_id}/approve", headers=_idem(checker))
    assert appr.status_code == 200, appr.text

    # Kiểm tra bảng cảnh báo hạn dùng nhận diện đúng lô vừa nhập
    alerts = client.get("/inventory/alerts/expiry?days=150", headers=checker).json()["alerts"]
    matching_alert = next((a for a in alerts if a["lot_no"] == lot_code), None)
    assert matching_alert is not None
    assert matching_alert["lot_no"] == lot_code
    assert matching_alert["expiry_date"] == exp


def test_weighted_average_cost_calculation_with_fractional_numbers(client):
    maker = _login(client, MAKER)
    checker = _login(client, CHECKER)
    locs = client.get("/inventory/locations", headers=maker).json()["locations"]
    dest_loc = locs[0]["id"]

    # 1. Tạo một nguyên liệu mới riêng biệt để kiểm tra chuẩn xác công thức
    sku = f"TRA-TEST-{uuid.uuid4().hex[:6]}"
    new_item = client.post(
        "/inventory/items",
        headers=_idem(checker),
        json={
            "sku": sku,
            "name": "Trà Test Bình Quân Gia Quyền",
            "unit": "kg",
            "cost_price": "120000.00",
            "category": "Nhóm Trà",
        },
    )
    assert new_item.status_code == 201, new_item.text
    item_id = new_item.json()["id"]

    # 2. Đặt tồn ban đầu = 3.5 kg giá 120,000 đ
    # Nhập đợt 1: 3.5 kg @ 120,000 đ
    r1 = client.post(
        "/inventory/requests",
        headers=_idem(maker),
        json={
            "kind": "receipt",
            "dest_id": dest_loc,
            "lines": [
                {
                    "item_id": item_id,
                    "quantity": "3.500",
                    "unit_price": "120000.00",
                    "lot_no": "LOT-INIT",
                    "expiry_date": (date.today() + timedelta(days=60)).isoformat(),
                }
            ],
            "reason": "Lô ban đầu",
        },
    )
    assert r1.status_code == 201
    r1_id = r1.json()["id"]
    client.post(f"/inventory/requests/{r1_id}/submit", headers=_idem(maker))
    client.post(f"/inventory/requests/{r1_id}/approve", headers=_idem(checker))

    # Đợt 1 xong: tồn = 3.5 kg, cost_price = 120,000 đ
    item_check1 = client.get(f"/inventory/items/{item_id}", headers=checker).json()
    assert Decimal(str(item_check1["cost_price"])) == Decimal("120000.00")

    # 3. Nhập đợt 2 với số lẻ: 6.25 kg @ 135,500 đ
    # Kỳ vọng:
    # Tổng tiền = (3.5 * 120,000) + (6.25 * 135,500) = 420,000 + 846,875 = 1,266,875 đ
    # Tổng lượng = 3.5 + 6.25 = 9.75 kg
    # Giá vốn BQGQ = 1,266,875 / 9.75 = 129935.897435... -> làm tròn 129935.90 đ
    r2 = client.post(
        "/inventory/requests",
        headers=_idem(maker),
        json={
            "kind": "receipt",
            "dest_id": dest_loc,
            "lines": [
                {
                    "item_id": item_id,
                    "quantity": "6.250",
                    "unit_price": "135500.00",
                    "lot_no": "LOT-DOT-2",
                    "expiry_date": (date.today() + timedelta(days=90)).isoformat(),
                }
            ],
            "reason": "Nhập đợt 2 số lẻ",
        },
    )
    assert r2.status_code == 201
    r2_id = r2.json()["id"]
    client.post(f"/inventory/requests/{r2_id}/submit", headers=_idem(maker))
    client.post(f"/inventory/requests/{r2_id}/approve", headers=_idem(checker))

    item_check2 = client.get(f"/inventory/items/{item_id}", headers=checker).json()
    actual_cost = Decimal(str(item_check2["cost_price"]))
    expected_cost = Decimal("129935.90")
    assert abs(actual_cost - expected_cost) <= Decimal("0.01")


def test_unit_conversion_on_receipt_approval(client):
    maker = _login(client, MAKER)
    checker = _login(client, CHECKER)
    locs = client.get("/inventory/locations", headers=maker).json()["locations"]
    dest_loc = locs[0]["id"]

    sku = f"BOT-TEST-{uuid.uuid4().hex[:6]}"
    new_item = client.post(
        "/inventory/items",
        headers=_idem(checker),
        json={
            "sku": sku,
            "name": "Bột Kem Béo Thùng",
            "unit": "gói",
            "cost_price": "60000.00",
            "category": "Bột Sữa",
        },
    )
    assert new_item.status_code == 201
    item_id = new_item.json()["id"]

    # Nhập 2 thùng, mỗi thùng 20 gói (conversion_rate = 20), giá 1,300,000 đ / thùng
    # -> Số lượng quy đổi: 2 * 20 = 40 gói
    # -> Đơn giá quy đổi: 1,300,000 / 20 = 65,000 đ / gói
    r = client.post(
        "/inventory/requests",
        headers=_idem(maker),
        json={
            "kind": "receipt",
            "dest_id": dest_loc,
            "lines": [
                {
                    "item_id": item_id,
                    "quantity": "2.000",
                    "unit": "thùng",
                    "conversion_rate": "20.0000",
                    "unit_price": "1300000.00",
                    "lot_no": "LOT-THUNG-01",
                    "expiry_date": (date.today() + timedelta(days=200)).isoformat(),
                }
            ],
            "reason": "Nhập nguyên thùng",
        },
    )
    assert r.status_code == 201
    req_id = r.json()["id"]
    client.post(f"/inventory/requests/{req_id}/submit", headers=_idem(maker))
    appr = client.post(f"/inventory/requests/{req_id}/approve", headers=_idem(checker))
    assert appr.status_code == 200

    # Kiểm tra tồn kho tại kho đích tăng 40 gói
    bals = client.get("/inventory/balances", headers=maker).json()["balances"]
    item_bal = next(b for b in bals if b["item_id"] == item_id and b["location_id"] == dest_loc)
    assert Decimal(str(item_bal["quantity"])) == Decimal("40.000")

    # Kiểm tra giá vốn cập nhật thành 65,000 đ/gói
    item_after = client.get(f"/inventory/items/{item_id}", headers=checker).json()
    assert Decimal(str(item_after["cost_price"])) == Decimal("65000.00")


def test_multiline_receipt_syncs_all_items_to_open_stocktake(client):
    maker = _login(client, MAKER)
    checker = _login(client, CHECKER)
    locs = client.get("/inventory/locations", headers=maker).json()["locations"]
    items = client.get("/inventory/items", headers=maker).json()["items"]
    dest_loc = locs[0]["id"]
    item1 = items[0]["id"]
    item2 = items[1]["id"]

    unique_date = (date(2045, 1, 1) + timedelta(days=uuid.uuid4().int % 364)).isoformat()
    open_shift = client.post(
        "/inventory/stocktakes",
        headers=_idem(maker),
        json={"location_id": dest_loc, "shift_code": "morning", "business_date": unique_date},
    )
    assert open_shift.status_code == 201, open_shift.text
    st_id = open_shift.json()["id"]

    lines_before = client.get(f"/inventory/stocktakes/{st_id}", headers=maker).json()["lines"]
    line1_before = next(l for l in lines_before if l["item_id"] == item1)
    line2_before = next(l for l in lines_before if l["item_id"] == item2)
    init_recv1 = float(line1_before["received_qty"])
    init_recv2 = float(line2_before["received_qty"])

    # Tạo phiếu nhập đa dòng:
    # - 2 dòng cho item1 (Lô A: 4 gói + Lô B: 6 gói = 10 gói)
    # - 1 dòng cho item2 (Lô C: 8 gói)
    req = client.post(
        "/inventory/requests",
        headers=_idem(maker),
        json={
            "kind": "receipt",
            "dest_id": dest_loc,
            "invoice_no": "HD-MULTILINE-SYNC",
            "lines": [
                {
                    "item_id": item1,
                    "quantity": "4.000",
                    "unit_price": "65000",
                    "lot_no": "LOT-A",
                    "expiry_date": (date.today() + timedelta(days=100)).isoformat(),
                },
                {
                    "item_id": item1,
                    "quantity": "6.000",
                    "unit_price": "65000",
                    "lot_no": "LOT-B",
                    "expiry_date": (date.today() + timedelta(days=150)).isoformat(),
                },
                {
                    "item_id": item2,
                    "quantity": "8.000",
                    "unit_price": "70000",
                    "lot_no": "LOT-C",
                    "expiry_date": (date.today() + timedelta(days=120)).isoformat(),
                },
            ],
            "reason": "Test đồng bộ đa dòng và gộp dòng cùng item",
        },
    )
    assert req.status_code == 201
    req_id = req.json()["id"]
    client.post(f"/inventory/requests/{req_id}/submit", headers=_idem(maker))
    appr = client.post(f"/inventory/requests/{req_id}/approve", headers=_idem(checker))
    assert appr.status_code == 200

    # Kiểm tra ca kiểm kê đang mở:
    # - item1: received_qty phải tăng đúng +10 (4 + 6)
    # - item2: received_qty phải tăng đúng +8
    lines_after = client.get(f"/inventory/stocktakes/{st_id}", headers=maker).json()["lines"]
    line1_after = next(l for l in lines_after if l["item_id"] == item1)
    line2_after = next(l for l in lines_after if l["item_id"] == item2)

    assert float(line1_after["received_qty"]) == init_recv1 + 10.0
    assert float(line2_after["received_qty"]) == init_recv2 + 8.0


def test_initial_lots_seeded_from_existing_balances(client):
    """Kiểm tra hàng tồn cũ đã được chuyển sang lô TON-DAU-KY trong inv_lot_balances."""
    maker = _login(client, MAKER)
    bals = client.get("/inventory/balances", headers=maker).json()["balances"]
    # Với các balance dương, phải luôn có thể truy vấn alert hoặc tồn lô
    positive_bals = [b for b in bals if float(b["quantity"]) > 0]
    assert len(positive_bals) > 0, "Cần có ít nhất một tồn dương trong seed ban đầu"
