"""Tests for reserved inventory, return for rework, and asset handover lifecycle."""
from __future__ import annotations

import asyncio
import uuid
from concurrent.futures import ThreadPoolExecutor

import pytest
from sqlalchemy import text

DEMO_PASSWORD = "DemoPass123!"


def _login(client, username: str) -> dict[str, str]:
    r = client.post("/auth/login", data={"username": username, "password": DEMO_PASSWORD})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def _idem(headers: dict[str, str]) -> dict[str, str]:
    return {**headers, "Idempotency-Key": str(uuid.uuid4())}


@pytest.fixture(autouse=True)
def reset_balances_fixture():
    import asyncio

    from sqlalchemy import text

    from app.database import AsyncSessionLocal

    async def _reset():
        async with AsyncSessionLocal() as db:
            await db.execute(
                text(
                    "UPDATE inv_balances SET reserved_quantity = 0, quantity = 500 "
                    "WHERE location_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1' "
                    "AND item_id = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1'"
                )
            )
            await db.commit()

    asyncio.run(_reset())
    yield


def test_reserved_inventory_and_return_lifecycle(client):
    headers_maker = _login(client, "demo_maker")
    headers_checker = _login(client, "demo_checker")

    # 1. Check initial balance
    res_bals = client.get(
        "/inventory/balances",
        headers=headers_maker,
        params={
            "location_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1",
            "item_id": "cccccccc-cccc-4ccc-8ccc-ccccccccccc1",
        },
    )
    assert res_bals.status_code == 200
    bals = res_bals.json()["balances"]
    assert len(bals) > 0
    init_qty = float(bals[0]["quantity"])
    init_reserved = float(bals[0]["reserved_quantity"])
    init_avail = float(bals[0]["available_quantity"])
    assert init_avail == max(0.0, init_qty - init_reserved)

    # 2. Maker creates an issue request of 5 units
    res_create = client.post(
        "/inventory/requests",
        headers={**headers_maker, "Idempotency-Key": str(uuid.uuid4())},
        json={
            "kind": "issue",
            "source_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1",
            "reason": "Xuất thử nghiệm đặt trước tồn kho",
            "lines": [
                {
                    "item_id": "cccccccc-cccc-4ccc-8ccc-ccccccccccc1",
                    "quantity": "5.000",
                }
            ],
        },
    )
    assert res_create.status_code in (200, 201)
    req_id = res_create.json()["id"]

    # 3. Maker submits the request -> reserved_quantity increases by 5
    res_sub = client.post(
        f"/inventory/requests/{req_id}/submit",
        headers=headers_maker,
    )
    assert res_sub.status_code == 200
    assert res_sub.json()["status"] == "submitted"

    res_bals_after_sub = client.get(
        "/inventory/balances",
        headers=headers_maker,
        params={
            "location_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1",
            "item_id": "cccccccc-cccc-4ccc-8ccc-ccccccccccc1",
        },
    )
    bals_sub = res_bals_after_sub.json()["balances"][0]
    assert float(bals_sub["reserved_quantity"]) == init_reserved + 5.0

    # 4. Invariant: Maker cannot return their own request
    res_self_return = client.post(
        f"/inventory/requests/{req_id}/return",
        headers=headers_maker,
        json={"reason": "Tự trả về"},
    )
    assert res_self_return.status_code == 403

    # 5. Checker returns request for rework
    res_return = client.post(
        f"/inventory/requests/{req_id}/return",
        headers=headers_checker,
        json={"reason": "Thiếu chữ ký phụ lục chứng từ"},
    )
    assert res_return.status_code == 200
    ret_body = res_return.json()
    assert ret_body["status"] == "returned"
    assert ret_body["return_reason"] == "Thiếu chữ ký phụ lục chứng từ"

    # Reservation is released upon return
    res_bals_after_ret = client.get(
        "/inventory/balances",
        headers=headers_maker,
        params={
            "location_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1",
            "item_id": "cccccccc-cccc-4ccc-8ccc-ccccccccccc1",
        },
    )
    bals_ret = res_bals_after_ret.json()["balances"][0]
    assert float(bals_ret["reserved_quantity"]) == init_reserved

    # 6. Maker resubmits from returned status
    res_resub = client.post(
        f"/inventory/requests/{req_id}/submit",
        headers=headers_maker,
    )
    assert res_resub.status_code == 200
    assert res_resub.json()["status"] == "submitted"

    # 7. Checker approves request
    res_app = client.post(
        f"/inventory/requests/{req_id}/approve",
        headers={**headers_checker, "Idempotency-Key": str(uuid.uuid4())},
    )
    assert res_app.status_code == 200
    assert res_app.json()["status"] == "posted"

    # Final balance: quantity decreased by 5, reserved decreased back to initial
    res_bals_final = client.get(
        "/inventory/balances",
        headers=headers_maker,
        params={
            "location_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1",
            "item_id": "cccccccc-cccc-4ccc-8ccc-ccccccccccc1",
        },
    )
    bals_final = res_bals_final.json()["balances"][0]
    assert float(bals_final["quantity"]) == init_qty - 5.0
    assert float(bals_final["reserved_quantity"]) == init_reserved


def test_issue_submit_rejects_partial_reservation_and_keeps_draft_unreserved(client):
    maker = _login(client, "demo_maker")
    balance = client.get(
        "/inventory/balances",
        headers=maker,
        params={
            "location_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1",
            "item_id": "cccccccc-cccc-4ccc-8ccc-ccccccccccc1",
        },
    ).json()["balances"][0]
    total_qty = float(balance["quantity"])
    request = client.post(
        "/inventory/requests",
        headers={**maker, "Idempotency-Key": str(uuid.uuid4())},
        json={
            "kind": "issue",
            "source_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1",
            "reason": "Không được over-reserve",
            "lines": [{"item_id": "cccccccc-cccc-4ccc-8ccc-ccccccccccc1", "quantity": str(total_qty + 5000)}],
        },
    )
    assert request.status_code in (200, 201), request.text
    req_id = request.json()["id"]
    submitted = client.post(f"/inventory/requests/{req_id}/submit", headers=maker)
    assert submitted.status_code == 409, submitted.text
    assert submitted.json()["error"]["code"] == "INSUFFICIENT_STOCK"

    unchanged_request = client.get(f"/inventory/requests/{req_id}", headers=maker)
    assert unchanged_request.status_code == 200, unchanged_request.text
    assert unchanged_request.json()["status"] == "draft"
    unchanged_balance = client.get(
        "/inventory/balances",
        headers=maker,
        params={
            "location_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1",
            "item_id": "cccccccc-cccc-4ccc-8ccc-ccccccccccc1",
        },
    )
    assert unchanged_balance.status_code == 200, unchanged_balance.text
    assert float(unchanged_balance.json()["balances"][0]["reserved_quantity"]) == 0.0


def test_concurrent_issue_submits_reserve_one_full_request_only(client):
    """Two competing submissions must not leave either request partially reserved."""
    maker = _login(client, "demo_maker")
    payload = {
        "kind": "issue",
        "source_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1",
        "reason": "Concurrent full-reservation regression",
        "lines": [
            {
                "item_id": "cccccccc-cccc-4ccc-8ccc-ccccccccccc1",
                "quantity": "300",
            }
        ],
    }
    drafts = [
        client.post(
            "/inventory/requests",
            headers=_idem(maker),
            json=payload,
        )
        for _ in range(2)
    ]
    assert all(response.status_code == 201 for response in drafts)

    with ThreadPoolExecutor(max_workers=2) as executor:
        submissions = list(
            executor.map(
                lambda draft: client.post(
                    f"/inventory/requests/{draft.json()['id']}/submit", headers=maker
                ),
                drafts,
            )
        )

    assert sorted(response.status_code for response in submissions) == [200, 409]
    assert all(
        response.status_code != 409
        or response.json()["error"]["code"] == "INSUFFICIENT_STOCK"
        for response in submissions
    )
    balance = client.get(
        "/inventory/balances",
        headers=maker,
        params={
            "location_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1",
            "item_id": "cccccccc-cccc-4ccc-8ccc-ccccccccccc1",
        },
    )
    assert balance.status_code == 200, balance.text
    assert float(balance.json()["balances"][0]["reserved_quantity"]) == 300.0


def test_issue_approval_rejects_missing_full_reservation(client):
    """Approval must fail instead of consuming another request's reservation."""
    maker = _login(client, "demo_maker")
    checker = _login(client, "demo_checker")
    draft = client.post(
        "/inventory/requests",
        headers=_idem(maker),
        json={
            "kind": "issue",
            "source_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1",
            "reason": "Reservation integrity regression",
            "lines": [
                {
                    "item_id": "cccccccc-cccc-4ccc-8ccc-ccccccccccc1",
                    "quantity": "5",
                }
            ],
        },
    )
    assert draft.status_code == 201, draft.text
    request_id = draft.json()["id"]
    assert client.post(
        f"/inventory/requests/{request_id}/submit", headers=maker
    ).status_code == 200

    async def remove_one_reserved_unit() -> None:
        from app.database import AsyncSessionLocal

        async with AsyncSessionLocal() as db:
            await db.execute(
                text(
                    "UPDATE inv_balances SET reserved_quantity = 4 "
                    "WHERE location_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1' "
                    "AND item_id = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1'"
                )
            )
            await db.commit()

    asyncio.run(remove_one_reserved_unit())

    approval = client.post(
        f"/inventory/requests/{request_id}/approve", headers=_idem(checker)
    )
    assert approval.status_code == 409, approval.text
    assert approval.json()["error"]["code"] == "RESERVATION_MISMATCH"

    unchanged_request = client.get(f"/inventory/requests/{request_id}", headers=checker)
    assert unchanged_request.status_code == 200, unchanged_request.text
    assert unchanged_request.json()["status"] == "submitted"
    balance = client.get(
        "/inventory/balances",
        headers=checker,
        params={
            "location_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1",
            "item_id": "cccccccc-cccc-4ccc-8ccc-ccccccccccc1",
        },
    )
    assert balance.status_code == 200, balance.text
    assert float(balance.json()["balances"][0]["quantity"]) == 500.0
    assert float(balance.json()["balances"][0]["reserved_quantity"]) == 4.0


def test_cash_request_return_and_resubmit(client):
    headers_maker = _login(client, "demo_maker")
    headers_checker = _login(client, "demo_checker")

    # 1. Maker creates a cash request
    res_create = client.post(
        "/cash-sim/requests",
        headers={**headers_maker, "Idempotency-Key": str(uuid.uuid4())},
        json={
            "cashbox_id": "11111111-1111-4111-8111-111111111111",
            "kind": "payment",
            "amount": "1000000.00",
            "reason": "Chi tạm ứng công tác",
        },
    )
    assert res_create.status_code in (200, 201)
    req_id = res_create.json()["id"]

    # 2. Maker submits
    res_sub = client.post(
        f"/cash-sim/requests/{req_id}/submit",
        headers=headers_maker,
    )
    assert res_sub.status_code == 200
    assert res_sub.json()["status"] == "submitted"

    # 3. Checker returns for rework
    res_return = client.post(
        f"/cash-sim/requests/{req_id}/return",
        headers=headers_checker,
        json={"reason": "Bổ sung hoá đơn tài chính điện tử"},
    )
    assert res_return.status_code == 200
    assert res_return.json()["status"] == "returned"
    assert res_return.json()["return_reason"] == "Bổ sung hoá đơn tài chính điện tử"

    # 4. Maker can resubmit
    res_resub = client.post(
        f"/cash-sim/requests/{req_id}/submit",
        headers=headers_maker,
    )
    assert res_resub.status_code == 200
    assert res_resub.json()["status"] == "submitted"


def test_asset_history_and_handover(client):
    headers = _login(client, "demo_admin")
    unauthorized_headers = _login(client, "demo_approver2")

    # 1. Create a new tracked asset
    serial = f"TEST-CARD-{uuid.uuid4().hex[:8].upper()}"
    res_create = client.post(
        "/inventory/assets",
        headers={**headers, "Idempotency-Key": str(uuid.uuid4())},
        json={
            "item_id": "cccccccc-cccc-4ccc-8ccc-ccccccccccc1",
            "serial": serial,
            "location_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1",
            "status": "available",
        },
    )
    assert res_create.status_code in (200, 201)
    asset_id = res_create.json()["id"]

    forbidden = client.post(
        f"/inventory/assets/{asset_id}/handover",
        headers=_idem(unauthorized_headers),
        json={"to_assignee": "Không được bàn giao"},
    )
    assert forbidden.status_code == 403, forbidden.text

    # 2. View asset history -> should have initial creation log
    res_hist = client.get(f"/inventory/assets/{asset_id}/history", headers=headers)
    assert res_hist.status_code == 200
    data = res_hist.json()
    assert data["asset"]["serial"] == serial
    assert len(data["history"]) >= 1
    assert data["history"][0]["status_after"] == "available"

    # 3. Handover asset to another location / assignee
    res_handover = client.post(
        f"/inventory/assets/{asset_id}/handover",
        headers=_idem(headers),
        json={
            "to_location_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2",
            "to_assignee": "Giao dịch viên Quầy 1",
            "status": "in_use",
            "notes": "Bàn giao phôi thẻ cho quầy giao dịch số 1",
        },
    )
    assert res_handover.status_code == 200
    assert res_handover.json()["status"] == "in_use"
    assert res_handover.json()["assignee"] == "Giao dịch viên Quầy 1"

    # 4. Check history again -> now has 2 log entries
    res_hist2 = client.get(f"/inventory/assets/{asset_id}/history", headers=headers)
    assert res_hist2.status_code == 200
    assert len(res_hist2.json()["history"]) == 2
    latest = res_hist2.json()["history"][0]
    assert latest["status_before"] == "available"
    assert latest["status_after"] == "in_use"
    assert latest["to_assignee"] == "Giao dịch viên Quầy 1"
    assert "quầy giao dịch số 1" in latest["notes"]


def test_handover_validates_destination_and_lifecycle(client):
    """Custody moves must not create logs for unknown locations or made-up states."""
    admin = _login(client, "demo_admin")
    serial = f"TEST-HANDOVER-{uuid.uuid4().hex[:8].upper()}"
    created = client.post(
        "/inventory/assets",
        headers=_idem(admin),
        json={
            "item_id": "cccccccc-cccc-4ccc-8ccc-ccccccccccc2",
            "serial": serial,
            "location_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1",
            "status": "available",
        },
    )
    assert created.status_code == 201, created.text
    asset_id = created.json()["id"]

    unknown_destination = client.post(
        f"/inventory/assets/{asset_id}/handover",
        headers=_idem(admin),
        json={"to_location_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"},
    )
    assert unknown_destination.status_code == 404, unknown_destination.text
    assert unknown_destination.json()["error"]["code"] == "LOCATION_NOT_FOUND"

    invalid_status = client.post(
        f"/inventory/assets/{asset_id}/handover",
        headers=_idem(admin),
        json={"status": "teleported"},
    )
    assert invalid_status.status_code == 422, invalid_status.text
    assert invalid_status.json()["error"]["code"] == "INVALID_ASSET_STATUS"


def test_create_asset_rejects_blank_serial_and_unknown_lifecycle_status(client):
    """Invalid custody records must not enter the serial ledger at creation."""
    admin = _login(client, "demo_admin")
    base = {
        "item_id": "cccccccc-cccc-4ccc-8ccc-ccccccccccc1",
        "location_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1",
    }

    blank_serial = client.post(
        "/inventory/assets",
        headers=_idem(admin),
        json={**base, "serial": "   ", "status": "available"},
    )
    assert blank_serial.status_code == 422, blank_serial.text
    assert blank_serial.json()["error"]["code"] == "SERIAL_REQUIRED"

    invalid_status = client.post(
        "/inventory/assets",
        headers=_idem(admin),
        json={
            **base,
            "serial": f"TEST-SERIAL-STATUS-{uuid.uuid4().hex[:8].upper()}",
            "status": "teleported",
        },
    )
    assert invalid_status.status_code == 422, invalid_status.text
    assert invalid_status.json()["error"]["code"] == "INVALID_ASSET_STATUS"


def test_approve_rejects_serial_with_wrong_item_before_posting(client):
    """A serial is custody-bound to its item; a wrong request line cannot post stock."""
    admin = _login(client, "demo_admin")
    maker = _login(client, "demo_maker")
    checker = _login(client, "demo_checker")
    serial = f"TEST-SERIAL-ITEM-{uuid.uuid4().hex[:8].upper()}"
    created = client.post(
        "/inventory/assets",
        headers=_idem(admin),
        json={
            "item_id": "cccccccc-cccc-4ccc-8ccc-ccccccccccc2",
            "serial": serial,
            "location_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1",
            "status": "available",
        },
    )
    assert created.status_code == 201, created.text

    draft = client.post(
        "/inventory/requests",
        headers=_idem(maker),
        json={
            "kind": "issue",
            "source_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1",
            "reason": "Must reject mismatched serial item",
            "lines": [
                {
                    "item_id": "cccccccc-cccc-4ccc-8ccc-ccccccccccc1",
                    "quantity": "1",
                    "serial": serial,
                }
            ],
        },
    )
    assert draft.status_code == 201, draft.text
    request_id = draft.json()["id"]
    submitted = client.post(f"/inventory/requests/{request_id}/submit", headers=maker)
    assert submitted.status_code == 200, submitted.text

    approval = client.post(
        f"/inventory/requests/{request_id}/approve", headers=_idem(checker)
    )
    assert approval.status_code == 422, approval.text
    assert approval.json()["error"]["code"] == "SERIAL_ITEM_MISMATCH"

    unchanged = client.get(f"/inventory/requests/{request_id}", headers=checker)
    assert unchanged.status_code == 200, unchanged.text
    assert unchanged.json()["status"] == "submitted"


def test_approve_rejects_serial_that_is_not_available_for_issue(client):
    """An issued serial is locked and rejected before any stock movement posts."""
    admin = _login(client, "demo_admin")
    maker = _login(client, "demo_maker")
    checker = _login(client, "demo_checker")
    serial = f"TEST-SERIAL-ISSUED-{uuid.uuid4().hex[:8].upper()}"
    created = client.post(
        "/inventory/assets",
        headers=_idem(admin),
        json={
            "item_id": "cccccccc-cccc-4ccc-8ccc-ccccccccccc1",
            "serial": serial,
            "location_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1",
            "status": "issued",
        },
    )
    assert created.status_code == 201, created.text

    draft = client.post(
        "/inventory/requests",
        headers=_idem(maker),
        json={
            "kind": "issue",
            "source_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1",
            "reason": "Không được xuất lại serial đã cấp phát",
            "lines": [
                {
                    "item_id": "cccccccc-cccc-4ccc-8ccc-ccccccccccc1",
                    "quantity": "1",
                    "serial": serial,
                }
            ],
        },
    )
    assert draft.status_code == 201, draft.text
    request_id = draft.json()["id"]
    assert client.post(
        f"/inventory/requests/{request_id}/submit", headers=maker
    ).status_code == 200

    approval = client.post(
        f"/inventory/requests/{request_id}/approve", headers=_idem(checker)
    )
    assert approval.status_code == 422, approval.text
    assert approval.json()["error"]["code"] == "SERIAL_STATUS_INVALID"
