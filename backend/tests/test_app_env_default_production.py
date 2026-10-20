"""STEP 5 — `app_env` mặc định phải là `production` (fail-closed).

Residual: `Settings.app_env` mặc định `"demo"` -> app khởi động mà không set
`APP_ENV` sẽ:
- dùng `session_secret`/`signing_key` ephemeral -> token hết hạn sau mỗi lần
  restart, và
- không kích hoạt `assert_runtime_secrets()` (app chạy được dù thiếu secret
  ký JWT bắt buộc ở môi trường thật).

Test:
- không set `APP_ENV` -> `app_env == "production"`;
- `APP_ENV=demo` + `DEMO_MODE=true` -> vẫn demo đầy đủ.
"""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

import pytest

from app.config import Settings

BACKEND_DIR = Path(__file__).resolve().parents[1]


def _env_without_secrets() -> dict:
    env = {k: v for k, v in os.environ.items() if k not in ("APP_ENV", "BANKOPS_SIGNING_KEY", "BANKOPS_signing")}
    return env


def test_default_app_env_is_production(monkeypatch):
    """Không set APP_ENV -> coi như production (fail-closed), KHÔNG phải demo."""
    monkeypatch.delenv("APP_ENV", raising=False)
    s = Settings()
    assert s.app_env == "production", (
        f"app_env mặc định phải là 'production' (fail-closed), thấy {s.app_env!r}"
    )
    assert s.is_demo is False
    assert s.is_demo_mode is False


def test_demo_env_still_works_when_explicit(monkeypatch):
    """`APP_ENV=demo` + `DEMO_MODE=true` -> demo đầy đủ (không bị ghi đè)."""
    monkeypatch.setenv("APP_ENV", "demo")
    monkeypatch.setenv("DEMO_MODE", "true")
    s = Settings()
    assert s.app_env == "demo"
    assert s.is_demo is True
    assert s.is_demo_mode is True
    # Demo -> secret ephemeral (không crash khi thiếu env)
    assert isinstance(s.signing_key, str) and s.signing_key
    assert isinstance(s.session_secret, str) and s.session_secret


def test_production_default_requires_signing_key(monkeypatch):
    """Mặc định production + thiếu `BANKOPS_SIGNING_KEY` -> phải fail fast."""
    monkeypatch.delenv("APP_ENV", raising=False)
    monkeypatch.delenv("BANKOPS_SIGNING_KEY", raising=False)
    monkeypatch.delenv("BANKOPS_signing", raising=False)
    s = Settings()
    with pytest.raises(RuntimeError, match="JWT signing key must be set"):
        s.assert_runtime_secrets()


def test_server_process_without_signing_key_fails_fast():
    """Process kiểu server (target `app.main:app`) thiếu secret -> KHÔNG được import được.

    Đây là fail-fast thật: `import app.config` (mà uvicorn import khi khởi động)
    phải ném lỗi NGAY, chứ không phải chết lúc ký token đầu tiên.
    """
    proc = subprocess.run(
        [sys.executable, "-c", "import app.config", "app.main:app"],
        cwd=str(BACKEND_DIR),
        env={**_env_without_secrets(), "PYTHONPATH": str(BACKEND_DIR)},
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert proc.returncode != 0, (
        "server thiếu BANKOPS_SIGNING_KEY phải fail-fast, nhưng import thành công:\n"
        f"{proc.stdout}\n{proc.stderr}"
    )
    assert "JWT signing key must be set" in proc.stderr, proc.stderr[-2000:]


def test_cli_process_does_not_require_signing_key():
    """Công cụ CLI (alembic/script) không ký token -> không bị chặn vì thiếu secret."""
    proc = subprocess.run(
        [sys.executable, "-c", "import app.config; print(app.config.settings.app_env)"],
        cwd=str(BACKEND_DIR),
        env={**_env_without_secrets(), "PYTHONPATH": str(BACKEND_DIR)},
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert proc.returncode == 0, (
        f"import app.config (CLI) phải thành công để `alembic` chạy được:\n{proc.stderr[-2000:]}"
    )
    assert proc.stdout.strip() == "production"
