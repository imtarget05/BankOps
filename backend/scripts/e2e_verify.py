"""Fail-closed MLflow registry gate for the S11 cloud workflow.

The command writes a small JSON artifact that names the promoted model version.
It intentionally does not train or bootstrap a model: S11 must prove that the
training stage created a model before registry promotion can succeed.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

import mlflow


def verify_registry(tracking_uri: str, model_name: str) -> dict[str, Any]:
    """Promote the newest registered model, or return a failed gate result."""
    mlflow.set_tracking_uri(tracking_uri)
    client = mlflow.tracking.MlflowClient(tracking_uri=tracking_uri)
    versions = client.search_model_versions(f"name='{model_name}'")

    if not versions:
        return {
            "status": "failed",
            "reason": "no_model_versions",
            "model_name": model_name,
        }

    latest = max(versions, key=lambda version: int(version.version))
    client.transition_model_version_stage(
        name=model_name,
        version=str(latest.version),
        stage="Production",
    )
    return {
        "status": "passed",
        "model_name": model_name,
        "production_version": int(latest.version),
    }


def _write_evidence(result: dict[str, Any]) -> None:
    output_path = Path(os.environ.get("E2E_EVIDENCE_PATH", "e2e-registry.json"))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(result, sort_keys=True) + "\n", encoding="utf-8")


def main() -> int:
    tracking_uri = os.environ.get("MLFLOW_TRACKING_URI", "sqlite:///./mlflow.db")
    model_name = os.environ.get("MODEL_NAME", "DemandForecastModel")
    result = verify_registry(tracking_uri=tracking_uri, model_name=model_name)
    _write_evidence(result)
    print(json.dumps(result, sort_keys=True))
    return 0 if result["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
