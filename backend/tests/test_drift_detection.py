# Drift Detection Tests (Phase M — S7)
import os
import sys

sys.path.insert(0, os.path.dirname(__file__) + "/../..")

import numpy as np
import pandas as pd

from app.services.drift_detection import analyze_drift, detect_data_drift


class TestDriftDetection:
    def test_no_drift_identical_data(self):
        """No drift when current data equals reference data."""
        reference = pd.DataFrame({"feature": [1.0, 2.0, 3.0, 4.0, 5.0] * 20})
        current = pd.DataFrame({"feature": [1.0, 2.0, 3.0, 4.0, 5.0] * 20})
        result = detect_data_drift(reference, current, ["feature"])
        assert result.drifted is False
        assert result.psi < 0.2

    def test_drift_detected_large_shift(self):
        """Drift detected when current data has shifted distribution."""
        reference = pd.DataFrame({"feature": np.random.normal(0, 1, 100)})
        current = pd.DataFrame({"feature": np.random.normal(5, 1, 100)})  # shifted mean
        result = detect_data_drift(reference, current, ["feature"])
        # Should detect drift with high probability
        assert result.drifted is True or result.psi > 0.1

    def test_analyze_drift_returns_dict(self):
        """analyze_drift returns a dict with expected keys."""
        reference = pd.DataFrame({"feature": np.random.normal(0, 1, 100)})
        current = pd.DataFrame({"feature": np.random.normal(0, 1, 100)})
        result = analyze_drift(reference, current, ["feature"])
        assert "drift_result" in result
        assert "recommendation" in result
        assert "psi_threshold" in result

    def test_drift_result_has_required_fields(self):
        """DriftResult has all required fields."""
        result = detect_data_drift(
            pd.DataFrame({"feature": np.random.normal(0, 1, 100)}),
            pd.DataFrame({"feature": np.random.normal(0, 1, 100)}),
            ["feature"]
        )
        assert hasattr(result, "drifted")
        assert hasattr(result, "psi")
        assert hasattr(result, "ks_stat")
        assert hasattr(result, "ks_pvalue")
        assert hasattr(result, "drift_type")
        assert hasattr(result, "affected_features")
        assert hasattr(result, "details")

    def test_analyze_drift_no_drift_recommendation(self):
        """No drift → no_action recommendation."""
        reference = pd.DataFrame({"feature": np.random.normal(0, 1, 100)})
        current = pd.DataFrame({"feature": np.random.normal(0, 1, 100)})
        result = analyze_drift(reference, current, ["feature"])
        assert result["recommendation"] == "no_action"