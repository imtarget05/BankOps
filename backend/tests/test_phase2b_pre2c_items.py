"""Tests cho 3 điểm soát trước Bước 2C:
  1. PostgreSQL + FOR UPDATE: chặn xuất âm qua cơ chế reservation (đã test bằng đơn test khác),
     ở đây xác nhận DB engine đang là PostgreSQL+asyncpg.
  2. Báo cáo inventory-summary: inbound_transfer_qty ở kho đích == outbound_transfer_qty ở kho nguồn.
  3. Lô TON-DAU-KY: giá vốn lấy từ item.cost_price, cost_amount tính đúng khi xuất.
"""
import uuid
from datetime import date, timedelta
from decimal import Decimal

from app.database import DATABASE_URL
from app.models.inventory import LotBalance

DEMO_PASSWORD = "DemoPass123!"
MAKER = "demo_maker"
CHECKER = "demo_checker"


def _login(client, username: str) -> dict[str, str]:
    r = client.post("/auth/login", data={"username": username, "password": DEMO_PASSWORD})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def _idem(headers: dict[str, str]) -> dict[str, str]:
    return {**headers, "Idempotency-Key": str(uuid.uuid4())}


# ---------------------------------------------------------------------------
# Điểm 1: Xác nhận database engine là PostgreSQL+asyncpg
# ---------------------------------------------------------------------------
def test_database_engine_is_postgresql():
    """Xác nhận app đang chạy với PostgreSQL+asyncpg (không phải SQLite).
    SELECT ... FOR UPDATE và CHECK (quantity >= 0) có tác dụng thật trên PostgreSQL.
    """
    assert "postgresql+asyncpg" in DATABASE_URL, (
        f"Kỳ vọng postgresql+asyncpg, nhưng DATABASE_URL = {DATABASE_URL}"
    )
    assert "sqlite" not in DATABASE_URL.lower(), "Không được dùng SQLite cho môi trường test"


# ---------------------------------------------------------------------------
# Điểm 2: Chuyển kho — báo cáo kho đích phải có inbound_transfer == outbound của kho nguồn
# ---------------------------------------------------------------------------
def test_transfer_inbound_visible_in_dest_summary(client):
    """Sau khi chuyển kho, kho đích phải có inbound_transfer_qty bằng outbound_transfer_qty kho nguồn.
    Tổng hệ thống: Σ inbound_transfer == Σ outbound_transfer.
    """
    maker = _login(client, MAKER)
    checker = _login(client, CHECKER)

    locs = client.get("/inventory/locations", headers=maker).json()["locations"]
    assert len(locs) >= 2, "Cần ít nhất 2 kho để test chuyển kho"
    src_loc = locs[0]["id"]
    dst_loc = locs[1]["id"]

    # Tạo nguyên liệu mới để isolate test
    sku = f"TRF-RPT-{uuid.uuid4().hex[:6]}"
    item = client.post(
        "/inventory/items",
        headers=_idem(checker),
        json={"sku": sku, "name": "Trà Xanh Chuyển Kho Test", "unit": "hộp", "cost_price": "80000"},
    ).json()
    item_id = item["id"]

    # Nhập 20 hộp vào kho nguồn
    r_in = client.post(
        "/inventory/requests",
        headers=_idem(maker),
        json={
            "kind": "receipt",
            "dest_id": src_loc,
            "lines": [{
                "item_id": item_id,
                "quantity": "20",
                "unit_price": "80000",
                "lot_no": "LOT-TRF-20",
                "expiry_date": (date.today() + timedelta(days=180)).isoformat(),
            }],
        },
    ).json()
    client.post(f"/inventory/requests/{r_in['id']}/submit", headers=_idem(maker))
    client.post(f"/inventory/requests/{r_in['id']}/approve", headers=_idem(checker))

    # Chuyển 8 hộp từ kho nguồn sang kho đích (kind=issue sub_kind=transfer)
    r_tr = client.post(
        "/inventory/requests",
        headers=_idem(maker),
        json={
            "kind": "issue",
            "sub_kind": "transfer",
            "source_id": src_loc,
            "dest_id": dst_loc,
            "lines": [{"item_id": item_id, "quantity": "8"}],
        },
    ).json()
    assert "id" in r_tr, f"Tạo phiếu chuyển kho thất bại: {r_tr}"
    client.post(f"/inventory/requests/{r_tr['id']}/submit", headers=_idem(maker))
    appr = client.post(f"/inventory/requests/{r_tr['id']}/approve", headers=_idem(checker))
    assert appr.status_code == 200, appr.text

    # Lấy báo cáo kho nguồn
    src_summary = client.get(
        f"/reports/inventory-summary?location_id={src_loc}", headers=checker
    ).json()
    src_row = next((r for r in src_summary["items"] if r["item_id"] == item_id), None)
    assert src_row is not None, "Không tìm thấy nguyên liệu trong báo cáo kho nguồn"

    # Lấy báo cáo kho đích
    dst_summary = client.get(
        f"/reports/inventory-summary?location_id={dst_loc}", headers=checker
    ).json()
    dst_row = next((r for r in dst_summary["items"] if r["item_id"] == item_id), None)
    assert dst_row is not None, "Không tìm thấy nguyên liệu trong báo cáo kho đích"

    # Kho nguồn: outbound_transfer_qty = 8
    src_out_transfer = Decimal(src_row["outbound_transfer_qty"])
    assert src_out_transfer == Decimal("8"), (
        f"Kho nguồn outbound_transfer_qty kỳ vọng 8, thực tế {src_out_transfer}"
    )

    # Kho đích: inbound_transfer_qty == outbound_transfer_qty kho nguồn (cross-location balance)
    dst_in_transfer = Decimal(dst_row["inbound_transfer_qty"])
    assert dst_in_transfer == src_out_transfer, (
        f"Cross-location lệch: kho đích inbound_transfer ({dst_in_transfer}) "
        f"!= kho nguồn outbound_transfer ({src_out_transfer})"
    )

    # Kho đích: không có inbound_receipt (chỉ nhận từ chuyển kho, không mua NCC)
    dst_in_receipt = Decimal(dst_row["inbound_receipt_qty"])
    assert dst_in_receipt == Decimal("0"), (
        f"Kho đích không nên có inbound_receipt_qty, thực tế {dst_in_receipt}"
    )

    # Bất biến: inbound_qty == inbound_receipt_qty + inbound_transfer_qty cho CẢ HAI kho
    for label, row in [("src", src_row), ("dst", dst_row)]:
        total_in = Decimal(row["inbound_qty"])
        r_qty = Decimal(row["inbound_receipt_qty"])
        t_qty = Decimal(row["inbound_transfer_qty"])
        assert total_in == r_qty + t_qty, (
            f"[{label}] inbound_qty ({total_in}) != receipt ({r_qty}) + transfer ({t_qty})"
        )


# ---------------------------------------------------------------------------
# Điểm 3: Lô TON-DAU-KY dùng item.cost_price (unit_cost != 0)
# ---------------------------------------------------------------------------
def test_ton_dau_ky_lot_uses_item_cost_price(client):
    """Khi tồn Balance cũ chưa có LotBalance, hệ thống tự sinh lô TON-DAU-KY
    với unit_cost = item.cost_price. Khi xuất, outbound_sale_cost != 0.
    """
    import asyncio

    from sqlalchemy import delete

    from app.database import AsyncSessionLocal

    maker = _login(client, MAKER)
    checker = _login(client, CHECKER)

    locs = client.get("/inventory/locations", headers=maker).json()["locations"]
    src_loc = locs[0]["id"]
    import uuid as _uuid
    loc_uuid = _uuid.UUID(src_loc)

    COST_PRICE = Decimal("55000")
    sku = f"TDKY-{uuid.uuid4().hex[:6]}"

    # Tạo nguyên liệu với cost_price = 55000
    item_res = client.post(
        "/inventory/items",
        headers=_idem(checker),
        json={"sku": sku, "name": "Bột Matcha TON-DAU-KY Test", "unit": "gói", "cost_price": str(COST_PRICE)},
    ).json()
    item_id = item_res["id"]
    item_uuid = _uuid.UUID(item_id)

    # Nhập 5 gói (không có lot_no để dễ xóa sau)
    r_in = client.post(
        "/inventory/requests",
        headers=_idem(maker),
        json={
            "kind": "receipt",
            "dest_id": src_loc,
            "lines": [{"item_id": item_id, "quantity": "5", "unit_price": str(COST_PRICE)}],
        },
    ).json()
    client.post(f"/inventory/requests/{r_in['id']}/submit", headers=_idem(maker))
    client.post(f"/inventory/requests/{r_in['id']}/approve", headers=_idem(checker))

    # Xóa tất cả LotBalance của item này ở kho này để simulate tồn cũ (không có lô)
    async def _delete_lot_balances():
        async with AsyncSessionLocal() as session:
            async with session.begin():
                await session.execute(
                    delete(LotBalance).where(
                        LotBalance.location_id == loc_uuid,
                        LotBalance.item_id == item_uuid,
                    )
                )
    asyncio.run(_delete_lot_balances())

    # Xuất 3 gói bằng sale — FEFO phải tự seed lô TON-DAU-KY với cost_price=55000
    r_out = client.post(
        "/inventory/requests",
        headers=_idem(maker),
        json={
            "kind": "issue",
            "sub_kind": "sale",
            "source_id": src_loc,
            "lines": [{"item_id": item_id, "quantity": "3"}],
        },
    ).json()
    assert "id" in r_out, r_out
    client.post(f"/inventory/requests/{r_out['id']}/submit", headers=_idem(maker))
    appr = client.post(f"/inventory/requests/{r_out['id']}/approve", headers=_idem(checker))
    assert appr.status_code == 200, appr.text

    # Báo cáo summary: outbound_sale_cost phải == 3 * 55000 = 165000
    summary = client.get(
        f"/reports/inventory-summary?location_id={src_loc}", headers=checker
    ).json()
    row = next((r for r in summary["items"] if r["item_id"] == item_id), None)
    assert row is not None, "Không tìm thấy nguyên liệu trong báo cáo"

    sale_cost = Decimal(row["outbound_sale_cost"])
    expected_cost = COST_PRICE * Decimal("3")  # 55000 * 3 = 165000
    assert sale_cost == expected_cost, (
        f"outbound_sale_cost kỳ vọng {expected_cost} (3 × {COST_PRICE}), thực tế {sale_cost}. "
        f"Lô TON-DAU-KY phải dùng cost_price của nguyên liệu, không phải 0."
    )
