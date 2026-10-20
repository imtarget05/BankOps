"""Phase 1: định mức tồn + cảnh báo thiếu + kiểm kê/chênh lệch (TDD).

RED ban đầu: endpoint chưa tồn tại -> 404; triển khai backend cho xanh dần:
- PUT /inventory/stock-levels (đặt min/max theo location+item)
- GET /inventory/low-stock (so tồn hiện tại với min, có suggested_action)
- Stocktake: POST open -> PUT lines -> POST submit -> POST approve tạo
  InventoryRequest kind=adjustment (Maker != Checker).
"""
from __future__ import annotations

import asyncio
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import date, timedelta
from pathlib import Path

from conftest import open_shift
from sqlalchemy import select

DEMO_PASSWORD = "DemoPass123!"


def _login(client, username: str) -> dict[str, str]:
    r = client.post("/auth/login", data={"username": username, "password": DEMO_PASSWORD})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


MANAGER = "demo_admin"
MAKER = "demo_maker"
CHECKER = "demo_checker"


def _seed_loc_item(client, headers: dict[str, str]) -> tuple[str, str, str, str]:
    items = client.get("/inventory/items", headers=headers).json()["items"]
    locs = client.get("/inventory/locations", headers=headers).json()["locations"]
    item = next(i for i in items if not i.get("tracked_serial"))
    return item["id"], item["sku"], locs[0]["id"], locs[0]["code"]


def _idem(headers: dict[str, str]) -> dict[str, str]:
    return {**headers, "Idempotency-Key": str(uuid.uuid4())}


class TestStockLevels:
    def test_put_stock_level_requires_manage_catalog(self, client):
        maker = _login(client, MAKER)
        item_id, _, loc_id, _ = _seed_loc_item(client, maker)
        r = client.put(
            "/inventory/stock-levels",
            headers=_idem(maker),
            json={"location_id": loc_id, "item_id": item_id, "min_qty": "10"},
        )
        assert r.status_code == 403, r.text

    def test_put_and_list_low_stock(self, client):
        mgr = _login(client, MANAGER)
        item_id, sku, loc_id, loc_code = _seed_loc_item(client, mgr)

        r = client.put(
            "/inventory/stock-levels",
            headers=_idem(mgr),
            json={
                "location_id": loc_id,
                "item_id": item_id,
                "min_qty": "999999",
                "max_qty": "9999999",
            },
        )
        assert r.status_code in (200, 201), r.text
        body = r.json()
        assert body["min_qty"] == "999999"

        low = client.get("/inventory/low-stock", headers=mgr)
        assert low.status_code == 200, low.text
        rows = low.json()["items"]
        match = [x for x in rows if x["sku"] == sku and x["location_code"] == loc_code]
        assert match, f"thiếu cảnh báo cho {sku}@{loc_code}: {rows!r}"
        assert match[0]["status"] in ("low", "empty")
        assert "suggested_action" in match[0]

    def test_max_must_be_gte_min(self, client):
        mgr = _login(client, MANAGER)
        item_id, _, loc_id, _ = _seed_loc_item(client, mgr)
        r = client.put(
            "/inventory/stock-levels",
            headers=_idem(mgr),
            json={"location_id": loc_id, "item_id": item_id, "min_qty": "50", "max_qty": "10"},
        )
        assert r.status_code == 422, r.text


class TestStocktake:
    def _open(self, client, headers, loc_id):
        r = client.post(
            "/inventory/stocktakes",
            headers=_idem(headers),
            json={
                "location_id": loc_id,
                "note": "Kiểm kê định kỳ",
                # Ngày nghiệp vụ ngẫu nhiên: tránh va chạm guard
                # "1 ca đang mở / kho / ngày" với stocktake do test khác để lại.
                "business_date": (
                    date.today() + timedelta(days=uuid.uuid4().int % 300 + 1)
                ).isoformat(),
            },
        )
        assert r.status_code in (200, 201), r.text
        return r.json()

    def test_stocktake_variance_creates_adjustment_request(self, client):
        mgr = _login(client, MANAGER)
        checker = _login(client, CHECKER)
        _, _, loc_id, _ = _seed_loc_item(client, mgr)

        st = self._open(client, mgr, loc_id)
        st_id = st["id"]
        assert st["status"] == "open"

        items = client.get("/inventory/items", headers=mgr).json()["items"]
        item = next(i for i in items if not i.get("tracked_serial"))

        r = client.put(
            f"/inventory/stocktakes/{st_id}/lines",
            headers=_idem(mgr),
            json={"lines": [{"item_id": item["id"], "counted_qty": "1"}]},
        )
        assert r.status_code == 200, r.text
        assert r.json()["lines"], "phải trả về chênh lệch book/counted"

        r = client.post(f"/inventory/stocktakes/{st_id}/submit", headers=_idem(mgr))
        assert r.status_code == 200, r.text
        assert r.json()["status"] == "submitted"

        # Maker không được tự duyệt đợt kiểm kê của mình.
        r = client.post(f"/inventory/stocktakes/{st_id}/approve", headers=_idem(mgr))
        assert r.status_code == 403, r.text

        r = client.post(f"/inventory/stocktakes/{st_id}/approve", headers=_idem(checker))
        assert r.status_code == 200, r.text
        body = r.json()
        assert body["status"] == "closed"
        assert body.get("adjustment_request_id"), (
            "duyệt kiểm kê có chênh lệch phải sinh phiếu adjustment"
        )

        # A different idempotency key cannot create a second final decision or
        # a second adjustment request once the stocktake row is closed.
        replay = client.post(
            f"/inventory/stocktakes/{st_id}/approve", headers=_idem(checker)
        )
        assert replay.status_code == 409, replay.text

        async def stocktake_evidence():
            from app.database import AsyncSessionLocal
            from app.models.activity import AuditEvent, OutboxEvent
            from app.models.approval import ApprovalDecision

            async with AsyncSessionLocal() as db:
                decisions = (
                    await db.execute(
                        select(ApprovalDecision).where(
                            ApprovalDecision.subject_type == "inventory_stocktake",
                            ApprovalDecision.subject_id == uuid.UUID(st_id),
                        )
                    )
                ).scalars().all()
                audits = (
                    await db.execute(
                        select(AuditEvent).where(
                            AuditEvent.subject == f"inventory_stocktake:{st_id}",
                            AuditEvent.action == "inventory.stocktake.approved",
                        )
                    )
                ).scalars().all()
                outbox = (
                    await db.execute(
                        select(OutboxEvent).where(
                            OutboxEvent.aggregate_id == st_id,
                            OutboxEvent.event_type == "inventory.stocktake.approved",
                        )
                    )
                ).scalars().all()
                return decisions, audits, outbox

        decisions, audits, outbox = asyncio.run(stocktake_evidence())
        assert len(decisions) == len(audits) == len(outbox) == 1
        assert decisions[0].decision == "approved"

    def test_stocktake_shortage_creates_negative_adjustment(self, client):
        """A count below book stock must post a reducing adjustment, never a receipt."""
        mgr = _login(client, MANAGER)
        checker = _login(client, CHECKER)
        all_balances = client.get("/inventory/balances", headers=mgr).json()["balances"]
        positive = next((b for b in all_balances if float(b.get("quantity", 0)) > 1.0), None)
        if positive:
            loc_id = positive["location_id"]
            item_id = positive["item_id"]
            balance = positive
        else:
            item_id, _, loc_id, _ = _seed_loc_item(client, mgr)
            req = client.post(
                "/inventory/requests",
                headers=_idem(mgr),
                json={
                    "kind": "receipt",
                    "destination_location_id": loc_id,
                    "reason": "Seed stock for shortage test",
                    "lines": [{"item_id": item_id, "quantity": "100"}],
                },
            ).json()
            client.post(f"/inventory/requests/{req['id']}/submit", headers=_idem(mgr))
            client.post(f"/inventory/requests/{req['id']}/approve", headers=_idem(checker))
            balance = client.get(
                "/inventory/balances",
                headers=mgr,
                params={"location_id": loc_id, "item_id": item_id},
            ).json()["balances"][0]
        assert float(balance["quantity"]) > 0

        st_id = self._open(client, mgr, loc_id)["id"]
        counted_qty = float(balance["quantity"]) - 1.0
        r = client.put(
            f"/inventory/stocktakes/{st_id}/lines",
            headers=_idem(mgr),
            json={"lines": [{"item_id": item_id, "counted_qty": str(counted_qty)}]},
        )
        assert r.status_code == 200, r.text
        matched = [line for line in r.json()["lines"] if line["item_id"] == item_id]
        assert matched, "dòng kiểm kê của item phải tồn tại trong response"
        assert float(matched[0]["variance"]) < 0
        assert client.post(f"/inventory/stocktakes/{st_id}/submit", headers=_idem(mgr)).status_code == 200

        approved = client.post(f"/inventory/stocktakes/{st_id}/approve", headers=_idem(checker))
        assert approved.status_code == 200, approved.text
        adjustment_id = approved.json()["adjustment_request_id"]
        adjustment = client.get(f"/inventory/requests/{adjustment_id}", headers=checker)
        assert adjustment.status_code == 200, adjustment.text
        # Inventory request lines remain positive by schema.  The explicit
        # direction carries the reducing effect through to posting.
        assert float(adjustment.json()["lines"][0]["quantity"]) > 0
        assert adjustment.json()["lines"][0]["direction"] == "decrease"

        # The accepting checker can post this small adjustment without a
        # supervisor PIN.  The persisted balance must go down, not up.
        posted = client.post(
            f"/inventory/requests/{adjustment_id}/approve", headers=_idem(checker)
        )
        assert posted.status_code == 200, posted.text
        after = client.get(
            "/inventory/balances",
            headers=checker,
            params={"location_id": loc_id, "item_id": item_id},
        ).json()["balances"][0]
        assert float(after["quantity"]) == counted_qty

    def test_only_stocktake_maker_can_change_or_submit_open_stocktake(self, client):
        maker = _login(client, MAKER)
        admin = _login(client, MANAGER)
        item_id, _, loc_id, _ = _seed_loc_item(client, maker)
        st_id = self._open(client, maker, loc_id)["id"]

        changed = client.put(
            f"/inventory/stocktakes/{st_id}/lines",
            headers=_idem(admin),
            json={"lines": [{"item_id": item_id, "counted_qty": "0"}]},
        )
        assert changed.status_code == 403, changed.text
        submitted = client.post(f"/inventory/stocktakes/{st_id}/submit", headers=_idem(admin))
        assert submitted.status_code == 403, submitted.text

        changed = client.put(
            f"/inventory/stocktakes/{st_id}/lines",
            headers=_idem(maker),
            json={"lines": [{"item_id": item_id, "counted_qty": "0"}]},
        )
        assert changed.status_code == 200, changed.text
        submitted = client.post(f"/inventory/stocktakes/{st_id}/submit", headers=_idem(maker))
        assert submitted.status_code == 200, submitted.text

    def test_concurrent_stocktake_line_edit_and_submit_preserve_immutable_evidence(self, client):
        """The parent-row lock serializes an edit with submit; submitted evidence stays frozen."""
        maker = _login(client, MAKER)
        item_id, _, loc_id, _ = _seed_loc_item(client, maker)
        st_id = self._open(client, maker, loc_id)["id"]

        with ThreadPoolExecutor(max_workers=2) as executor:
            edit, submit = list(
                executor.map(
                    lambda operation: (
                        client.put(
                            f"/inventory/stocktakes/{st_id}/lines",
                            headers=_idem(maker),
                            json={"lines": [{"item_id": item_id, "counted_qty": "1"}]},
                        )
                        if operation == "edit"
                        else client.post(
                            f"/inventory/stocktakes/{st_id}/submit", headers=_idem(maker)
                        )
                    ),
                    ("edit", "submit"),
                )
            )

        assert submit.status_code == 200, submit.text
        assert edit.status_code in (200, 409), edit.text
        if edit.status_code == 409:
            # Theo contract kiểm kê, mọi PUT sau khi ca không còn open phải
            # dùng mã chuyên biệt STOCKTAKE_LOCKED, kể cả khi submit vừa xảy
            # ra song song với thao tác sửa.
            assert edit.json()["error"]["code"] == "STOCKTAKE_LOCKED"

        frozen = client.get(f"/inventory/stocktakes/{st_id}", headers=maker)
        assert frozen.status_code == 200, frozen.text
        assert frozen.json()["status"] == "submitted"
        rejected_edit = client.put(
            f"/inventory/stocktakes/{st_id}/lines",
            headers=_idem(maker),
            json={"lines": [{"item_id": item_id, "counted_qty": "999"}]},
        )
        assert rejected_edit.status_code == 409, rejected_edit.text
        assert rejected_edit.json()["error"]["code"] == "STOCKTAKE_LOCKED"


def test_legacy_stock_level_module_reexports_canonical_models():
    """Avoid a second SQLAlchemy mapping for the same inventory tables."""
    from app.models.inventory import StockLevel, Stocktake, StocktakeLine
    from app.models.stock_level import (
        StockLevel as LegacyStockLevel,
    )
    from app.models.stock_level import (
        Stocktake as LegacyStocktake,
    )
    from app.models.stock_level import (
        StocktakeLine as LegacyStocktakeLine,
    )

    assert LegacyStockLevel is StockLevel
    assert LegacyStocktake is Stocktake
    assert LegacyStocktakeLine is StocktakeLine


def test_stocktake_timestamp_repair_migration_exists():
    migration = (
        Path(__file__).resolve().parents[1]
        / "alembic/versions/010_stocktake_updated_at.py"
    )
    assert migration.exists()
    source = migration.read_text()
    assert "op.add_column" in source
    assert "inv_stocktakes" in source
    assert "updated_at" in source


def test_adjustment_direction_migration_fits_alembic_version_column():
    """Postgres stores migration IDs in VARCHAR(32) in the initial schema."""
    migration = (
        Path(__file__).resolve().parents[1]
        / "alembic/versions/011_inventory_adjustment_direction.py"
    )
    namespace: dict[str, object] = {}
    exec(migration.read_text(), namespace)
    revision = namespace["revision"]
    assert isinstance(revision, str)
    assert len(revision) <= 32


def test_stocktake_submitted_appears_in_approval_inbox_and_can_be_rejected(client):
    maker = _login(client, MAKER)
    checker = _login(client, CHECKER)
    item_id, _, loc_id, _ = _seed_loc_item(client, maker)

    _opened, st_id = open_shift(client, _idem(maker), loc_id)

    # Submit stocktake
    sub = client.post(f"/inventory/stocktakes/{st_id}/submit", headers=_idem(maker))
    assert sub.status_code == 200, sub.text

    # Verify stocktake appears in approval inbox
    inbox = client.get("/approvals/inbox", headers=checker)
    assert inbox.status_code == 200, inbox.text
    st_items = [i for i in inbox.json()["approvals"] if i["id"] == st_id]
    assert len(st_items) == 1
    assert st_items[0]["kind"] == "stocktake"

    # Reject stocktake
    rej = client.post(
        f"/inventory/stocktakes/{st_id}/reject",
        headers=_idem(checker),
        json={"reason": "Cần đếm lại bột sữa"},
    )
    assert rej.status_code == 200, rej.text
    assert rej.json()["status"] == "open"
    assert "Cần đếm lại bột sữa" in (rej.json().get("note") or "")


def test_inbound_receipt_approval_syncs_to_open_stocktake(client):
    maker = _login(client, MAKER)
    checker = _login(client, CHECKER)
    item_id, _, loc_id, _ = _seed_loc_item(client, maker)

    _opened, st_id = open_shift(client, _idem(maker), loc_id)

    seeded = client.get(f"/inventory/stocktakes/{st_id}", headers=maker).json()["lines"]
    target = next(stocktake_line for stocktake_line in seeded if stocktake_line["item_id"] == item_id)
    initial_received = float(target["received_qty"])
    opening = float(target["opening_qty"])

    # Create and approve an inbound receipt of 15 units
    req = client.post(
        "/inventory/requests",
        headers=_idem(maker),
        json={
            "kind": "receipt",
            "source_id": None,
            "dest_id": loc_id,
            "lines": [{"item_id": item_id, "quantity": "15"}],
            "reason": "Nhập kho trà test",
        },
    )
    assert req.status_code == 201, req.text
    req_id = req.json()["id"]

    # Submit request
    client.post(f"/inventory/requests/{req_id}/submit", headers=_idem(maker))

    # Approve request
    appr = client.post(f"/inventory/requests/{req_id}/approve", headers=_idem(checker))
    assert appr.status_code == 200, appr.text

    # Verify open stocktake line received_qty was automatically updated
    after = client.get(f"/inventory/stocktakes/{st_id}", headers=maker).json()["lines"]
    updated_line = next(stocktake_line for stocktake_line in after if stocktake_line["item_id"] == item_id)
    assert float(updated_line["received_qty"]) == initial_received + 15.0
    # theoretical_qty = opening + received - used
    expected_theo = opening + initial_received + 15.0 - float(updated_line["used_qty"])
    assert abs(float(updated_line["theoretical_qty"]) - expected_theo) < 1e-4


def test_inbound_receipt_double_approval_does_not_double_count_in_stocktake(client):
    maker = _login(client, MAKER)
    checker = _login(client, CHECKER)
    item_id, _, loc_id, _ = _seed_loc_item(client, maker)

    _opened, st_id = open_shift(client, _idem(maker), loc_id)

    seeded = client.get(f"/inventory/stocktakes/{st_id}", headers=maker).json()["lines"]
    target = next(stocktake_line for stocktake_line in seeded if stocktake_line["item_id"] == item_id)
    initial_received = float(target["received_qty"])

    # Create inbound receipt
    req = client.post(
        "/inventory/requests",
        headers=_idem(maker),
        json={
            "kind": "receipt",
            "source_id": None,
            "dest_id": loc_id,
            "lines": [{"item_id": item_id, "quantity": "20"}],
            "reason": "Test duplicate approval",
        },
    )
    assert req.status_code == 201, req.text
    req_id = req.json()["id"]
    client.post(f"/inventory/requests/{req_id}/submit", headers=_idem(maker))

    # Approve 1st time
    first_idem = str(uuid.uuid4())
    headers_first = {**checker, "Idempotency-Key": first_idem}
    appr1 = client.post(f"/inventory/requests/{req_id}/approve", headers=headers_first)
    assert appr1.status_code == 200, appr1.text

    # Approve 2nd time with SAME idempotency key (replay cache)
    appr_replay = client.post(f"/inventory/requests/{req_id}/approve", headers=headers_first)
    assert appr_replay.status_code == 200

    # Approve 2nd time with NEW idempotency key (conflict)
    appr_conflict = client.post(f"/inventory/requests/{req_id}/approve", headers=_idem(checker))
    assert appr_conflict.status_code == 409
    assert appr_conflict.json()["error"]["code"] == "STATE_CONFLICT"

    # Verify received_qty is strictly initial + 20 (not 40 or 60)
    lines_after = client.get(f"/inventory/stocktakes/{st_id}", headers=maker).json()["lines"]
    line = next(stocktake_line for stocktake_line in lines_after if stocktake_line["item_id"] == item_id)
    assert float(line["received_qty"]) == initial_received + 20.0


def test_stocktake_reject_only_valid_when_submitted(client):
    maker = _login(client, MAKER)
    checker = _login(client, CHECKER)
    item_id, _, loc_id, _ = _seed_loc_item(client, maker)

    _opened, st_id = open_shift(client, _idem(maker), loc_id)

    # Reject while 'open' must fail with 409 STATE_CONFLICT
    rej_open = client.post(
        f"/inventory/stocktakes/{st_id}/reject",
        headers=_idem(checker),
        json={"reason": "Chưa nộp mà đã reject"},
    )
    assert rej_open.status_code == 409, rej_open.text
    assert rej_open.json()["error"]["code"] == "STATE_CONFLICT"

    # Submit stocktake
    sub = client.post(f"/inventory/stocktakes/{st_id}/submit", headers=_idem(maker))
    assert sub.status_code == 200, sub.text

    # Approve stocktake to 'closed'
    appr = client.post(f"/inventory/stocktakes/{st_id}/approve", headers=_idem(checker))
    assert appr.status_code == 200, appr.text

    # Reject while 'closed' must fail with 409 STATE_CONFLICT
    rej_closed = client.post(
        f"/inventory/stocktakes/{st_id}/reject",
        headers=_idem(checker),
        json={"reason": "Đã chốt xong không thể reject"},
    )
    assert rej_closed.status_code == 409, rej_closed.text
    assert rej_closed.json()["error"]["code"] == "STATE_CONFLICT"


def test_stocktake_reject_forbidden_for_shift_staff(client):
    maker = _login(client, MAKER)
    item_id, _, loc_id, _ = _seed_loc_item(client, maker)

    _opened, st_id = open_shift(client, _idem(maker), loc_id)

    # Submit stocktake
    sub = client.post(f"/inventory/stocktakes/{st_id}/submit", headers=_idem(maker))
    assert sub.status_code == 200, sub.text

    # 1. Other staff (NOT maker, NO approval role) calls reject -> must be 403 FORBIDDEN
    other_staff = _login(client, "staff_afternoon")
    rej_other = client.post(
        f"/inventory/stocktakes/{st_id}/reject",
        headers=_idem(other_staff),
        json={"reason": "Nhân viên khác gọi reject"},
    )
    assert rej_other.status_code == 403, rej_other.text
    assert rej_other.json()["error"]["code"] == "FORBIDDEN"

    # 2. Shift staff (maker) calls reject -> must be 403
    rej_staff = client.post(
        f"/inventory/stocktakes/{st_id}/reject",
        headers=_idem(maker),
        json={"reason": "Nhân viên tự reject"},
    )
    assert rej_staff.status_code == 403, rej_staff.text
    error_code = rej_staff.json()["error"]["code"]
    assert error_code in ("FORBIDDEN", "SELF_APPROVAL_FORBIDDEN")


