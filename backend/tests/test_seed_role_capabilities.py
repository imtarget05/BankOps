"""STEP 5 — seed phải cấp `cash:manage_box` + `cash:post_adjustment` cho admin.

Residual: `backend/app/seed.py` chỉ cấp hai quyền két tiền cho
`cash_sim_operator` và `approver` -> user chỉ có role `admin` (hoặc
`system_admin`) bị chặn ở CẢ UI lẫn backend (kể cả luồng tăng quỹ `receipt`
vốn giờ yêu cầu `cash:post_adjustment`).

Test chạy seed THẬT (idempotent) rồi đọc `iam_role_capabilities` để khẳng
định mapping tồn tại trong DB — không chỉ so chuỗi source.
"""
from __future__ import annotations

import asyncio
import os
import subprocess
import sys
from pathlib import Path

import pytest
from sqlalchemy import text

BACKEND_DIR = Path(__file__).resolve().parents[1]

ADMIN_ROLES = ("admin", "system_admin")
REQUIRED_CAPS = ("cash:manage_box", "cash:post_adjustment")


def _sql(sql: str, **params):
    """Chạy SQL trực tiếp (độc lập HTTP response) để assert dữ liệu thật."""
    from app.database import AsyncSessionLocal

    async def _run():
        async with AsyncSessionLocal() as session:
            result = await session.execute(text(sql), params)
            await session.commit()
            if not result.returns_rows:
                return []
            return result.fetchall()

    return asyncio.run(_run())


@pytest.fixture(scope="module", autouse=True)
def _seeded_db():
    """Chạy `seed_demo()` thật (idempotent) trước khi assert."""
    env = {
        **os.environ,
        "APP_ENV": "demo",
        "DEMO_MODE": "true",
    }
    env.setdefault("DATABASE_URL", "postgresql+psycopg2://bankops:bankops@localhost:5432/bankops")
    proc = subprocess.run(
        [
            sys.executable,
            "-c",
            "from app.seed import seed_demo; import asyncio; asyncio.run(seed_demo())",
        ],
        cwd=str(BACKEND_DIR),
        env=env,
        capture_output=True,
        text=True,
        timeout=300,
    )
    assert proc.returncode == 0, f"seed_demo thất bại: {proc.stdout[-2000:]} {proc.stderr[-2000:]}"
    yield


@pytest.mark.parametrize("role_code", ADMIN_ROLES)
def test_admin_roles_have_cash_box_capabilities(role_code):
    """`admin` / `system_admin` phải có đủ `cash:manage_box` + `cash:post_adjustment`."""
    rows = _sql(
        "SELECT capability_code FROM iam_role_capabilities WHERE role_code = :r",
        r=role_code,
    )
    caps = {row[0] for row in rows}
    missing = [cap for cap in REQUIRED_CAPS if cap not in caps]
    assert not missing, (
        f"role `{role_code}` thiếu capability {missing} "
        f"(seed phải cấp {list(REQUIRED_CAPS)})"
    )


@pytest.mark.parametrize("role_code", ADMIN_ROLES)
def test_admin_roles_capabilities_exist_in_catalog(role_code):
    """Capability phải có trong danh mục `iam_capabilities` (không phải mapping mồ côi)."""
    rows = _sql(
        "SELECT c.code FROM iam_capabilities c "
        "JOIN iam_role_capabilities rc ON rc.capability_code = c.code "
        "WHERE rc.role_code = :r AND c.code IN ('cash:manage_box', 'cash:post_adjustment')",
        r=role_code,
    )
    found = {row[0] for row in rows}
    assert found == set(REQUIRED_CAPS), (
        f"role `{role_code}` chỉ resolve được {found}, mong đợi {set(REQUIRED_CAPS)}"
    )
