"""B1.3 — template Secret của Kubernetes phải khai báo ĐÚNG tên key.

`backend/app/config.py` đọc secret từ env var:
  - `BANKOPS_SIGNING_KEY`  — key ký/verify JWT (fail-closed ở non-demo),
  - `BANKOPS_SESSION_SECRET` — ký cookie phiên (bắt buộc ở non-demo),
  - `SMTP_PASSWORD`        — mật khẩu SMTP (email kích hoạt / reset mật khẩu),
  - `SUPERVISOR_PIN`       — PIN duyệt phiếu quỹ giá trị cao.

Template cũ chỉ có `SECRET_KEY` (tên LEGACY) -> deploy theo template sẽ thiếu
key bắt buộc và app không khởi động được (hoặc ký token bằng secret rỗng).

Ràng buộc quan trọng: template CHỈ được chứa PLACEHOLDER, tuyệt đối không
đưa giá trị thật vào repo.
"""

from __future__ import annotations

from pathlib import Path

import yaml

REPO_DIR = Path(__file__).resolve().parents[2]
TEMPLATE_PATH = REPO_DIR / "infra" / "k8s" / "base" / "secret-template.yaml"

# Key bắt buộc phải có trong template (khớp `backend/app/config.py`).
REQUIRED_KEYS = (
    "DATABASE_URL",
    "BANKOPS_SIGNING_KEY",
    "BANKOPS_SESSION_SECRET",
    "SMTP_PASSWORD",
    "SUPERVISOR_PIN",
)


def _load_template() -> dict:
    assert TEMPLATE_PATH.exists(), f"không tìm thấy template: {TEMPLATE_PATH}"
    doc = yaml.safe_load(TEMPLATE_PATH.read_text(encoding="utf-8"))
    assert isinstance(doc, dict), "template phải là một YAML document (dict)"
    return doc


def test_secret_template_is_valid_k8s_secret():
    doc = _load_template()
    assert doc.get("apiVersion") == "v1"
    assert doc.get("kind") == "Secret"
    assert doc.get("type") == "Opaque"
    assert doc["metadata"]["name"] == "bankops-secrets"


def test_secret_template_declares_all_required_keys():
    doc = _load_template()
    string_data = doc.get("stringData") or {}
    missing = [k for k in REQUIRED_KEYS if k not in string_data]
    assert not missing, f"template thiếu key bắt buộc: {missing}"


def test_secret_template_is_not_legacy_only():
    """Không được chỉ có `SECRET_KEY` (tên legacy) trong template."""
    doc = _load_template()
    string_data = doc.get("stringData") or {}
    assert "SECRET_KEY" in string_data, (
        "giữ `SECRET_KEY` để rollout không gãy (cluster cũ), nhưng phải có "
        "thêm key canonical"
    )
    assert "BANKOPS_SIGNING_KEY" in string_data, (
        "template KHÔNG được chỉ dựa vào `SECRET_KEY` — code đọc "
        "`BANKOPS_SIGNING_KEY` (`backend/app/config.py::_signing_key_from_env`)"
    )


def test_secret_template_contains_only_placeholders():
    """Template KHÔNG được chứa giá trị thật (chỉ placeholder)."""
    doc = _load_template()
    string_data = doc.get("stringData") or {}
    for key, value in string_data.items():
        assert isinstance(value, str), f"{key} phải là chuỗi"
        assert "CHANGE_ME" in value, (
            f"{key} trong template phải là placeholder `CHANGE_ME_...`, "
            f"không phải giá trị thật: {value[:12]}..."
        )
    # `DATABASE_URL` là URL -> placeholder nằm ở phần mật khẩu.
    assert "CHANGE_ME_PASSWORD" in string_data["DATABASE_URL"]
