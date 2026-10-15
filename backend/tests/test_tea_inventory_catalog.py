"""Catalog fields required by the milk-tea inventory specification."""
import uuid

DEMO_PASSWORD = "DemoPass123!"


def _manager_headers(client) -> dict[str, str]:
    response = client.post(
        "/auth/login",
        data={"username": "demo_admin", "password": DEMO_PASSWORD},
    )
    assert response.status_code == 200, response.text
    return {
        "Authorization": f"Bearer {response.json()['access_token']}",
        "Idempotency-Key": str(uuid.uuid4()),
    }


def test_manager_can_record_tea_ingredient_catalog_details(client):
    """A manager needs category and package specification, not serial tracking."""
    sku = f"TRA-O-LONG-{uuid.uuid4().hex[:8]}"
    response = client.post(
        "/inventory/items",
        headers=_manager_headers(client),
        json={
            "sku": sku,
            "name": "Trà ô long",
            "unit": "Gói",
            "category": "Nhóm Trà",
            "packaging": "500 g/gói",
            "tracked_serial": False,
        },
    )

    assert response.status_code == 201, response.text
    body = response.json()
    assert body["category"] == "Nhóm Trà"
    assert body["packaging"] == "500 g/gói"

    listed = client.get("/inventory/items", headers=_manager_headers(client))
    assert listed.status_code == 200, listed.text
    item = next(row for row in listed.json()["items"] if row["id"] == body["id"])
    assert item["category"] == "Nhóm Trà"
    assert item["packaging"] == "500 g/gói"
