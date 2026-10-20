"""Shift stock-count workflow from the tea-shop SRS."""
import uuid

from conftest import open_shift

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

    # Unique far-future business date: guard blocks a second OPEN shift per
    # (location, date, shift), so today/near dates collide across runs.
    opened, st_id = open_shift(
        client, _idempotent(headers), locations[0]["id"]
    )
    assert opened.json()["shift_code"] == "morning"
    # SRS §3.3: staff only enters used/count; opening is seeded by the system.
    seeded = client.get(f"/inventory/stocktakes/{st_id}", headers=headers).json()["lines"]
    opening = float(
        next(line for line in seeded if line["item_id"] == items[0]["id"])["opening_qty"]
    )

    updated = client.put(
        f"/inventory/stocktakes/{st_id}/lines",
        headers=_idempotent(headers),
        json={
            "lines": [
                {
                    "item_id": items[0]["id"],
                    "used_qty": "25",
                    "counted_qty": "43",
                }
            ]
        },
    )
    assert updated.status_code == 200, updated.text
    line = next(line for line in updated.json()["lines"] if line["item_id"] == items[0]["id"])
    theoretical = opening - 25
    assert float(line["theoretical_qty"]) == theoretical
    assert float(line["variance"]) == 43 - theoretical
