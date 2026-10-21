"""`backend/entrypoint.sh` không được ÂM THẦM dùng `SECRET_KEY` làm signing key.

Residual (xem `docs/security/secret-rotation-inventory-2026-10-20.md` §4):
shim `SECRET_KEY -> BANKOPS_SIGNING_KEY` khiến **2 tên, 1 giá trị** ⇒ rotate
`BANKOPS_SIGNING_KEY` ở một nơi thì nơi kia vẫn giữ giá trị cũ, và secret
cũ vẫn "sống" trong cluster.

Contract sau khi sửa:
- `BANKOPS_SIGNING_KEY` có mặt -> dùng nó, KHÔNG đụng `SECRET_KEY`.
- `BANKOPS_SIGNING_KEY` thiếu + `APP_ENV` là production/staging (mặc định
  khi `APP_ENV` không set) -> **FAIL-FAST**, exit != 0, KHÔNG start server.
- `BANKOPS_SIGNING_KEY` thiếu + `APP_ENV` demo/dev/test -> fallback legacy
  **kèm CẢNH BÁO LỚN** (không âm thầm).

Test chạy THẬT `backend/entrypoint.sh` với `alembic`/`uvicorn` giả (đưa vào
PATH) — cùng kỹ thuật với `test_entrypoint_failfast.py`.
"""
from __future__ import annotations

import os
import stat
import subprocess
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
ENTRYPOINT = BACKEND_DIR / "entrypoint.sh"


def _make_fake_bin(tmp_path: Path) -> tuple[Path, Path, Path]:
    """bin giả: `alembic` (ok) + `uvicorn` (ghi args và signing key ra file)."""
    bindir = tmp_path / "bin"
    bindir.mkdir(exist_ok=True)
    args_marker = tmp_path / "uvicorn-args.txt"
    key_marker = tmp_path / "uvicorn-signing-key.txt"

    alembic = bindir / "alembic"
    alembic.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    alembic.chmod(alembic.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)

    uvicorn = bindir / "uvicorn"
    uvicorn.write_text(
        "#!/bin/sh\n"
        f'echo "$@" > "{args_marker}"\n'
        f'echo "${{BANKOPS_SIGNING_KEY:-}}" > "{key_marker}"\n'
        "exit 0\n",
        encoding="utf-8",
    )
    uvicorn.chmod(uvicorn.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
    return bindir, args_marker, key_marker


def _run_entrypoint(tmp_path: Path, extra_env: dict | None = None):
    bindir, args_marker, key_marker = _make_fake_bin(tmp_path)
    env = {
        **os.environ,
        "PATH": f"{bindir}{os.pathsep}{os.environ.get('PATH', '')}",
    }
    # Dọn sạch biến secret khỏi môi trường kế thừa để test tự quyết định.
    for name in ("APP_ENV", "BANKOPS_SIGNING_KEY", "SECRET_KEY", "DATABASE_URL"):
        env.pop(name, None)
    env.update(extra_env or {})
    proc = subprocess.run(
        ["sh", str(ENTRYPOINT)],
        env=env,
        capture_output=True,
        text=True,
        timeout=60,
    )
    args = args_marker.read_text(encoding="utf-8") if args_marker.exists() else None
    key = key_marker.read_text(encoding="utf-8").strip() if key_marker.exists() else None
    return proc, args, key


def test_production_without_signing_key_fails_fast(tmp_path):
    """Production thiếu `BANKOPS_SIGNING_KEY` -> exit != 0, KHÔNG start server."""
    proc, uvicorn_args, _ = _run_entrypoint(
        tmp_path,
        {
            "APP_ENV": "production",
            "SECRET_KEY": "legacy-value-present",
        },
    )
    combined = proc.stdout + proc.stderr
    assert proc.returncode != 0, (
        f"production thiếu BANKOPS_SIGNING_KEY phải FAIL-FAST, exit={proc.returncode}\n{combined}"
    )
    assert uvicorn_args is None, (
        f"KHÔNG được start server khi thiếu signing key, uvicorn chạy với: {uvicorn_args!r}"
    )
    assert "FATAL" in combined, f"phải log FATAL rõ ràng, thấy:\n{combined}"
    assert "BANKOPS_SIGNING_KEY" in combined, combined


def test_unset_app_env_is_treated_as_production(tmp_path):
    """Không set `APP_ENV` -> coi như production (fail-closed) => fail-fast."""
    proc, uvicorn_args, _ = _run_entrypoint(tmp_path, {"SECRET_KEY": "legacy-value-present"})
    combined = proc.stdout + proc.stderr
    assert proc.returncode != 0, (
        f"APP_ENV unset phải fail-closed (fail-fast), exit={proc.returncode}\n{combined}"
    )
    assert uvicorn_args is None, uvicorn_args


def test_staging_without_signing_key_fails_fast(tmp_path):
    """Staging cũng fail-fast (không chỉ production)."""
    proc, uvicorn_args, _ = _run_entrypoint(
        tmp_path, {"APP_ENV": "staging", "SECRET_KEY": "legacy-value-present"}
    )
    assert proc.returncode != 0, proc.stdout + proc.stderr
    assert uvicorn_args is None, uvicorn_args


def test_demo_fallback_emits_loud_warning(tmp_path):
    """Demo thiếu `BANKOPS_SIGNING_KEY` -> fallback legacy KÈM CẢNH BÁO LỚN."""
    proc, uvicorn_args, signing_key = _run_entrypoint(
        tmp_path, {"APP_ENV": "demo", "SECRET_KEY": "legacy-value-present"}
    )
    combined = proc.stdout + proc.stderr
    assert proc.returncode == 0, combined
    assert uvicorn_args is not None, "demo vẫn phải start server"
    assert signing_key == "legacy-value-present", (
        f"demo fallback phải dùng SECRET_KEY, thấy {signing_key!r}"
    )
    assert "WARNING" in combined.upper(), f"phải có cảnh báo, thấy:\n{combined}"
    assert "SECRET_KEY" in combined, combined
    assert "DEPRECATED" in combined.upper(), (
        f"cảnh báo phải nói rõ SECRET_KEY là tên legacy/Deprecated, thấy:\n{combined}"
    )


def test_canonical_signing_key_is_used_without_touching_legacy(tmp_path):
    """Có `BANKOPS_SIGNING_KEY` -> dùng nó, KHÔNG fallback, KHÔNG cảnh báo legacy."""
    proc, uvicorn_args, signing_key = _run_entrypoint(
        tmp_path,
        {
            "APP_ENV": "production",
            "BANKOPS_SIGNING_KEY": "canonical-value-present",
            "SECRET_KEY": "legacy-value-present",
        },
    )
    combined = proc.stdout + proc.stderr
    assert proc.returncode == 0, combined
    assert uvicorn_args is not None, combined
    assert signing_key == "canonical-value-present", signing_key
    assert "SECRET_KEY" not in combined, (
        f"không được nhắc tới fallback legacy khi đã có key chuẩn:\n{combined}"
    )
