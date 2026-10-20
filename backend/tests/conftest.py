"""Shared fixtures for BankOps audit tests.

These tests are written by the independent QA reviewer. They must not import
`app.*` at module import time, so that collection always succeeds even when the
application itself is broken.
"""
from __future__ import annotations

import os
import subprocess
import sys
import uuid
from datetime import date, timedelta
from pathlib import Path

import pytest

BACKEND_DIR = Path(__file__).resolve().parents[1]
REPO_DIR = BACKEND_DIR.parent
APP_DIR = BACKEND_DIR / "app"

# Make `app` importable the same way uvicorn/alembic would.
sys.path.insert(0, str(BACKEND_DIR))

# A syntactically valid placeholder so `app.config.Settings()` can be built
# without a real database. Tests never open a connection through this URL.
os.environ.setdefault(
    "DATABASE_URL", "postgresql+psycopg2://bankops:bankops@127.0.0.1:5432/bankops"
)


def _import_or_fail(module: str):
    try:
        return __import__(module, fromlist=["*"])
    except BaseException as exc:  # noqa: BLE001 - we want every failure kind
        pytest.fail(
            f"Không import được `{module}`: {type(exc).__name__}: {exc}\n"
            f"-> Ứng dụng/khối đó không khởi động được, mọi ca kiểm thử phụ thuộc "
            f"vào nó đều không chạy được.",
            pytrace=False,
        )


@pytest.fixture(scope="session")
def app():
    """Import the FastAPI application, failing loudly if it cannot boot."""
    return _import_or_fail("app.main").app


@pytest.fixture(scope="session")
def client(app):
    """HTTP client against the real app. Needs a reachable database for /health/ready."""
    from fastapi.testclient import TestClient

    try:
        with TestClient(app) as c:
            yield c
    except BaseException as exc:  # noqa: BLE001
        pytest.fail(
            f"Không khởi động được ASGI app (startup hook): {type(exc).__name__}: {exc}",
            pytrace=False,
        )


@pytest.fixture(autouse=True)
def reset_rate_limits():
    """Reset in-memory login failure rate limits between tests."""
    try:
        from app.api.routes.auth_utils import _login_failures
        _login_failures.clear()
    except Exception:
        pass
    yield
    try:
        from app.api.routes.auth_utils import _login_failures
        _login_failures.clear()
    except Exception:
        pass


@pytest.fixture(scope="session")
def models():
    """Import every SQLAlchemy model module, failing loudly on any broken module."""
    broken = []
    loaded = []
    for name in ("iam", "inventory", "cash_sim", "approval", "activity", "integration", "reconciliation"):
        try:
            loaded.append(__import__(f"app.models.{name}", fromlist=["*"]))
        except BaseException as exc:  # noqa: BLE001
            broken.append(f"  app.models.{name}: {type(exc).__name__}: {exc}")
    if broken:
        pytest.fail(
            "Một hoặc nhiều model module không import được:\n" + "\n".join(broken),
            pytrace=False,
        )
    return loaded


def run(cmd: list[str], cwd: Path | None = None, timeout: int = 300) -> subprocess.CompletedProcess:
    return subprocess.run(
        cmd, cwd=str(cwd or REPO_DIR), capture_output=True, text=True, timeout=timeout
    )


def open_shift(client, headers, location_id: str, shift_code: str = "morning"):
    """Open a stocktake shift on a business date that is still free.

    The application allows only one *open* shift per
    ``(location_id, business_date, shift_code)``.  Every test run leaves its
    shift open, so a randomly chosen date eventually collides with a previous
    run and the API answers ``409 SHIFT_ALREADY_OPEN``.  This helper retries
    across a wide window of dates until the shift can be opened, and returns
    ``(response, stocktake_id)``.
    """
    base = date(2040, 1, 1)
    offset = uuid.uuid4().int % 3650
    response = None
    for attempt in range(50):
        candidate = (base + timedelta(days=(offset + attempt) % 3650)).isoformat()
        response = client.post(
            "/inventory/stocktakes",
            headers=headers,
            json={
                "location_id": location_id,
                "shift_code": shift_code,
                "business_date": candidate,
            },
        )
        if response.status_code != 409:
            break
    assert response is not None and response.status_code == 201, (
        f"Không mở được ca kiểm kê: {response.status_code} {response.text}"
    )
    return response, response.json()["id"]


def fetch_all_balances(
    client,
    headers: dict[str, str],
    path: str = "/inventory/balances",
    params: dict | None = None,
) -> list[dict]:
    """Duyệt hết các trang của /inventory/balances qua keyset cursor.

    Endpoint giới hạn ``limit`` (tối đa 100) và trả ``next_cursor``; một GET
    duy nhất chỉ thấy trang đầu. Trên database dùng chung tích tụ balance row
    qua nhiều lần chạy, test phải đi theo cursor để nhìn thấy toàn bộ tồn kho
    thay vì chỉ trang đầu tiên.
    """
    query = dict(params or {})
    rows: list[dict] = []
    while True:
        resp = client.get(path, headers=headers, params=query)
        assert resp.status_code == 200, resp.text
        body = resp.json()
        rows.extend(body["balances"])
        next_cursor = body.get("next_cursor")
        if not next_cursor:
            return rows
        query["cursor"] = next_cursor
