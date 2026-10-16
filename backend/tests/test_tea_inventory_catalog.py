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


def test_manager_can_delete_unused_item(client):
    """Deleting an item with zero balances and no transaction history performs safe cleanup and frees SKU."""
    sku = f"DEL-TEST-{uuid.uuid4().hex[:8]}"
    create_resp = client.post(
        "/inventory/items",
        headers=_manager_headers(client),
        json={
            "sku": sku,
            "name": "Mặt hàng test xóa",
            "unit": "Hộp",
            "category": "Nhóm Khác",
        },
    )
    assert create_resp.status_code == 201
    item_id = create_resp.json()["id"]

    # Delete the item
    del_resp = client.delete(
        f"/inventory/items/{item_id}",
        headers=_manager_headers(client),
    )
    assert del_resp.status_code == 200, del_resp.text
    assert del_resp.json()["status"] == "deleted"

    # Verify not listed in active catalog
    listed = client.get("/inventory/items", headers=_manager_headers(client))
    assert listed.status_code == 200
    assert not any(i["id"] == item_id for i in listed.json()["items"])

    # Verify we can re-create with the same SKU without duplicate error
    recreate_resp = client.post(
        "/inventory/items",
        headers=_manager_headers(client),
        json={
            "sku": sku,
            "name": "Mặt hàng tái tạo",
            "unit": "Hộp",
            "category": "Nhóm Khác",
        },
    )
    assert recreate_resp.status_code in (200, 201), recreate_resp.text


def test_manager_can_batch_delete_items(client):
    """Batch delete endpoint can remove multiple items in a single atomic request."""
    sku1 = f"DEL-BATCH1-{uuid.uuid4().hex[:8]}"
    sku2 = f"DEL-BATCH2-{uuid.uuid4().hex[:8]}"

    r1 = client.post(
        "/inventory/items",
        headers=_manager_headers(client),
        json={"sku": sku1, "name": "Món xóa 1", "unit": "Gói"},
    )
    r2 = client.post(
        "/inventory/items",
        headers=_manager_headers(client),
        json={"sku": sku2, "name": "Món xóa 2", "unit": "Gói"},
    )
    id1 = r1.json()["id"]
    id2 = r2.json()["id"]

    batch_del_resp = client.post(
        "/inventory/items/batch-delete",
        headers=_manager_headers(client),
        json={"item_ids": [id1, id2]},
    )
    assert batch_del_resp.status_code == 200, batch_del_resp.text
    data = batch_del_resp.json()
    assert data["deleted_count"] == 2
    assert id1 in data["deleted_ids"]
    assert id2 in data["deleted_ids"]

    # Verify items are gone from active list
    listed = client.get("/inventory/items", headers=_manager_headers(client))
    active_ids = {i["id"] for i in listed.json()["items"]}
    assert id1 not in active_ids
    assert id2 not in active_ids


def test_delete_item_with_stock_and_movements_deactivates_and_clears_balance(client):
    """Deleting an item with stock balance clears balances and safely deactivates the item."""
    sku = f"STOCK-ITEM-{uuid.uuid4().hex[:8]}"
    create_resp = client.post(
        "/inventory/items",
        headers=_manager_headers(client),
        json={"sku": sku, "name": "Món còn tồn kho", "unit": "kg"},
    )
    assert create_resp.status_code == 201
    item_id = create_resp.json()["id"]

    # Get a location
    locs_resp = client.get("/inventory/locations", headers=_manager_headers(client))
    assert locs_resp.status_code == 200
    loc_id = locs_resp.json()["locations"][0]["id"]

    # Create a receipt request with stock
    req_resp = client.post(
        "/inventory/requests",
        headers={**_manager_headers(client), "Idempotency-Key": str(uuid.uuid4())},
        json={
            "kind": "receipt",
            "dest_id": loc_id,
            "reason": "Nhập kho ban đầu",
            "lines": [{"item_id": item_id, "quantity": "10.000"}],
        },
    )
    assert req_resp.status_code in (200, 201), req_resp.text
    req_id = req_resp.json()["id"]

    # Submit request
    client.post(
        f"/inventory/requests/{req_id}/submit",
        headers=_manager_headers(client),
    )

    # Login as checker and approve
    checker_resp = client.post(
        "/auth/login",
        data={"username": "demo_checker", "password": DEMO_PASSWORD},
    )
    checker_headers = {
        "Authorization": f"Bearer {checker_resp.json()['access_token']}",
        "Idempotency-Key": str(uuid.uuid4()),
    }
    app_resp = client.post(
        f"/inventory/requests/{req_id}/approve",
        headers=checker_headers,
    )
    assert app_resp.status_code == 200, app_resp.text

    # Delete the item -> succeeds, clears balance, and deactivates (soft delete)
    del_resp = client.delete(
        f"/inventory/items/{item_id}",
        headers=_manager_headers(client),
    )
    assert del_resp.status_code == 200, del_resp.text
    assert del_resp.json()["status"] == "deleted"
    assert del_resp.json()["mode"] == "soft_deleted"

    # Verify not listed in active catalog
    listed = client.get("/inventory/items", headers=_manager_headers(client))
    assert listed.status_code == 200
    assert not any(i["id"] == item_id for i in listed.json()["items"])

    # Verify balance is cleared
    bals = client.get("/inventory/balances", headers=_manager_headers(client))
    assert bals.status_code == 200
    assert not any(b.get("item_id") == item_id for b in bals.json().get("balances", []))



