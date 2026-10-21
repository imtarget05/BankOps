"""Hygiene script + template: tên chuẩn, KHÔNG in giá trị secret.

Contract:
1. `scripts/sync_github_secrets.sh` KHÔNG được in giá trị secret ra stdout
   (terminal/log CI là nơi secret bị lộ — xem
   `docs/security/secret-rotation-inventory-2026-10-20.md` §4) và phải sync
   đủ 4 biến chuẩn: `BANKOPS_SIGNING_KEY`, `BANKOPS_SESSION_SECRET`,
   `SMTP_PASSWORD`, `SUPERVISOR_PIN`.
2. `backend/.env.example` phải khai báo đủ key chuẩn (placeholder) và chỉ
   NHẮC `SECRET_KEY` (legacy) trong comment — không khai báo giá trị.
"""

from __future__ import annotations

import re
from pathlib import Path

REPO_DIR = Path(__file__).resolve().parents[2]
SYNC_SCRIPT = REPO_DIR / "scripts" / "sync_github_secrets.sh"
ENV_EXAMPLE = REPO_DIR / "backend" / ".env.example"

CANONICAL_VARS = (
    "BANKOPS_SIGNING_KEY",
    "BANKOPS_SESSION_SECRET",
    "SMTP_PASSWORD",
    "SUPERVISOR_PIN",
)


def _script_text() -> str:
    assert SYNC_SCRIPT.exists(), f"không tìm thấy {SYNC_SCRIPT}"
    return SYNC_SCRIPT.read_text(encoding="utf-8")


def test_sync_script_never_prints_secret_values():
    """Không có dòng `echo` nào nội suy biến chứa secret (chỉ màu & tên)."""
    # Biến "màu" dùng cho log — không phải secret.
    cosmetic = {"BLUE", "GREEN", "YELLOW", "RED", "NC"}
    secret_names = (
        "SECRET_KEY",
        "BANKOPS_SIGNING_KEY",
        "BANKOPS_SESSION_SECRET",
        "SMTP_PASSWORD",
        "SMTP_USER",
        "SUPERVISOR_PIN",
        "DATABASE_URL",
        "CLOUDFLARE_ACCOUNT_ID",
        "CLOUDFLARE_API_TOKEN",
        "CLOUDFLARE_TUNNEL_TOKEN",
        "AWS_ACCESS_KEY_ID",
        "AWS_SECRET_ACCESS_KEY",
        "BACKUP_GPG_PASSPHRASE",
    )
    offenders = []
    for line in _script_text().splitlines():
        stripped = line.strip()
        if stripped.startswith("#"):
            continue
        if not re.search(r"\becho\b", stripped):
            continue
        for name in re.findall(r"\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-|[-}])", stripped):
            if name in cosmetic:
                continue
            if name in secret_names:
                offenders.append(stripped)
                break
    assert not offenders, f"script in giá trị secret ra stdout: {offenders}"


def test_sync_script_syncs_all_canonical_vars():
    text = _script_text()
    for name in CANONICAL_VARS:
        assert f'set_secret "{name}"' in text, f"thiếu set_secret cho {name}"


def test_sync_script_does_not_sync_legacy_secret_key():
    text = _script_text()
    assert 'set_secret "SECRET_KEY"' not in text, (
        "`SECRET_KEY` là tên legacy/DEPRECATED — không được sync nữa "
        "(2 tên / 1 giá trị khiến rotate bị lệch)"
    )


def test_env_example_declares_canonical_keys_with_placeholder():
    assert ENV_EXAMPLE.exists(), f"không tìm thấy {ENV_EXAMPLE}"
    text = ENV_EXAMPLE.read_text(encoding="utf-8")
    # Key BẮT BUỘC có giá trị (placeholder) trong .env.example.
    for name in ("BANKOPS_SIGNING_KEY", "BANKOPS_SESSION_SECRET", "SUPERVISOR_PIN"):
        assert re.search(rf"(?m)^{name}=.+", text), f".env.example thiếu {name}=<placeholder>"
    # Key tùy chọn (SMTP) phải được KHAI BÁO; để trống = "chưa cấu hình"
    # (giữ hành vi cũ: email bị tắt, không tự động thử kết nối SMTP giả).
    for name in ("SMTP_USER", "SMTP_PASSWORD"):
        assert re.search(rf"(?m)^{name}=.*$", text), f".env.example thiếu khai báo {name}"


def test_env_example_mentions_legacy_secret_key_only_as_deprecated():
    text = ENV_EXAMPLE.read_text(encoding="utf-8")
    assert "SECRET_KEY" in text, "phải NHẮC `SECRET_KEY` là legacy/DEPRECATED"
    assert not re.search(r"(?m)^SECRET_KEY=", text), (
        "KHÔNG được khai báo giá trị cho `SECRET_KEY` trong .env.example"
    )
    # Phần nhắc phải nói rõ là deprecated.
    assert re.search(r"(?i)deprecated", text), "phải ghi rõ `SECRET_KEY` là DEPRECATED"
