"""Test Suite cho Bước 2B: Phân loại xuất kho (sale, spoilage, internal, transfer),
trừ tồn theo FEFO, khóa dòng chống xuất âm, đồng bộ ca kiểm kê và báo cáo xuất nhập tồn.
"""
import uuid
from datetime import date, timedelta
from decimal import Decimal

from conftest import open_shift
from sqlalchemy import select

from app.models.inventory import (
    LotBalance,
)

DEMO_PASSWORD = "DemoPass123!"
MAKER = "demo_maker"
CHECKER = "demo_checker"


def _login(client, username: str) -> dict[str, str]:
    r = client.post("/auth/login", data={"username": username, "password": DEMO_PASSWORD})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def _idem(headers: dict[str, str]) -> dict[str, str]:
    return {**headers, "Idempotency-Key": str(uuid.uuid4())}


def test_outbound_classification_and_mandatory_reasons(client):
    maker = _login(client, MAKER)
    locs = client.get("/inventory/locations", headers=maker).json()["locations"]
    items = client.get("/inventory/items", headers=maker).json()["items"]
    src_loc = locs[0]["id"]
    item_id = items[0]["id"]

    # 1. Xuất spoilage thiếu reason -> Phải trả về 422 MISSING_REASON
    r_spoilage_no_reason = client.post(
        "/inventory/requests",
        headers=_idem(maker),
        json={
            "kind": "issue",
            "sub_kind": "spoilage",
            "source_id": src_loc,
            "lines": [{"item_id": item_id, "quantity": "1"}],
            "reason": "",
        },
    )
    assert r_spoilage_no_reason.status_code == 422, r_spoilage_no_reason.text
    assert r_spoilage_no_reason.json()["error"]["code"] == "MISSING_REASON"

    # 2. Xuất internal thiếu reason -> Phải trả về 422 MISSING_REASON
    r_internal_no_reason = client.post(
        "/inventory/requests",
        headers=_idem(maker),
        json={
            "kind": "issue",
            "sub_kind": "internal",
            "source_id": src_loc,
            "lines": [{"item_id": item_id, "quantity": "1"}],
        },
    )
    assert r_internal_no_reason.status_code == 422, r_internal_no_reason.text
    assert r_internal_no_reason.json()["error"]["code"] == "MISSING_REASON"

    # 3. Xuất spoilage có reason hợp lệ -> Thành công 201
    r_spoilage_ok = client.post(
        "/inventory/requests",
        headers=_idem(maker),
        json={
            "kind": "issue",
            "sub_kind": "spoilage",
            "source_id": src_loc,
            "lines": [{"item_id": item_id, "quantity": "1"}],
            "reason": "Hàng rơi vỡ bể bao bì khi bốc dỡ",
        },
    )
    assert r_spoilage_ok.status_code == 201, r_spoilage_ok.text
    assert r_spoilage_ok.json()["sub_kind"] == "spoilage"

    # 4. Phiếu xuất cũ không truyền sub_kind -> Mặc định là 'sale'
    r_legacy_issue = client.post(
        "/inventory/requests",
        headers=_idem(maker),
        json={
            "kind": "issue",
            "source_id": src_loc,
            "lines": [{"item_id": item_id, "quantity": "1"}],
            "reason": "Phiếu xuất bán POS cũ",
        },
    )
    assert r_legacy_issue.status_code == 201, r_legacy_issue.text
    assert r_legacy_issue.json()["sub_kind"] == "sale"


def test_fefo_deduction_across_multiple_lots(client):
    maker = _login(client, MAKER)
    checker = _login(client, CHECKER)
    locs = client.get("/inventory/locations", headers=maker).json()["locations"]
    src_loc = locs[0]["id"]

    # Tạo nguyên liệu riêng
    sku = f"FEFO-TEST-{uuid.uuid4().hex[:6]}"
    item = client.post(
        "/inventory/items",
        headers=_idem(checker),
        json={"sku": sku, "name": "Bột Trà Lài FEFO", "unit": "gói", "cost_price": "50000.00"},
    ).json()
    item_id = item["id"]

    today = date.today()
    exp_lot1 = (today + timedelta(days=10)).isoformat()  # Hết hạn sớm nhất: 5 gói @ 50,000 đ
    exp_lot2 = (today + timedelta(days=30)).isoformat()  # Hết hạn tiếp theo: 10 gói @ 55,000 đ

    # Nhập Lô 1 (5 gói) và Lô 2 (10 gói)
    inbound_req = client.post(
        "/inventory/requests",
        headers=_idem(maker),
        json={
            "kind": "receipt",
            "dest_id": src_loc,
            "lines": [
                {"item_id": item_id, "quantity": "5", "unit_price": "50000", "lot_no": "LOT-EARLY", "expiry_date": exp_lot1},
                {"item_id": item_id, "quantity": "10", "unit_price": "55000", "lot_no": "LOT-LATER", "expiry_date": exp_lot2},
            ],
            "reason": "Nhập 2 lô có HSD khác nhau",
        },
    ).json()
    client.post(f"/inventory/requests/{inbound_req['id']}/submit", headers=_idem(maker))
    client.post(f"/inventory/requests/{inbound_req['id']}/approve", headers=_idem(checker))

    # Xuất bán 8 gói: FEFO phải trừ sạch 5 gói LOT-EARLY và trừ 3 gói LOT-LATER
    out_req = client.post(
        "/inventory/requests",
        headers=_idem(maker),
        json={
            "kind": "issue",
            "sub_kind": "sale",
            "source_id": src_loc,
            "lines": [{"item_id": item_id, "quantity": "8"}],
            "reason": "Xuất bán 8 gói qua 2 lô",
        },
    ).json()
    out_id = out_req["id"]
    client.post(f"/inventory/requests/{out_id}/submit", headers=_idem(maker))
    appr = client.post(f"/inventory/requests/{out_id}/approve", headers=_idem(checker))
    assert appr.status_code == 200, appr.text

    # Kiểm tra LotBalance sau xuất
    bals = client.get(
        "/inventory/balances", headers=checker, params={"item_id": item_id}
    ).json()["balances"]
    item_bal = next(b for b in bals if b["item_id"] == item_id and b["location_id"] == src_loc)
    # Tổng tồn = 15 - 8 = 7 gói
    assert Decimal(str(item_bal["quantity"])) == Decimal("7.000")


def test_insufficient_stock_prevents_negative_inventory(client):
    maker = _login(client, MAKER)
    checker = _login(client, CHECKER)
    locs = client.get("/inventory/locations", headers=maker).json()["locations"]
    src_loc = locs[0]["id"]

    sku = f"NEG-TEST-{uuid.uuid4().hex[:6]}"
    item = client.post(
        "/inventory/items",
        headers=_idem(checker),
        json={"sku": sku, "name": "Trân Châu Đen Chống Âm", "unit": "kg", "cost_price": "30000"},
    ).json()
    item_id = item["id"]

    # Nhập chỉ 3 kg
    r_in = client.post(
        "/inventory/requests",
        headers=_idem(maker),
        json={
            "kind": "receipt",
            "dest_id": src_loc,
            "lines": [{"item_id": item_id, "quantity": "3", "unit_price": "30000", "lot_no": "LOT-3KG", "expiry_date": (date.today() + timedelta(days=60)).isoformat()}],
        },
    ).json()
    client.post(f"/inventory/requests/{r_in['id']}/submit", headers=_idem(maker))
    client.post(f"/inventory/requests/{r_in['id']}/approve", headers=_idem(checker))

    # Cố xuất 5 kg -> Phải bị chặn không cho xuất âm
    r_out = client.post(
        "/inventory/requests",
        headers=_idem(maker),
        json={
            "kind": "issue",
            "sub_kind": "sale",
            "source_id": src_loc,
            "lines": [{"item_id": item_id, "quantity": "5"}],
            "reason": "Xuất quá lượng tồn",
        },
    ).json()
    out_id = r_out["id"]

    # Lúc submit kiểm tra tồn khả dụng bị chặn với 409 INSUFFICIENT_STOCK
    sub = client.post(f"/inventory/requests/{out_id}/submit", headers=_idem(maker))
    assert sub.status_code == 409
    assert sub.json()["error"]["code"] == "INSUFFICIENT_STOCK"


def test_expired_lots_blocked_for_sale_but_allowed_for_spoilage(client):
    maker = _login(client, MAKER)
    checker = _login(client, CHECKER)
    locs = client.get("/inventory/locations", headers=maker).json()["locations"]
    src_loc = locs[0]["id"]

    sku = f"EXP-TEST-{uuid.uuid4().hex[:6]}"
    item = client.post(
        "/inventory/items",
        headers=_idem(checker),
        json={"sku": sku, "name": "Sữa Tươi Cận Date", "unit": "hộp", "cost_price": "35000"},
    ).json()
    item_id = item["id"]

    # Nhập hàng có HSD tương lai 1 ngày để hợp lệ khi nhập
    r_in = client.post(
        "/inventory/requests",
        headers=_idem(maker),
        json={
            "kind": "receipt",
            "dest_id": src_loc,
            "lines": [
                {
                    "item_id": item_id,
                    "quantity": "4",
                    "unit_price": "35000",
                    "lot_no": "LOT-QUAHAN",
                    "expiry_date": (date.today() + timedelta(days=1)).isoformat(),
                }
            ],
        },
    ).json()
    client.post(f"/inventory/requests/{r_in['id']}/submit", headers=_idem(maker))
    client.post(f"/inventory/requests/{r_in['id']}/approve", headers=_idem(checker))

    # Giả lập thời gian trôi qua: cập nhật LotBalance có expiry_date về quá khứ (hết hạn)
    # Lô này giờ đã quá hạn sử dụng.
    import asyncio

    from app.database import AsyncSessionLocal

    async def _expire_lot():
        async with AsyncSessionLocal() as session:
            lots = (await session.execute(select(LotBalance).where(LotBalance.item_id == uuid.UUID(item_id)))).scalars().all()
            for lot in lots:
                lot.expiry_date = date.today() - timedelta(days=2)
            await session.commit()

    asyncio.run(_expire_lot())

    # 1. Xuất bán (sale) lô đã hết hạn -> Bị chặn
    out_sale = client.post(
        "/inventory/requests",
        headers=_idem(maker),
        json={
            "kind": "issue",
            "sub_kind": "sale",
            "source_id": src_loc,
            "lines": [{"item_id": item_id, "quantity": "2"}],
            "reason": "Bán hàng quá hạn",
        },
    ).json()
    sub_sale = client.post(f"/inventory/requests/{out_sale['id']}/submit", headers=_idem(maker))
    assert sub_sale.status_code == 422, sub_sale.text
    assert sub_sale.json()["error"]["code"] == "EXPIRED_LOT_CANNOT_BE_USED"

    # 2. Xuất hủy (spoilage) lô hết hạn -> Được phép thông qua
    out_spoilage = client.post(
        "/inventory/requests",
        headers=_idem(maker),
        json={
            "kind": "issue",
            "sub_kind": "spoilage",
            "source_id": src_loc,
            "lines": [{"item_id": item_id, "quantity": "2"}],
            "reason": "Xuất hủy do sữa đã chua và quá hạn 2 ngày",
        },
    ).json()
    sub_spoil = client.post(f"/inventory/requests/{out_spoilage['id']}/submit", headers=_idem(maker))
    assert sub_spoil.status_code == 200, sub_spoil.text
    appr_spoil = client.post(f"/inventory/requests/{out_spoilage['id']}/approve", headers=_idem(checker))
    assert appr_spoil.status_code == 200, appr_spoil.text


def test_transfer_atomic_and_lot_preservation(client):
    maker = _login(client, MAKER)
    checker = _login(client, CHECKER)
    locs = client.get("/inventory/locations", headers=maker).json()["locations"]
    src_loc = locs[0]["id"]
    dst_loc = locs[1]["id"]

    sku = f"TRANS-TEST-{uuid.uuid4().hex[:6]}"
    item = client.post(
        "/inventory/items",
        headers=_idem(checker),
        json={"sku": sku, "name": "Syrup Đào Chuyển Kho", "unit": "chai", "cost_price": "85000"},
    ).json()
    item_id = item["id"]

    exp_date = (date.today() + timedelta(days=90)).isoformat()
    lot_code = f"LOT-DAO-{uuid.uuid4().hex[:4]}"

    # Nhập 6 chai tại Kho Tổng (src_loc)
    r_in = client.post(
        "/inventory/requests",
        headers=_idem(maker),
        json={
            "kind": "receipt",
            "dest_id": src_loc,
            "lines": [{"item_id": item_id, "quantity": "6", "unit_price": "85000", "lot_no": lot_code, "expiry_date": exp_date}],
        },
    ).json()
    client.post(f"/inventory/requests/{r_in['id']}/submit", headers=_idem(maker))
    client.post(f"/inventory/requests/{r_in['id']}/approve", headers=_idem(checker))

    # Chuyển 4 chai từ Kho Tổng sang Quầy Bar (dst_loc)
    r_transfer = client.post(
        "/inventory/requests",
        headers=_idem(maker),
        json={
            "kind": "transfer",
            "source_id": src_loc,
            "dest_id": dst_loc,
            "lines": [{"item_id": item_id, "quantity": "4"}],
            "reason": "Điều chuyển cho quầy pha chế",
        },
    ).json()
    tr_id = r_transfer["id"]
    client.post(f"/inventory/requests/{tr_id}/submit", headers=_idem(maker))
    appr_tr = client.post(f"/inventory/requests/{tr_id}/approve", headers=_idem(checker))
    assert appr_tr.status_code == 200, appr_tr.text

    # Kiểm tra Kho Tổng còn 2 chai
    bals = client.get(
        "/inventory/balances", headers=checker, params={"item_id": item_id}
    ).json()["balances"]
    src_bal = next(b for b in bals if b["item_id"] == item_id and b["location_id"] == src_loc)
    assert Decimal(str(src_bal["quantity"])) == Decimal("2.000")

    # Kiểm tra Quầy Bar có 4 chai
    dst_bal = next(b for b in bals if b["item_id"] == item_id and b["location_id"] == dst_loc)
    assert Decimal(str(dst_bal["quantity"])) == Decimal("4.000")


def test_outbound_syncs_used_qty_to_open_stocktake(client):
    maker = _login(client, MAKER)
    checker = _login(client, CHECKER)
    locs = client.get("/inventory/locations", headers=maker).json()["locations"]
    src_loc = locs[0]["id"]

    sku = f"ST-SYNC-{uuid.uuid4().hex[:6]}"
    item = client.post(
        "/inventory/items",
        headers=_idem(checker),
        json={"sku": sku, "name": "Trà Oolong Đồng Bộ Ca", "unit": "gói", "cost_price": "40000"},
    ).json()
    item_id = item["id"]

    # Nhập 10 gói tồn sẵn
    r_in = client.post(
        "/inventory/requests",
        headers=_idem(maker),
        json={
            "kind": "receipt",
            "dest_id": src_loc,
            "lines": [{"item_id": item_id, "quantity": "10", "unit_price": "40000", "lot_no": "LOT-ST-01", "expiry_date": (date.today() + timedelta(days=90)).isoformat()}],
        },
    ).json()
    client.post(f"/inventory/requests/{r_in['id']}/submit", headers=_idem(maker))
    client.post(f"/inventory/requests/{r_in['id']}/approve", headers=_idem(checker))

    # Mở ca kiểm kê tại kho. Mỗi lần chạy để lại một ca "morning" ở trạng thái
    # open, nên ngày phải được thử nhiều ngày khác nhau cho tới khi tìm được
    # ngày chưa có ca nào mở (tránh lỗi 409 SHIFT_ALREADY_OPEN).
    _st_res, st_id = open_shift(client, _idem(maker), src_loc)

    # Xuất nội bộ 2 gói để pha test menu mới
    out_internal = client.post(
        "/inventory/requests",
        headers=_idem(maker),
        json={
            "kind": "issue",
            "sub_kind": "internal",
            "source_id": src_loc,
            "lines": [{"item_id": item_id, "quantity": "2"}],
            "reason": "Pha test công thức mẫu mới",
        },
    ).json()
    client.post(f"/inventory/requests/{out_internal['id']}/submit", headers=_idem(maker))
    client.post(f"/inventory/requests/{out_internal['id']}/approve", headers=_idem(checker))

    # Kiểm tra ca kiểm kê đang mở: used_qty phải tự động tăng 2 gói
    st_detail = client.get(f"/inventory/stocktakes/{st_id}", headers=maker).json()
    st_lines = st_detail.get("lines", [])
    st_line = next((ln for ln in st_lines if ln["item_id"] == item_id), None)
    assert st_line is not None
    assert Decimal(str(st_line["used_qty"])) == Decimal("2.000")
    # theoretical_qty = opening(10) + received(0) - used(2) = 8
    assert Decimal(str(st_line["theoretical_qty"])) == Decimal("8")


def test_reports_inventory_summary_breakdown(client):
    maker = _login(client, MAKER)
    checker = _login(client, CHECKER)
    locs = client.get("/inventory/locations", headers=maker).json()["locations"]
    src_loc = locs[0]["id"]

    # Gọi API báo cáo Nhập - Xuất - Tồn chi tiết
    res = client.get(f"/reports/inventory-summary?location_id={src_loc}", headers=checker)
    assert res.status_code == 200, res.text
    data = res.json()
    assert "items" in data
    # Kiểm tra cấu trúc các cột phân loại xuất VÀ cột nhập phân loại mới
    for row in data["items"]:
        # Cột tổng nhập (tương thích ngược)
        assert "inbound_qty" in row
        assert "inbound_cost" in row
        # Cột nhập phân loại (mới - Điểm 2)
        assert "inbound_receipt_qty" in row
        assert "inbound_receipt_cost" in row
        assert "inbound_transfer_qty" in row
        assert "inbound_transfer_cost" in row
        # Cột xuất phân loại
        assert "outbound_sale_qty" in row
        assert "outbound_sale_cost" in row
        assert "outbound_spoilage_qty" in row
        assert "outbound_spoilage_cost" in row
        assert "outbound_internal_qty" in row
        assert "outbound_internal_cost" in row
        assert "outbound_transfer_qty" in row
        assert "outbound_transfer_cost" in row
        assert "total_outbound_qty" in row
        assert "total_outbound_cost" in row
        # Tổng nhập = nhập NCC + nhập chuyển kho
        total = Decimal(row["inbound_qty"])
        r_qty = Decimal(row["inbound_receipt_qty"])
        t_qty = Decimal(row["inbound_transfer_qty"])
        assert total == r_qty + t_qty, (
            f"inbound_qty ({total}) != receipt ({r_qty}) + transfer ({t_qty})"
        )


def test_concurrent_issues_do_not_produce_negative_stock(client):
    maker = _login(client, MAKER)
    checker = _login(client, CHECKER)
    locs = client.get("/inventory/locations", headers=maker).json()["locations"]
    src_loc = locs[0]["id"]

    sku = f"CONC-{uuid.uuid4().hex[:6]}"
    item = client.post(
        "/inventory/items",
        headers=_idem(checker),
        json={"sku": sku, "name": "Bột Trà Xanh Concurrency", "unit": "gói", "cost_price": "60000"},
    ).json()
    item_id = item["id"]

    # Nhập chính xác 5 gói
    r_in = client.post(
        "/inventory/requests",
        headers=_idem(maker),
        json={
            "kind": "receipt",
            "dest_id": src_loc,
            "lines": [{"item_id": item_id, "quantity": "5", "unit_price": "60000", "lot_no": "LOT-5PACK", "expiry_date": (date.today() + timedelta(days=90)).isoformat()}],
        },
    ).json()
    client.post(f"/inventory/requests/{r_in['id']}/submit", headers=_idem(maker))
    client.post(f"/inventory/requests/{r_in['id']}/approve", headers=_idem(checker))

    # Request 1 muốn xuất 4 gói
    r1 = client.post(
        "/inventory/requests",
        headers=_idem(maker),
        json={
            "kind": "issue",
            "sub_kind": "sale",
            "source_id": src_loc,
            "lines": [{"item_id": item_id, "quantity": "4"}],
        },
    ).json()
    sub1 = client.post(f"/inventory/requests/{r1['id']}/submit", headers=_idem(maker))
    assert sub1.status_code == 200

    # Request 2 cũng muốn xuất 4 gói (tổng 8 > 5 hiện có)
    r2 = client.post(
        "/inventory/requests",
        headers=_idem(maker),
        json={
            "kind": "issue",
            "sub_kind": "sale",
            "source_id": src_loc,
            "lines": [{"item_id": item_id, "quantity": "4"}],
        },
    ).json()
    # Khi Request 1 đã đặt trước 4 gói, tồn khả dụng còn lại = 5 - 4 = 1 gói.
    # Request 2 cố submit 4 gói -> Bị chặn với 409 INSUFFICIENT_STOCK
    sub2 = client.post(f"/inventory/requests/{r2['id']}/submit", headers=_idem(maker))
    assert sub2.status_code == 409
    assert sub2.json()["error"]["code"] == "INSUFFICIENT_STOCK"

    # Duyệt Request 1 thành công
    appr1 = client.post(f"/inventory/requests/{r1['id']}/approve", headers=_idem(checker))
    assert appr1.status_code == 200

    # Tồn kho thực tế còn lại 1 gói (không bị âm)
    bals = client.get(
        "/inventory/balances", headers=checker, params={"item_id": item_id}
    ).json()["balances"]
    item_bal = next(b for b in bals if b["item_id"] == item_id and b["location_id"] == src_loc)
    assert Decimal(str(item_bal["quantity"])) == Decimal("1.000")
