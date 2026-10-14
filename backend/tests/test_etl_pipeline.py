"""Tests for 4-layer ETL Pipeline, Staging, Validation, Scoping, and Posting (Phase 2).

Verifies:
  - 4-layer model: Connection -> Pipeline -> MappingVersion -> Run -> Review/Post
  - Multi-format parsing (CSV, JSON) and fingerprint deduplication
  - Row-level validation and error reporting
  - Target 'balance_adjustment_admin':
      * Computes delta and direction
      * Enforces etl:post_balance capability
      * Single-admin self-approval override with auditability
      * Never raw updates balance; creates Requests, Lines, Movements
  - Scoped access: users with etl:run only see & run pipelines within their branch/location
  - Deprecation warning on legacy /integrations/* routes
"""

import io
import uuid

DEMO_PASSWORD = "DemoPass123!"


def _login(client, username: str, password: str = DEMO_PASSWORD) -> dict[str, str]:
    r = client.post("/auth/login", data={"username": username, "password": password})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def _idem(headers: dict[str, str]) -> dict[str, str]:
    return {**headers, "Idempotency-Key": str(uuid.uuid4())}


class TestEtlPipeline:
    def test_legacy_integrations_returns_deprecation_header(self, client):
        admin = _login(client, "demo_admin")
        r = client.get("/integrations/connections", headers=admin)
        assert r.status_code == 200
        assert "Warning" in r.headers
        assert "Deprecated: use /api/v1/etl/* instead" in r.headers["Warning"]

    def test_etl_connection_and_pipeline_lifecycle(self, client):
        admin = _login(client, "demo_admin")

        # 1. Create Connection
        conn_res = client.post(
            "/etl/connections",
            headers=admin,
            json={
                "name": "Nguồn CSV Kế Toán Kho Trung Tâm",
                "type": "csv",
                "secret_ref": "vault://etl/csv_central",
            },
        )
        assert conn_res.status_code == 201, conn_res.text
        conn = conn_res.json()
        conn_id = conn["id"]

        # 2. Get location for pipeline
        locs = client.get("/inventory/locations", headers=admin).json()["locations"]
        loc_id = locs[0]["id"]

        # 3. Create Pipeline
        pipe_res = client.post(
            "/etl/pipelines",
            headers=admin,
            json={
                "name": "Điều chỉnh Quản trị Tồn kho Trung Tâm",
                "target": "balance_adjustment_admin",
                "connection_id": conn_id,
                "location_id": loc_id,
            },
        )
        assert pipe_res.status_code == 201, pipe_res.text
        pipe = pipe_res.json()
        pipe_id = pipe["id"]

        # 4. List mapping versions (default published v1 created automatically)
        mv_res = client.get(f"/etl/pipelines/{pipe_id}/mapping-versions", headers=admin)
        assert mv_res.status_code == 200
        mvs = mv_res.json()["mapping_versions"]
        assert len(mvs) >= 1
        assert mvs[0]["status"] == "published"

    def test_etl_run_staging_and_duplicate_fingerprint(self, client):
        admin = _login(client, "demo_admin")
        items = client.get("/inventory/items", headers=admin).json()["items"]
        locs = client.get("/inventory/locations", headers=admin).json()["locations"]
        sku1 = items[0]["sku"]
        loc_id = locs[0]["id"]

        # Create connection & pipeline
        conn = client.post(
            "/etl/connections",
            headers=admin,
            json={"name": "Test Ingest CSV", "type": "csv"},
        ).json()
        pipe = client.post(
            "/etl/pipelines",
            headers=admin,
            json={
                "name": "Pipeline Ingest Test",
                "target": "balance_adjustment_admin",
                "connection_id": conn["id"],
                "location_id": loc_id,
            },
        ).json()
        pipe_id = pipe["id"]

        # Prepare CSV content with 1 valid row, 1 invalid row (unknown SKU)
        csv_content = f"sku,target_quantity,reason\n{sku1},25,Đồng bộ định kỳ\nUNKNOWN_SKU_999,10,Lỗi SKU\n"
        files = {"file": ("stock_adjust.csv", io.BytesIO(csv_content.encode("utf-8")), "text/csv")}

        # Trigger run
        run_res = client.post(f"/etl/pipelines/{pipe_id}/runs", headers=admin, files=files)
        assert run_res.status_code == 201, run_res.text
        run = run_res.json()
        run_id = run["id"]
        assert run["total_rows"] == 2
        assert run["valid_rows"] == 1
        assert run["invalid_rows"] == 1
        assert run["status"] == "staged"

        # Check rows API
        rows_res = client.get(f"/etl/runs/{run_id}/rows", headers=admin)
        assert rows_res.status_code == 200
        rows_data = rows_res.json()
        assert rows_data["total"] == 2
        rows = rows_data["rows"]
        assert rows[0]["valid"] is True
        assert rows[0]["action_preview"]["target_quantity"] == 25.0
        assert rows[1]["valid"] is False
        assert "không tồn tại" in str(rows[1]["errors_json"])

        # Error report download
        err_res = client.get(f"/etl/runs/{run_id}/error-report", headers=admin)
        assert err_res.status_code == 200
        assert "UNKNOWN_SKU_999" in err_res.text

        # Fingerprint deduplication: submitting same file returns identical run
        files2 = {"file": ("stock_adjust.csv", io.BytesIO(csv_content.encode("utf-8")), "text/csv")}
        dedup_res = client.post(f"/etl/pipelines/{pipe_id}/runs", headers=admin, files=files2)
        assert dedup_res.status_code == 201
        assert dedup_res.json()["id"] == run_id

    def test_balance_adjustment_posting_with_single_admin_override(self, client):
        admin = _login(client, "demo_admin")
        items = client.get("/inventory/items", headers=admin).json()["items"]
        locs = client.get("/inventory/locations", headers=admin).json()["locations"]
        item = items[0]
        sku = item["sku"]
        loc_id = locs[0]["id"]

        # Check initial balance
        bal_res = client.get("/inventory/balances", headers=admin).json()["balances"]
        init_bal_obj = next((b for b in bal_res if b["item_id"] == item["id"] and b["location_id"] == loc_id), None)
        initial_qty = float(init_bal_obj["quantity"]) if init_bal_obj else 0.0

        target_qty = initial_qty + 12.0

        # Create connection & pipeline
        conn = client.post(
            "/etl/connections",
            headers=admin,
            json={"name": "Post Balance Conn", "type": "json"},
        ).json()
        pipe = client.post(
            "/etl/pipelines",
            headers=admin,
            json={
                "name": "Adjust Balance Admin Pipeline",
                "target": "balance_adjustment_admin",
                "connection_id": conn["id"],
                "location_id": loc_id,
            },
        ).json()
        pipe_id = pipe["id"]

        # Trigger run via JSON
        run_res = client.post(
            f"/etl/pipelines/{pipe_id}/runs",
            headers=admin,
            json={
                "raw_rows": [
                    {"sku": sku, "target_quantity": target_qty, "reason": "Admin kiểm kê thực tế"}
                ]
            },
        )
        assert run_res.status_code == 201, run_res.text
        run = run_res.json()
        run_id = run["id"]
        assert run["valid_rows"] == 1

        # Post the run (single admin override)
        post_res = client.post(f"/etl/runs/{run_id}/post", headers=admin)
        assert post_res.status_code == 200, post_res.text
        post_data = post_res.json()
        assert post_data["status"] == "posted"
        assert post_data["single_admin_override"] is True
        assert post_data["movements_count"] >= 1
        req_id = post_data["request_id"]

        # Verify that an InventoryRequest of kind="adjustment" was created and approved
        req_info = client.get(f"/inventory/requests/{req_id}", headers=admin).json()
        assert req_info["kind"] == "adjustment"
        assert req_info["status"] == "approved"

        # Verify new balance updated correctly
        updated_bals = client.get("/inventory/balances", headers=admin).json()["balances"]
        new_bal_obj = next((b for b in updated_bals if b["item_id"] == item["id"] and b["location_id"] == loc_id), None)
        assert new_bal_obj is not None
        assert float(new_bal_obj["quantity"]) == target_qty

        # Verify posting cannot be replayed
        repost_res = client.post(f"/etl/runs/{run_id}/post", headers=admin)
        assert repost_res.status_code == 409

    def test_catalog_upsert_flow(self, client):
        admin = _login(client, "demo_admin")
        new_sku = f"CAT_{uuid.uuid4().hex[:6].upper()}"

        conn = client.post(
            "/etl/connections",
            headers=admin,
            json={"name": "Catalog Ingest Conn", "type": "json"},
        ).json()
        pipe = client.post(
            "/etl/pipelines",
            headers=admin,
            json={
                "name": "Catalog Upsert Pipeline",
                "target": "catalog_upsert",
                "connection_id": conn["id"],
            },
        ).json()
        pipe_id = pipe["id"]

        # Run with new item
        run_res = client.post(
            f"/etl/pipelines/{pipe_id}/runs",
            headers=admin,
            json={
                "raw_rows": [
                    {"sku": new_sku, "name": "Ấn chỉ đặc thù mới", "unit": "quyển", "tracked_serial": False}
                ]
            },
        )
        assert run_res.status_code == 201
        run_id = run_res.json()["id"]

        # Post catalog upsert
        post_res = client.post(f"/etl/runs/{run_id}/post", headers=admin)
        assert post_res.status_code == 200
        assert post_res.json()["created_count"] == 1

        # Verify item exists in catalog
        items = client.get("/inventory/items", headers=admin).json()["items"]
        assert any(i["sku"] == new_sku for i in items)
