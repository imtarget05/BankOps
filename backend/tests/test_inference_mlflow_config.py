"""The serving image and a local test host use different writable stores."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path


def test_inference_import_uses_writable_local_default_and_tracks_fixture_uri(tmp_path):
    """Importing inference must not pin every later MLflow test to /data."""
    backend_dir = Path(__file__).resolve().parents[1]
    env = os.environ.copy()
    env.pop("MLFLOW_TRACKING_URI", None)
    env.pop("MLFLOW_REGISTRY_URI", None)
    env["PYTHONPATH"] = str(backend_dir)
    env["TEST_MLFLOW_URI"] = f"sqlite:///{tmp_path / 'fixture.db'}"
    script = """
import os
real_isdir = os.path.isdir
os.path.isdir = lambda path: False if path == '/data' else real_isdir(path)
import mlflow
from app.api import inference

assert inference.MLFLOW_TRACKING_URI != 'sqlite:////data/mlflow.db'
assert mlflow.get_tracking_uri() == inference.MLFLOW_TRACKING_URI
assert mlflow.get_registry_uri() == inference.MLFLOW_TRACKING_URI
fixture_uri = os.environ['TEST_MLFLOW_URI']
mlflow.set_tracking_uri(fixture_uri)
assert mlflow.get_registry_uri() == fixture_uri
"""
    result = subprocess.run(
        [sys.executable, "-c", script],
        cwd=backend_dir,
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )
    assert result.returncode == 0, result.stderr
