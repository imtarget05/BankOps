"""Test keyset pagination on /audit-events."""
import uuid
from datetime import UTC, datetime, timedelta

import pytest
from starlette.testclient import TestClient

from app.models.activity import AuditEvent

DEMO_PASSWORD = "DemoPass123!"


def _login(client: TestClient, username: str = "demo_admin") -> dict[str, str]:
    r = client.post("/auth/login", data={"username": username, "password": DEMO_PASSWORD})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


@pytest.mark.asyncio
async def test_audit_events_keyset_pagination(client: TestClient):
    """Auditors can paginate through audit events with cursor without missing rows."""
    from app.database import AsyncSessionLocal

    headers = _login(client, "demo_admin")

    # Insert 15 audit events with distinct timestamps
    now = datetime.now(UTC)
    inserted_ids = []
    async with AsyncSessionLocal() as session:
        for i in range(15):
            event_time = now - timedelta(minutes=15 - i)
            ae = AuditEvent(
                id=uuid.uuid4(),
                action=f"action_{i}",
                subject=f"subject_{i}",
                occurred_at=event_time,
                metadata_json={"index": i},
            )
            session.add(ae)
            inserted_ids.append(str(ae.id))
        await session.commit()

    # Page 1: limit 5
    r1 = client.get("/audit-events?limit=5", headers=headers)
    assert r1.status_code == 200
    d1 = r1.json()
    assert len(d1["audit_events"]) == 5
    cursor1 = d1["next_cursor"]
    assert cursor1 is not None

    # Page 2: with cursor
    r2 = client.get(f"/audit-events?limit=5&cursor={cursor1}", headers=headers)
    assert r2.status_code == 200
    d2 = r2.json()
    assert len(d2["audit_events"]) == 5
    cursor2 = d2["next_cursor"]
    assert cursor2 is not None

    # Page 3: with next cursor
    r3 = client.get(f"/audit-events?limit=5&cursor={cursor2}", headers=headers)
    assert r3.status_code == 200
    d3 = r3.json()
    assert len(d3["audit_events"]) == 5

    # Page 1, 2, 3 must have mutually disjoint event IDs
    ids1 = {e["id"] for e in d1["audit_events"]}
    ids2 = {e["id"] for e in d2["audit_events"]}
    ids3 = {e["id"] for e in d3["audit_events"]}
    assert len(ids1.intersection(ids2)) == 0
    assert len(ids2.intersection(ids3)) == 0
    assert len(ids1.intersection(ids3)) == 0
