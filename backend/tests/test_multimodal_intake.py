"""Tests for Multimodal Document Intake (Vendor Invoice / Stock Receipt).

Verifies:
1. Deterministic extraction and schema parsing of invoice documents.
2. Mathematical reconciliation & validation:
   - Line items: quantity * unit_price == line_total
   - Subtotal: sum(line_totals) == subtotal
   - Total: subtotal + tax_amount == total_amount
3. Arithmetic mismatch rejection (flags discrepancies blocking draft creation).
4. Catalog matching against inv_items.
5. Strict Maker-Checker preservation:
   - Document intake only creates an InventoryRequest in 'draft' status.
   - Balances do not change until Maker submits and Checker approves.
"""

from __future__ import annotations

import io
import uuid
from decimal import Decimal

import pytest

from app.schemas.invoice_intake import (
    InvoiceExtraction,
    InvoiceLineItem,
    ValidationReport,
)
from app.services.multimodal_service import (
    parse_invoice_bytes,
    parse_invoice_text,
    validate_invoice_math,
)

DEMO_PASSWORD = "DemoPass123!"
MAKER = "demo_maker"
CHECKER = "demo_checker"


def _login(client, username: str) -> dict[str, str]:
    r = client.post(
        "/auth/login", data={"username": username, "password": DEMO_PASSWORD}
    )
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


SAMPLE_INVOICE_TEXT = """
HÓA ĐƠN BÁN HÀNG / INVOICE
Nhà cung cấp: Cty TNHH Nguyên Liệu Trà Sữa Phúc Thịnh
Mã số thuế: 0312345678
Số hóa đơn: INV-2026-10-8899
Ngày: 2026-10-24
------------------------------------------------------------
1. Trà Đen Phúc Long (SKU: TEA-BLK-01) | SL: 10 kg | Đơn giá: 120000 | Thành tiền: 1200000 | Lô: LOT-2026A | HSD: 2027-10-24
2. Trân Châu Đen (SKU: TOP-TCD-01) | SL: 20 gói | Đơn giá: 45000 | Thành tiền: 900000 | Lô: LOT-2026B | HSD: 2027-04-24
------------------------------------------------------------
Cộng tiền hàng: 2100000
Thuế GTGT (VAT 10%): 210000
Tổng thanh toán: 2310000
"""


class TestInvoiceMathValidation:
    def test_valid_invoice_math_reconciliation(self):
        extraction = parse_invoice_text(SAMPLE_INVOICE_TEXT)
        assert extraction.supplier_name == "Cty TNHH Nguyên Liệu Trà Sữa Phúc Thịnh"
        assert extraction.invoice_no == "INV-2026-10-8899"
        assert len(extraction.line_items) == 2

        report = validate_invoice_math(extraction)
        assert report.is_valid is True
        assert report.line_math_valid is True
        assert report.subtotal_valid is True
        assert report.total_valid is True
        assert len(report.errors) == 0

    def test_line_math_mismatch_detected(self):
        # 10 * 120,000 = 1,200,000 but line_total declared as 1,300,000
        bad_line = InvoiceLineItem(
            raw_name="Trà Đen",
            sku="TEA-01",
            quantity=Decimal("10"),
            unit_price=Decimal("120000"),
            line_total=Decimal("1300000"),  # mismatch!
        )
        extraction = InvoiceExtraction(
            supplier_name="Vendor A",
            invoice_no="INV-BAD-01",
            invoice_date="2026-10-24",
            line_items=[bad_line],
            subtotal=Decimal("1300000"),
            tax_amount=Decimal("0"),
            total_amount=Decimal("1300000"),
        )
        report = validate_invoice_math(extraction)
        assert report.is_valid is False
        assert report.line_math_valid is False
        assert any("does not match stated line total" in err for err in report.errors)

    def test_subtotal_mismatch_detected(self):
        # Line total = 1,200,000 but subtotal declared as 2,000,000
        line = InvoiceLineItem(
            raw_name="Trà Đen",
            sku="TEA-01",
            quantity=Decimal("10"),
            unit_price=Decimal("120000"),
            line_total=Decimal("1200000"),
        )
        extraction = InvoiceExtraction(
            supplier_name="Vendor A",
            invoice_no="INV-BAD-02",
            invoice_date="2026-10-24",
            line_items=[line],
            subtotal=Decimal("2000000"),  # mismatch!
            tax_amount=Decimal("0"),
            total_amount=Decimal("2000000"),
        )
        report = validate_invoice_math(extraction)
        assert report.is_valid is False
        assert report.subtotal_valid is False
        assert any("does not match invoice subtotal" in err for err in report.errors)

    def test_total_amount_mismatch_detected(self):
        # Subtotal 1,000,000 + tax 100,000 = 1,100,000, but stated total = 1,500,000
        line = InvoiceLineItem(
            raw_name="Trà Đen",
            sku="TEA-01",
            quantity=Decimal("10"),
            unit_price=Decimal("100000"),
            line_total=Decimal("1000000"),
        )
        extraction = InvoiceExtraction(
            supplier_name="Vendor A",
            invoice_no="INV-BAD-03",
            invoice_date="2026-10-24",
            line_items=[line],
            subtotal=Decimal("1000000"),
            tax_amount=Decimal("100000"),
            total_amount=Decimal("1500000"),  # mismatch!
        )
        report = validate_invoice_math(extraction)
        assert report.is_valid is False
        assert report.total_valid is False
        assert any("does not match stated total payment" in err for err in report.errors)


class TestMultimodalIntakeAPI:
    def test_extract_endpoint(self, client):
        maker_auth = _login(client, MAKER)
        file_bytes = SAMPLE_INVOICE_TEXT.encode("utf-8")
        files = {"file": ("invoice_sample.txt", file_bytes, "text/plain")}

        res = client.post("/inventory/intake/extract", files=files, headers=maker_auth)
        assert res.status_code == 200, res.text
        data = res.json()
        assert data["status"] in ("extracted", "validation_failed")
        assert data["extraction"]["invoice_no"] == "INV-2026-10-8899"
        assert len(data["extraction"]["line_items"]) == 2
        assert data["validation"]["is_valid"] is True

    def test_intake_process_creates_draft_and_executes_maker_checker(self, client):
        maker_auth = _login(client, MAKER)
        checker_auth = _login(client, CHECKER)

        # 1. Look up existing inventory item and location
        items_res = client.get("/inventory/items", headers=maker_auth)
        assert items_res.status_code == 200
        items = items_res.json()["items"]
        target_item = items[0]
        item_id = target_item["id"]
        item_sku = target_item["sku"]

        locs_res = client.get("/inventory/locations", headers=maker_auth)
        assert locs_res.status_code == 200
        loc_id = locs_res.json()["locations"][0]["id"]

        # Read balance before receipt
        b_before = client.get(
            f"/inventory/balances?location_id={loc_id}&item_id={item_id}",
            headers=maker_auth,
        ).json()
        qty_before = Decimal("0")
        for b in b_before.get("balances", []):
            if b["item_id"] == item_id and b["location_id"] == loc_id:
                qty_before = Decimal(str(b["quantity"]))

        # 2. Build invoice matching target item SKU
        qty_intake = Decimal("15.0")
        unit_price = Decimal("100000.0")
        line_total = qty_intake * unit_price
        tax = line_total * Decimal("0.10")
        total = line_total + tax

        unique_inv_no = f"INV-{uuid.uuid4().hex[:6].upper()}"
        unique_lot = f"LOT-{uuid.uuid4().hex[:4].upper()}"
        invoice_doc = f"""
Nhà cung cấp: Đại Lý Trà Tân Cương
Số hóa đơn: {unique_inv_no}
Ngày: 2026-10-24
1. {target_item['name']} (SKU: {item_sku}) | SL: {qty_intake} kg | Đơn giá: {unit_price} | Thành tiền: {line_total} | Lô: {unique_lot} | HSD: 2027-12-31
Cộng tiền hàng: {line_total}
Thuế GTGT (VAT 10%): {tax}
Tổng thanh toán: {total}
"""
        files = {"file": ("vendor_invoice.txt", invoice_doc.encode("utf-8"), "text/plain")}
        data = {"dest_location_id": loc_id}

        # 3. Post to /inventory/intake/process
        res = client.post(
            "/inventory/intake/process",
            files=files,
            data=data,
            headers=maker_auth,
        )
        assert res.status_code == 200, res.text
        resp_data = res.json()
        assert resp_data["status"] == "draft_created"
        draft_id = resp_data["draft_request_id"]
        assert draft_id is not None

        # 4. CRITICAL INVARIANT: The intake created a DRAFT. It must NOT auto-post!
        # Check request in DB:
        req_res = client.get(f"/inventory/requests/{draft_id}", headers=maker_auth)
        assert req_res.status_code == 200
        req_info = req_res.json()
        assert req_info["status"] == "draft"
        assert req_info["kind"] == "receipt"
        assert req_info["invoice_no"] == unique_inv_no

        # Balance must still be UNCHANGED
        b_after_draft = client.get(
            f"/inventory/balances?location_id={loc_id}&item_id={item_id}",
            headers=maker_auth,
        ).json()
        qty_after_draft = Decimal("0")
        for b in b_after_draft.get("balances", []):
            if b["item_id"] == item_id and b["location_id"] == loc_id:
                qty_after_draft = Decimal(str(b["quantity"]))
        assert qty_after_draft == qty_before

        # 5. Maker submits the draft request
        sub_res = client.post(
            f"/inventory/requests/{draft_id}/submit",
            headers={**maker_auth, "Idempotency-Key": str(uuid.uuid4())},
        )
        assert sub_res.status_code == 200, sub_res.text
        assert sub_res.json()["status"] == "submitted"

        # 6. Checker approves the request
        app_res = client.post(
            f"/inventory/requests/{draft_id}/approve",
            headers={**checker_auth, "Idempotency-Key": str(uuid.uuid4())},
        )
        assert app_res.status_code == 200, app_res.text
        assert app_res.json()["status"] in ("approved", "posted")

        # 7. Balance is now increased by exactly qty_intake!
        b_final = client.get(
            f"/inventory/balances?location_id={loc_id}&item_id={item_id}",
            headers=maker_auth,
        ).json()
        qty_final = Decimal("0")
        for b in b_final.get("balances", []):
            if b["item_id"] == item_id and b["location_id"] == loc_id:
                qty_final = Decimal(str(b["quantity"]))
        assert qty_final == qty_before + qty_intake
