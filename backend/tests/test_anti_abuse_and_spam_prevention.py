"""Tests for Anti-Abuse, Spam Prevention, Batch Caps, and Maker-Checker Governance."""
from __future__ import annotations

import uuid

DEMO_PASSWORD = "DemoPass123!"


def _login(client, username: str) -> dict[str, str]:
    r = client.post("/auth/login", data={"username": username, "password": DEMO_PASSWORD})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def _idem(headers: dict[str, str]) -> dict[str, str]:
    return {**headers, "Idempotency-Key": str(uuid.uuid4())}


class TestAntiAbuseAndSpamPrevention:
    def test_staff_cannot_create_catalog_item(self, client):
        """Staff (maker/teller) cannot add items to the catalog -> 403 Forbidden."""
        maker_auth = _login(client, "demo_maker")
        r = client.post(
            "/inventory/items",
            headers=_idem(maker_auth),
            json={
                "sku": f"SPAM_{uuid.uuid4().hex[:6].upper()}",
                "name": "Nguyên liệu spam trái phép",
                "unit": "kg",
            },
        )
        assert r.status_code == 403, r.text

    def test_staff_cannot_batch_create_catalog_items(self, client):
        """Staff cannot mass-import catalog items via batch -> 403 Forbidden."""
        maker_auth = _login(client, "demo_maker")
        r = client.post(
            "/inventory/items/batch",
            headers=_idem(maker_auth),
            json={
                "items": [
                    {"sku": f"SPAM_{i}", "name": f"Item {i}", "unit": "kg"}
                    for i in range(5)
                ]
            },
        )
        assert r.status_code == 403, r.text

    def test_duplicate_sku_is_rejected(self, client):
        """Cannot flood catalog with duplicate SKUs -> 409 DUPLICATE_SKU."""
        admin_auth = _login(client, "demo_admin")
        sku = f"TEA_{uuid.uuid4().hex[:8].upper()}"
        r1 = client.post(
            "/inventory/items",
            headers=_idem(admin_auth),
            json={"sku": sku, "name": "Trà Xanh Oolong Đặc Biệt", "unit": "kg"},
        )
        assert r1.status_code == 201, r1.text

        r2 = client.post(
            "/inventory/items",
            headers=_idem(admin_auth),
            json={"sku": sku, "name": "Trà Xanh Trùng Lặp", "unit": "kg"},
        )
        assert r2.status_code == 409, r2.text
        assert "DUPLICATE_SKU" in r2.text

    def test_batch_items_size_cap_enforced(self, client):
        """Flooding batch API with > 100 items is immediately rejected -> 422 BATCH_TOO_LARGE."""
        admin_auth = _login(client, "demo_admin")
        huge_batch = [
            {"sku": f"OVERFLOW_{i}", "name": f"Hàng hoá {i}", "unit": "hộp"}
            for i in range(105)
        ]
        r = client.post(
            "/inventory/items/batch",
            headers=_idem(admin_auth),
            json={"items": huge_batch},
        )
        assert r.status_code == 422, r.text
        assert "BATCH_TOO_LARGE" in r.text

    def test_maker_cannot_self_approve_request(self, client):
        """Maker cannot approve their own inventory request -> 403 SELF_APPROVAL_FORBIDDEN."""
        admin_auth = _login(client, "demo_admin")
        locs = client.get("/inventory/locations", headers=admin_auth).json()["locations"]
        items = client.get("/inventory/items", headers=admin_auth).json()["items"]
        item = next(i for i in items if not i.get("tracked_serial"))

        req = client.post(
            "/inventory/requests",
            headers=_idem(admin_auth),
            json={
                "kind": "receipt",
                "destination_location_id": locs[0]["id"],
                "reason": "Nhập kho thử nghiệm",
                "lines": [{"item_id": item["id"], "quantity": "10"}],
            },
        ).json()

        # Submit
        sub = client.post(f"/inventory/requests/{req['id']}/submit", headers=_idem(admin_auth))
        assert sub.status_code == 200

        # Self-approval forbidden
        appr = client.post(f"/inventory/requests/{req['id']}/approve", headers=_idem(admin_auth))
        assert appr.status_code == 403, appr.text
        assert "SELF_APPROVAL_FORBIDDEN" in appr.text

    def test_idempotency_prevents_duplicate_requests(self, client):
        """Sending the exact same mutation with the same Idempotency-Key replays without duplicates."""
        admin_auth = _login(client, "demo_admin")
        locs = client.get("/inventory/locations", headers=admin_auth).json()["locations"]
        items = client.get("/inventory/items", headers=admin_auth).json()["items"]
        item = next(i for i in items if not i.get("tracked_serial"))

        fixed_key = str(uuid.uuid4())
        headers = {**admin_auth, "Idempotency-Key": fixed_key}
        payload = {
            "kind": "receipt",
            "destination_location_id": locs[0]["id"],
            "reason": "Nhập kho Idempotency Test",
            "lines": [{"item_id": item["id"], "quantity": "5"}],
        }

        r1 = client.post("/inventory/requests", headers=headers, json=payload)
        assert r1.status_code == 201
        req_id_1 = r1.json()["id"]

        # Re-send same request with same key
        r2 = client.post("/inventory/requests", headers=headers, json=payload)
        assert r2.status_code == 201
        req_id_2 = r2.json()["id"]

        assert req_id_1 == req_id_2, "Idempotent replay must return the exact same request ID"
