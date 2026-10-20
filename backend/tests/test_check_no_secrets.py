"""Tests for the repo secret guard (`scripts/check_no_secrets.py`).

The guard is the CI gate that keeps credentials out of tracked files. These
tests pin the behaviour that matters for the S10 containment work:

* real credential assignments in tracked files MUST be reported (fail level);
* demo constants / documented placeholders MUST NOT be reported (no false
  positives that would break the build);
* the guard MUST NOT report its own source (it contains the patterns);
* the guard MUST NOT print secret values, only path + line + label.
"""

from __future__ import annotations

import importlib.util
import subprocess
import sys
from pathlib import Path

import pytest

BACKEND_DIR = Path(__file__).resolve().parents[1]
REPO_DIR = BACKEND_DIR.parent
SCANNER_PATH = REPO_DIR / "scripts" / "check_no_secrets.py"


def _load_scanner():
    spec = importlib.util.spec_from_file_location("check_no_secrets", SCANNER_PATH)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module  # dataclasses need the module registered
    spec.loader.exec_module(module)
    return module


scanner = _load_scanner()


def _labels(text: str) -> list[str]:
    return [f.label for f in scanner.scan_text(text, "sample.txt")]


def _severities(text: str) -> list[str]:
    return [f.severity for f in scanner.scan_text(text, "sample.txt")]


def test_reports_numeric_supervisor_pin_assignment():
    findings = scanner.scan_text("SUPERVISOR_PIN=123456\n", "app.env")
    assert findings, "numeric SUPERVISOR_PIN literal must be reported"
    assert findings[0].line == 1
    assert findings[0].severity == scanner.SEVERITY_FAIL
    assert "PIN" in findings[0].label.upper()


def test_ignores_demo_pin_constant():
    assert _labels("DEMO_SUPERVISOR_PIN = '123456'\n") == []


def test_ignores_documented_placeholders():
    text = (
        'SUPERVISOR_PIN: "CHANGE_ME"\n'
        'SECRET_KEY="CHANGE_ME_GENERATE_32_BYTE_RANDOM_SECRET_KEY"\n'
        'BACKUP_GPG_PASSPHRASE="CHANGE_ME"\n'
    )
    assert _labels(text) == []


def test_reports_secret_key_literal():
    findings = scanner.scan_text('SECRET_KEY = "0123456789abcdef0123456789abcdef"\n', "x.env")
    assert findings and findings[0].severity == scanner.SEVERITY_FAIL


def test_reports_signing_and_session_secret_literals():
    text = (
        'BANKOPS_dev_signing_key="0123456789abcdef0123456789abcdef"\n'
        'BANKOPS_SESSION_SECRET="0123456789abcdef0123456789abcdef"\n'
    )
    labels = _labels(text)
    assert len(labels) == 2
    assert all(s == scanner.SEVERITY_FAIL for s in _severities(text))


def test_reports_cloudflare_token_and_pem_key():
    token = "cfut_" + "A" * 25
    findings = scanner.scan_text(f"{token}\n-----BEGIN PRIVATE KEY-----\n", "x.txt")
    assert len(findings) == 2
    assert all(f.severity == scanner.SEVERITY_FAIL for f in findings)


def test_reports_known_token_formats():
    text = "ghp_" + "a" * 30 + "\nxoxb-1234567890-abcdefghij\nAKIA" + "B" * 16 + "\n"
    assert len(scanner.scan_text(text, "x.txt")) == 3


def test_postgres_url_with_password_is_advisory_only():
    findings = scanner.scan_text(
        "DATABASE_URL=postgresql://user:s3cr3tpassword@db.example.com:5432/app\n", "x.env"
    )
    assert findings, "postgres URL with password must still be surfaced"
    assert findings[0].severity == scanner.SEVERITY_WARN


def test_scanner_does_not_flag_its_own_source():
    findings = scanner.scan_text(SCANNER_PATH.read_text(encoding="utf-8"), str(SCANNER_PATH))
    assert [f for f in findings if f.severity == scanner.SEVERITY_FAIL] == []


def test_guard_and_its_test_are_excluded_from_the_tracked_scan():
    assert "scripts/check_no_secrets.py" in scanner.SELF_EXCLUDED_RELATIVE
    assert "backend/tests/test_check_no_secrets.py" in scanner.SELF_EXCLUDED_RELATIVE
    # The test file itself contains credential-shaped fixtures; it must not be
    # reported once it is committed.
    fixture_findings = scanner.scan_text(
        Path(__file__).read_text(encoding="utf-8"), "backend/tests/test_check_no_secrets.py"
    )
    assert fixture_findings, "the fixture file should contain credential-shaped literals"
    assert "backend/tests/test_check_no_secrets.py" in scanner.SELF_EXCLUDED_RELATIVE


def test_tracked_files_have_no_failing_findings():
    findings = scanner.scan_tracked_files()
    failing = [f for f in findings if f.severity == scanner.SEVERITY_FAIL]
    assert failing == [], (
        "Tracked files must not contain credentials: "
        + "; ".join(f"{f.path}:{f.line} {f.label}" for f in failing)
    )


def test_local_env_files_are_listed_without_values(tmp_path):
    local = tmp_path / ".env"
    local.write_text("SUPERVISOR_PIN=123456\n", encoding="utf-8")
    findings = scanner.scan_local_secret_files(extra_roots=[tmp_path])
    assert findings
    assert all(f.path.endswith(".env") for f in findings)
    # No secret value may appear in the rendered finding.
    for f in findings:
        assert "123456" not in f.label


def test_cli_exit_code_is_zero_on_clean_repo():
    proc = subprocess.run(
        [sys.executable, str(SCANNER_PATH)],
        cwd=REPO_DIR,
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, proc.stderr


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(pytest.main([__file__, "-v"]))
