"""B2 — Identity/Auth: negative scope tests for cross-branch and limited-view access.

These tests do NOT rely on demo seed data for the negative path. They create
their own users and commit to the same test database used by the rest of the
suite, so a user with no (or no relevant) capabilities is always denied.
"""

from __future__ import annotations

import uuid

from sqlalchemy import text

from app.database import AsyncSessionLocal

PASSWORD = "Wave2Secure123!"

BRANCH_HO = "11111111-1111-4111-8111-111111111111"
BRANCH_A = "22222222-2222-4222-8222-222222222222"
BRANCH_B = "33333333-3333-4333-8333-333333333333"


def _sql(sql: str, **params):
    """Run a short SQL statement against the test database and commit."""
    from asyncio import run

    async def _run() -> None:
        async with AsyncSessionLocal() as session:
            await session.execute(text(sql), params)
            await session.commit()

    run(_run())


def _ensure_user(username: str, role_code: str, branch_id: str | None = None) -> str:
    """Insert (or re-use) a user with a fixed role and commit."""
    from app.api.routes.auth_utils import get_password_hash

    row = _sql(
        "SELECT id FROM iam_users WHERE username = :u", u=username
    )
    user_id = row[0][0] if row else str(uuid.uuid4())
    if not row:
        _sql(
            "INSERT INTO iam_users (id, username, password_hash, status, display_name_demo, "
            "email, branch_id) VALUES (:id, :u, :p, 'active', :d, :e, :b)",
            id=user_id,
            u=username,
            p=get_password_hash(PASSWORD),
            d=f"scope test {username}",
            e=f"{username}@bankops.internal",
            b=branch_id,
        )

    _sql("DELETE FROM iam_user_roles WHERE user_id = :id", id=user_id)
    _sql(
        "INSERT INTO iam_user_roles (user_id, role_code) VALUES (:id, :r)", id=user_id, r=role_code
    )
    return str(user_id)


def _login(client, username: str, password: str = PASSWORD) -> dict:
    response = client.post("/auth/login", json={"username": username, "password": password})
    assert response.status_code == 200, response.text
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


# ---------------------------------------------------------------------------
# S7 — token + capability gates on the activity/audit streams
# ---------------------------------------------------------------------------
class TestActivityAuthorization:
    def test_activity_endpoints_require_capability(self, client):
        username = f"w2_nocap_{uuid.uuid4().hex[:8]}"
        _ensure_user(username, "no_view_role", BRANCH_HO)
        headers = _login(client, username)

        # Authenticated but no `activity:view`/`audit:view` capability -> 403.
        for path in (
            "/activity",
            "/activity/",
            "/activity/stream",
            "/events/stream",
            "/audit-events",
        ):
            assert (
                client.get(path, headers=headers).status_code == 403
            ), f"{path} should require activity:view/audit:view"

    def test_activity_endpoints_deny_anonymous_access(self, client):
        assert client.get("/activity").status_code == 401
        assert client.get("/activity/").status_code == 401
        assert client.get("/activity/stream").status_code == 401
        assert client.get("/events/stream").status_code == 401
        assert client.get("/audit-events").status_code == 401

    def test_403_for_no_capability_user(self, client):
        # S13/S11 still apply, but capability deny is checked on the auth
        # surface before any DB access.
        username = f"w2_deny_{uuid.uuid4().hex[:8]}"
        _ensure_user(username, "no_view_role", BRANCH_HO)
        headers = _login(client, username)

        assert client.get("/reports/inventory-daily", headers=headers).status_code == 403
        assert client.get("/reports/cashflow-daily", headers=headers).status_code == 403
        assert client.get("/reports/stagnation", headers=headers).status_code == 403
