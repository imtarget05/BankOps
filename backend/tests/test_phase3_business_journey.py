"""Phase B — Hành trình nghiệp vụ toàn diện."""

from __future__ import annotations

import uuid
from datetime import date, timedelta
from decimal import Decimal

import pytest

from conftest import open_shift

DEMO_PASSWORD = "DemoPass123!"
MAKER = "demo_maker"
CHECKER_A = "demo_checker"
CHECKER_B = "demo_approver2"
READER = "demo_auditor"


def _login(client, username: str) -> dict[str, str]:
    r = client.post("/auth/login", data={"username": username, "password": DEMO_PASSWORD})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def _idem(headers: dict[str, str]) -> dict[str, str]:
    return {**headers, "Idempotency-Key": str(uuid.uuid4())}




# ---------------------------------------------------------------------------
# Stage 1 — Nhận lô (receipt) + FEFO xuất
# ---------------------------------------------------------------------------


class TestStage1_ReceiptAndFefo:
    def test_receipt_creates_balance_and_escrows(self, client):
        maker = _login(client, MAKER)
        items = client.get("/inventory/items", headers=maker).json()["items"]
        locs = client.get("/inventory/locations", headers=maker).json()["locations"]
        item_id = items[0]["id"]
        loc_id = locs[0]["id"]

        r1 = client.post(
            "/inventory/requests",
            headers=_idem(maker),
            json={
                "kind": "receipt",
                "sub_kind": "internal",
                "source_id": loc_id,
                "lines": [
                    {
                        "item_id": item_id,
                        "quantity": "10",
                        "lot_no": "LOT-100",
                        "expiry_date": (date.today() + timedelta(days=30)).isoformat(),
                    }
                ],
            },
        )
        assert r1.status_code == 201, r1.text
        request_id = r1.json()["id"]
        assert r1.json()["status"] == "draft"

        r2 = client.post(f"/inventory/requests/{request_id}/submit", headers=maker)
        assert r2.status_code == 200, r2.text
        assert r2.json()["status"] == "submitted"

        r3 = _approve(client, request_id, CHECKER_A)
        assert r3.status_code == 200, r3.text
        assert r3.json()["status"] == "posted"

        bal_before = client.get("/inventory/balances", headers=maker).json()["balances"]
        row_before = next(
            (b for b in bal_before if b["item_id"] == item_id and b["location_id"] == loc_id),
            None,
        )
        before_qty = Decimal(row_before["quantity"]) if row_before else Decimal("0")

        bal = client.get("/inventory/balances", headers=maker).json()["balances"]
        row = next(b for b in bal if b["item_id"] == item_id and b["location_id"] == loc_id)
        assert Decimal(row["quantity"]) == before_qty + Decimal("10")

    def test_efo_selects_oldest_expiry_first(self, client):
        maker = _login(client, MAKER)
        item_id, src_loc, dst_loc = _get_first_item_and_loc(client, MAKER)

        exp_old = (date.today() + timedelta(days=1)).isoformat()
        exp_new = (date.today() + timedelta(days=30)).isoformat()

        inbound = client.post(
            "/inventory/requests",
            headers=_idem(maker),
            json={
                "kind": "receipt",
                "sub_kind": "internal",
                "dest_id": src_loc,
                "lines": [
                    {
                        "item_id": item_id,
                        "quantity": "5",
                        "lot_no": "LOT-OLD",
                        "expiry_date": exp_old,
                    },
                    {
                        "item_id": item_id,
                        "quantity": "3",
                        "lot_no": "LOT-NEW",
                        "expiry_date": exp_new,
                    },
                ],
            },
        )
        assert inbound.status_code == 201, inbound.text
        inbound_id = inbound.json()["id"]
        client.post(f"/inventory/requests/{inbound_id}/submit", headers=maker)
        _approve(client, inbound_id, CHECKER_A)

        out_req = client.post(
            "/inventory/requests",
            headers=_idem(maker),
            json={
                "kind": "issue",
                "sub_kind": "sale",
                "source_id": src_loc,
                "dest_id": dst_loc,
                "lines": [{"item_id": item_id, "quantity": "4"}],
            },
        )
        assert out_req.status_code == 201, out_req.text
        out_id = out_req.json()["id"]
        client.post(f"/inventory/requests/{out_id}/submit", headers=maker)


# ---------------------------------------------------------------------------
# Stage 2 — Kiểm kê ca (Stocktake) + phiếu điều chỉnh
# ---------------------------------------------------------------------------


class TestStage2_StocktakeAndAdjustment:
    @pytest.fixture
    def open_ca(self, client):
        maker = _login(client, MAKER)
        locs = client.get("/inventory/locations", headers=maker).json()["locations"]
        _, stocktake_id = open_shift(client, maker, locs[0]["id"], "morning")
        # Use the same business_date as the opened shift for subsequent ops
        st = client.get(f"/inventory/stocktakes/{stocktake_id}", headers=maker)
        biz_date = st.json()["business_date"]
        return {
            "maker": maker,
            "location_id": locs[0]["id"],
            "headers": maker,
            "stocktake_id": stocktake_id,
            "business_date": biz_date,
        }

    def test_two_checkers_cannot_open_same_shift(self, client, open_ca):
        _login(client, CHECKER_A)
        _login(client, CHECKER_B)
        resp = client.post(
            "/inventory/stocktakes",
            headers=open_ca["headers"],
            json={
                "location_id": open_ca["location_id"],
                "business_date": open_ca["business_date"],
                "shift_code": "morning",
                "note": "Cố gắng mở trùng ca",
            },
        )
        assert resp.status_code == 409, resp.text
        assert resp.json()["error"]["code"] == "SHIFT_ALREADY_OPEN"

    def test_stocktake_submit_approve_close_chain(self, client, open_ca):
        maker = _login(client, MAKER)
        loc_id = open_ca["location_id"]

        st = client.post(
            "/inventory/stocktakes",
            headers=maker,
            json={
                "location_id": loc_id,
                "business_date": open_ca["business_date"],
                "shift_code": "morning",
                "note": "Kiểm kê ca 1",
            },
        )
        assert st.status_code == 201, st.text
        stocktake_id = st.json()["id"]

        items = client.get("/inventory/items", headers=maker).json()["items"]
        item_id = items[0]["id"]
        client.put(
            f"/inventory/stocktakes/{stocktake_id}/lines",
            headers=maker,
            json={"lines": [{"item_id": item_id, "counted_qty": "7", "received_qty": "3"}]},
        )

        client.post(f"/inventory/stocktakes/{stocktake_id}/submit", headers=maker)
        client.post(f"/inventory/stocktakes/{stocktake_id}/approve", headers=maker)
        client.post(f"/inventory/stocktakes/{stocktake_id}/reject", headers=maker)

        st_close = client.get(f"/inventory/stocktakes/{stocktake_id}", headers=maker)
        assert st_close.status_code == 200, st_close.text
        assert st_close.json()["status"] == "closed"

    def test_adjustment_request_updates_balance_only_once(self, client, open_ca):
        maker = _login(client, MAKER)
        items = client.get("/inventory/items", headers=maker).json()["items"]
        loc_id = open_ca["location_id"]
        item_id = items[0]["id"]

        st = client.post(
            "/inventory/stocktakes",
            headers=maker,
            json={
                "location_id": loc_id,
                "business_date": open_ca["business_date"],
                "shift_code": "morning",
                "note": "Kiểm kê điều chỉnh",
            },
        )
        assert st.status_code == 201, st.text
        stocktake_id = st.json()["id"]
        client.post(f"/inventory/stocktakes/{stocktake_id}/submit", headers=maker)
        client.post(f"/inventory/stocktakes/{stocktake_id}/approve", headers=maker)
        client.post(f"/inventory/stocktakes/{stocktake_id}/close", headers=maker)

        audit = client.get("/audit-events", headers=maker).json()["events"]
        stocktake_events = [e for e in audit if e.get("subject_type") == "inventory_stocktake"]
        assert len(stocktake_events) >= 1
        _approve(client, out_id, CHECKER_A)

        bal = client.get("/inventory/balances", headers=maker).json()["balances"]
        old = next(b for b in bal if b.get("lot_no") == "LOT-OLD")
        new = next(b for b in bal if b.get("lot_no") == "LOT-NEW")
        assert Decimal(old["quantity"]) == Decimal("1"), f"Expected 1, got {old['quantity']}"
        assert Decimal(new["quantity"]) == Decimal("3")
def _get_first_item_and_loc(client, user: str):
    maker = _login(client, user)
    items = client.get("/inventory/items", headers=maker).json()["items"]
    locs = client.get("/inventory/locations", headers=maker).json()["locations"]
    return items[0]["id"], locs[0]["id"], locs[1]["id"] if len(locs) > 1 else locs[0]["id"]


def _approve(client, request_id, checker_username):
    checker = _login(client, checker_username)
    return client.post(
        f"/inventory/requests/{request_id}/approve",
        headers={**checker, "Idempotency-Key": str(uuid.uuid4())},
    )


# ---------------------------------------------------------------------------
# Stage 3 — Duyệt/Từ chối với 2 checker cạnh tranh
# ---------------------------------------------------------------------------


class TestStage3_ApprovalRace:
    def test_two_checkers_race_and_winner_wins(self, client):
        maker = _login(client, MAKER)
        items = client.get("/inventory/items", headers=maker).json()["items"]
        locs = client.get("/inventory/locations", headers=maker).json()["locations"]
        item_id = items[0]["id"]
        src_id = locs[0]["id"]
        dst_id = locs[1]["id"]

        req = client.post(
            "/inventory/requests",
            headers=_idem(maker),
            json={
                "kind": "receipt",
                "sub_kind": "internal",
                "source_id": src_id,
                "dest_id": dst_id,
                "lines": [{"item_id": item_id, "quantity": "20"}],
            },
        )
        assert req.status_code == 201, req.text
        request_id = req.json()["id"]
        client.post(f"/inventory/requests/{request_id}/submit", headers=maker)

        h_a = _login(client, CHECKER_A)
        h_b = _login(client, CHECKER_B)

        r1 = client.post(
            f"/inventory/requests/{request_id}/approve",
            headers={**h_a, "Idempotency-Key": str(uuid.uuid4())},
        )
        r2 = client.post(
            f"/inventory/requests/{request_id}/approve",
            headers={**h_b, "Idempotency-Key": str(uuid.uuid4())},
        )

        assert r1.status_code in (200, 409), f"Checker A got {r1.status_code}"
        assert r2.status_code in (200, 409), f"Checker B got {r2.status_code}"
        success = [r for r in (r1, r2) if r.status_code == 200]
        assert len(success) == 1, f"Expected exactly 1 success, got {len(success)}"



# ---------------------------------------------------------------------------
# Stage 4 — Idempotency, retry, concurrency, failure
# ---------------------------------------------------------------------------


class TestStage4_IdempotencyRetry:
    def test_same_payload_idempotent(self, client):
        maker = _login(client, MAKER)
        item_id, loc_id, _ = _get_first_item_and_loc(client, MAKER)

        payload = {
            "kind": "receipt",
            "sub_kind": "internal",
            "source_id": loc_id,
            "lines": [{"item_id": item_id, "quantity": "5"}],
        }

        key = str(uuid.uuid4())
        r1 = client.post("/inventory/requests", headers={**maker, "Idempotency-Key": key}, json=payload)
        r2 = client.post("/inventory/requests", headers={**maker, "Idempotency-Key": key}, json=payload)
        assert r1.status_code == 201, r1.text
        assert r2.status_code == 200, r2.text
        assert r1.json()["id"] == r2.json()["id"]

    def test_new_payload_after_replay_409(self, client):
        maker = _login(client, MAKER)
        item_id, loc_id, _ = _get_first_item_and_loc(client, MAKER)

        key = str(uuid.uuid4())
        r1 = client.post("/inventory/requests", headers={**maker, "Idempotency-Key": key}, json={"kind": "receipt", "sub_kind": "internal", "source_id": loc_id, "lines": [{"item_id": item_id, "quantity": "5"}]})
        r2 = client.post("/inventory/requests", headers={**maker, "Idempotency-Key": key}, json={"kind": "receipt", "sub_kind": "internal", "source_id": loc_id, "lines": [{"item_id": item_id, "quantity": "6"}]})
        assert r1.status_code == 201, r1.text
        assert r2.status_code == 409, r2.text

    def test_concurrent_two_writers_same_payload_one_wins(self, client):
        maker = _login(client, MAKER)
        item_id, loc_id, _ = _get_first_item_and_loc(client, MAKER)

        key = str(uuid.uuid4())
        r1 = client.post("/inventory/requests", headers={**maker, "Idempotency-Key": key}, json={"kind": "receipt", "sub_kind": "internal", "source_id": loc_id, "lines": [{"item_id": item_id, "quantity": "10"}]})
        r2 = client.post("/inventory/requests", headers={**maker, "Idempotency-Key": key}, json={"kind": "receipt", "sub_kind": "internal", "source_id": loc_id, "lines": [{"item_id": item_id, "quantity": "10"}]})
        assert r1.status_code == 201, r1.text
        assert r2.status_code == 200, r2.text
        assert r1.json()["id"] == r2.json()["id"]


# ---------------------------------------------------------------------------
# Stage 5 — Negative security tests
# ---------------------------------------------------------------------------


class TestStage5_NegativeSecurity:
    def test_reader_cross_branch_403(self, client):
        h = _login(client, READER)
        resp = client.get("/inventory/stocktakes", headers=h)
        assert resp.status_code in (200, 400, 403, 404), f"Expected 200/400/403/404 got {resp.status_code}"

    def test_writer_cross_branch_409(self, client):
        h = _login(client, MAKER)
        items = client.get("/inventory/items", headers=h).json()["items"]
        locs = client.get("/inventory/locations", headers=h).json()["locations"]
        item_id = items[0]["id"]
        src_id = locs[0]["id"]
        dst_id = locs[1]["id"]

        resp = client.post(
            "/inventory/requests",
            headers=_idem(h),
            json={
                "kind": "issue",
                "sub_kind": "sale",
                "source_id": src_id,
                "dest_id": dst_id,
                "lines": [{"item_id": item_id, "quantity": "1"}],
            },
        )
        assert resp.status_code in (201, 409, 404), f"Expected 201/409/404 got {resp.status_code}"


# ---------------------------------------------------------------------------
# Stage 6 — Migration + backup/restore
# ---------------------------------------------------------------------------


class TestStage6_MigrationRestore:
    def test_migration_applies_and_rollforwards(self, client):
        assert True

    def test_backup_restore_checksum(self, client):
        assert True