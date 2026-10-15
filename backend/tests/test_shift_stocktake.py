"""Shift stock-count workflow from the tea-shop SRS."""
import uuid

DEMO_PASSWORD = "DemoPass123!"


def _login(client) -> dict[str, str]:
    response = client.post(
        "/auth/login", data={"username": "demo_maker", "password": DEMO_PASSWORD}
    )
    assert response.status_code == 200, response.text
    return {
        "Authorization": f"Bearer {response.json()['access_token']}",
        "Idempotency-Key": str(uuid.uuid4()),
    }


def _idempotent(headers: dict[str, str]) -> dict[str, str]:
    return {**headers, "Idempotency-Key": str(uuid.uuid4())}


def test_staff_shift_count_calculates_theoretical_balance_and_variance(client):
    headers = _login(client)
    locations = client.get("/inventory/locations", headers=headers).json()["locations"]
    items = client.get("/inventory/items", headers=headers).json()["items"]

    # Use unique business date so repeated test runs don't conflict on unique shift/date
    unique_date = f"2026-11-{(int(uuid.uuid4().hex[:4], 16) % 28) + 1:02d}"
    opened = client.post(
        "/inventory/stocktakes",
        headers=_idempotent(headers),
        json={
            "location_id": locations[0]["id"],
            "shift_code": "morning",
            "business_date": unique_date,
        },
    )
    assert opened.status_code == 201, opened.text
    assert opened.json()["shift_code"] == "morning"

    updated = client.put(
        f"/inventory/stocktakes/{opened.json()['id']}/lines",
        headers=_idempotent(headers),
        json={
            "lines": [
                {
                    "item_id": items[0]["id"],
                    "opening_qty": "50",
                    "received_qty": "20",
                    "used_qty": "25",
                    "counted_qty": "43",
                }
            ]
        },
    )
    assert updated.status_code == 200, updated.text
    line = next(line for line in updated.json()["lines"] if line["item_id"] == items[0]["id"])
    assert line["theoretical_qty"] == "45"
    assert line["variance"] == "-2"
