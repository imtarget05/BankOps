"""STEP 5 — `app.models` phải đăng ký ĐẦY ĐỦ model (không phụ thuộc import
trong file migration).

Residual: model `idempotency` chưa được đăng ký trong `app/models/__init__.py`
-> `alembic check` chỉ xanh nhờ import ở module-level của
`alembic/versions/027_idempotency_keys.py`. Ai gỡ import đó -> drift quay lại
(autogenerate đòi DROP bảng `idempotency_keys`).

Test chạy subprocess chỉ `import app.models` (KHÔNG import migration) và
kiểm tra `Base.metadata` — chứng minh metadata độc lập với import trong file
migration.
"""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]

# Bảng bắt buộc phải có trong `Base.metadata` chỉ với `import app.models`.
EXPECTED_TABLES = {
    "idempotency_keys",  # model `idempotency` (027) - residual STEP 5
    "cash_requests",
    "cash_boxes",
    "cash_balances",
    "iam_users",
    "iam_roles",
    "iam_capabilities",
    "iam_role_capabilities",
}


def _metadata_tables_via_models_package() -> set[str]:
    """Import DUY NHẤT package `app.models` rồi liệt kê bảng trong metadata."""
    code = (
        "import app.models\n"
        "from app.db.base import Base\n"
        "print('\\n'.join(sorted(Base.metadata.tables)))\n"
    )
    proc = subprocess.run(
        [sys.executable, "-c", code],
        cwd=str(BACKEND_DIR),
        env={**os.environ, "PYTHONPATH": str(BACKEND_DIR)},
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert proc.returncode == 0, f"import app.models thất bại: {proc.stderr[-2000:]}"
    return {line.strip() for line in proc.stdout.splitlines() if line.strip()}


def test_models_package_registers_all_tables():
    """`import app.models` đủ để metadata có bảng `idempotency_keys` + các bảng lõi."""
    tables = _metadata_tables_via_models_package()
    missing = EXPECTED_TABLES - tables
    assert not missing, (
        f"`import app.models` chưa đăng ký các bảng {sorted(missing)} -> "
        f"`alembic check` sẽ báo drift (autogenerate đòi DROP)"
    )


def test_idempotency_table_registered_without_migration_import():
    """Bảng `idempotency_keys` phải có mà KHÔNG cần import trong file migration."""
    tables = _metadata_tables_via_models_package()
    assert "idempotency_keys" in tables, (
        "model `idempotency` chưa được đăng ký trong app/models/__init__.py"
    )


def test_migration_file_does_not_need_model_import():
    """File migration không được phụ thuộc import ORM để metadata đầy đủ.

    `027_idempotency_keys.py` trước đây import `app.models.idempotency` ở
    module-level chỉ để `Base.metadata` có bảng -> đây là cái "xiền" khiến
    `alembic check` xanh giả. Giờ việc đó do `app/models/__init__.py` đảm nhiệm.
    """
    migration = BACKEND_DIR / "alembic" / "versions" / "027_idempotency_keys.py"
    source = migration.read_text(encoding="utf-8")
    assert "from app.models.idempotency import" not in source, (
        "migration 027 không được import model ở module-level nữa "
        "(metadata phải đầy đủ nhờ app/models/__init__.py)"
    )
