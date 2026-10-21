"""Test canonical database binding for advisory AI assessment."""
import uuid
from decimal import Decimal

import pytest
from starlette.testclient import TestClient

from app.models.iam import User
from app.models.inventory import InventoryRequest, InventoryRequestLine, Item

DEMO_PASSWORD = "DemoPass123!"


def _login(client: TestClient, username: str = "demo_admin") -> dict[str, str]:
    r = client.post("/auth/login", data={"username": username, "password": DEMO_PASSWORD})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


@pytest.mark.asyncio
async def test_ai_assessment_canonical_binding_overrides_forged_client_fields(client: TestClient):
    """When a voucher exists in PostgreSQL, AI assessment ignores client-forged quantity/maker."""
    from sqlalchemy import select

    from app.database import AsyncSessionLocal

    headers = _login(client, "demo_admin")

    req_id = uuid.uuid4()

    async with AsyncSessionLocal() as session:
        admin_user = (
            await session.execute(select(User).where(User.username == "demo_admin"))
        ).scalars().first()
        maker_id = admin_user.id if admin_user else uuid.uuid4()

        item = (await session.execute(select(Item).limit(1))).scalars().first()
        assert item is not None, "Seeded item must exist"

        inv_req = InventoryRequest(
            id=req_id,
            kind="receipt",
            status="submitted",
            maker_id=maker_id,
            reason="Nhập 80kg trà đen theo hợp đồng chuẩn",
            version=2,
            created_by=maker_id,
        )
        session.add(inv_req)

        line = InventoryRequestLine(
            id=uuid.uuid4(),
            request_id=req_id,
            item_id=item.id,
            quantity=Decimal("80.000"),
            direction="increase",
        )
        session.add(line)
        await session.commit()

    # Client tries to forge the request by claiming it is only 5 units and maker is 'FakeMaker'
    forged_body = {
        "request_id": str(req_id),
        "kind": "receipt",
        "amount_or_qty": "5",  # Forged: claiming 5 units instead of real 80
        "maker": "Hacker",
        "reason": "Mua ít trà",
    }

    response = client.post("/ai/assess-request", headers=headers, json=forged_body)
    assert response.status_code == 200, response.text
    data = response.json()

    # Must be bound to canonical database values
    assert data["canonical_bound"] is True
    assert data["request_version"] == 1
    assert data["assessed_by"] == "demo_admin"

    # Because real quantity is 80 (>= 50), it must trigger the large receipt rule (medium risk)
    assert data["risk_level"] in ("medium", "high")
    assert any(">= 50" in r or "50 đơn vị" in r for r in data["flagged_rules"])
