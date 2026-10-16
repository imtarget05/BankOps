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


def test_manager_can_batch_import_items(client):
    """A manager can import multiple catalog items in a single request, skipping duplicates."""
    sku_exist = f"TRA-EXIST-{uuid.uuid4().hex[:8]}"
    client.post(
        "/inventory/items",
        headers=_manager_headers(client),
        json={
            "sku": sku_exist,
            "name": "Trà đen lộc phát đã có",
            "unit": "Gói",
            "category": "Nhóm Trà",
            "packaging": "500g/gói",
            "tracked_serial": False,
        },
    )

    sku_new_1 = f"TRA-NEW1-{uuid.uuid4().hex[:8]}"
    sku_new_2 = f"TRA-NEW2-{uuid.uuid4().hex[:8]}"

    batch_resp = client.post(
        "/inventory/items/batch",
        headers=_manager_headers(client),
        json={
            "items": [
                {
                    "sku": sku_exist,
                    "name": "Trà đen lộc phát trùng",
                    "unit": "Gói",
                    "category": "Nhóm Trà",
                    "packaging": "500g/gói",
                },
                {
                    "sku": sku_new_1,
                    "name": "Trà nhài hoa cúc",
                    "unit": "Gói",
                    "category": "Nhóm Trà",
                    "packaging": "500g/gói",
                },
                {
                    "sku": sku_new_2,
                    "name": "Bột kem béo dừa",
                    "unit": "Túi",
                    "category": "Nhóm Bột & Sữa",
                    "packaging": "1kg/túi",
                },
            ]
        },
    )

    assert batch_resp.status_code == 201, batch_resp.text
    data = batch_resp.json()
    assert data["created_count"] == 2
    assert data["skipped_count"] == 1
    created_skus = [i["sku"] for i in data["items"]]
    assert sku_new_1.upper() in created_skus
    assert sku_new_2.upper() in created_skus

