"""Contracts for the S11 registry-verification command."""

from __future__ import annotations

import importlib.util
from pathlib import Path

SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "e2e_verify.py"


def _load_script():
    spec = importlib.util.spec_from_file_location("e2e_verify", SCRIPT_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_registry_verification_fails_closed_without_a_registered_model(tmp_path):
    script = _load_script()

    result = script.verify_registry(
        tracking_uri=f"sqlite:///{tmp_path / 'tracking.db'}",
        model_name="MissingDemandForecastModel",
    )

    assert result["status"] == "failed"
    assert result["reason"] == "no_model_versions"
