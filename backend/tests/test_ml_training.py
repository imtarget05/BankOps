# ML Training Pipeline Tests (Phase M — S4)
# Test-first: RED → GREEN → REFACTOR
import os
import sys

sys.path.insert(0, os.path.dirname(__file__) + "/../..")

import numpy as np
import pandas as pd

from app.services.ml_training import (
    generate_synthetic_inventory_demand,
    run_full_pipeline,
    time_aware_split,
    train_demand_forecast_model,
)


class TestGenerateSyntheticData:
    def test_generate_data_returns_dataframe(self):
        """Synthetic data generation produces a DataFrame with expected columns."""
        df = generate_synthetic_inventory_demand(n_periods=50, seed=99)
        assert isinstance(df, pd.DataFrame)
        assert {"ds", "y", "month"}.issubset(set(df.columns))
        assert len(df) == 50

    def test_data_has_positive_demand(self):
        """Demand values should be non-negative."""
        df = generate_synthetic_inventory_demand(n_periods=10, seed=1)
        assert (df["y"] >= 0).all()

    def test_different_seeds_different_data(self):
        """Two different seeds should produce different data (high probability)."""
        df1 = generate_synthetic_inventory_demand(n_periods=30, seed=42)
        df2 = generate_synthetic_inventory_demand(n_periods=30, seed=123)
        assert not df1.equals(df2)


class TestTimeAwareSplit:
    def test_split_returns_two_dataframes(self):
        """Chronological split returns train and test DataFrames."""
        df = generate_synthetic_inventory_demand(n_periods=40, seed=7)
        train, test = time_aware_split(df, train_ratio=0.75)
        assert isinstance(train, pd.DataFrame)
        assert isinstance(test, pd.DataFrame)
        # Train should be earlier periods, test should be later
        assert train["ds"].max() <= test["ds"].min()

    def test_split_ratio_0_8(self):
        """With 120 periods and 0.8 ratio, train should have 96 rows."""
        df = generate_synthetic_inventory_demand(n_periods=120, seed=42)
        train, test = time_aware_split(df, train_ratio=0.8)
        assert len(train) == 96, f"Expected 96, got {len(train)}"
        assert len(test) == 24, f"Expected 24, got {len(test)}"

    def test_no_future_leakage(self):
        """Max train ds <= min test ds (strict temporal ordering)."""
        df = generate_synthetic_inventory_demand(n_periods=100, seed=42)
        train, test = time_aware_split(df, train_ratio=0.8)
        assert train["ds"].max() <= test["ds"].min()


class TestTrainModel:
    def test_train_returns_dict_with_metrics(self):
        """Training function returns dict with run_id and metrics."""
        df = generate_synthetic_inventory_demand(n_periods=60, seed=42)
        train, test = time_aware_split(df, train_ratio=0.8)
        result = train_demand_forecast_model(train, test, experiment_name="test-exp")
        assert "run_id" in result
        assert "mae" in result
        assert "rmse" in result
        assert "r2" in result
        assert "train_size" in result
        assert "test_size" in result

    def test_metrics_are_finite_numbers(self):
        """MAE, RMSE, R2 should be finite numbers."""
        df = generate_synthetic_inventory_demand(n_periods=60, seed=42)
        train, test = time_aware_split(df, train_ratio=0.8)
        result = train_demand_forecast_model(train, test)
        assert np.isfinite(result["mae"])
        assert np.isfinite(result["rmse"])
        assert -1 <= result["r2"] <= 1  # R2 can be negative for bad models

    def test_r2_expects_positive_for_baseline(self):
        """With simple trend + seasonality, baseline model should achieve positive R2."""
        df = generate_synthetic_inventory_demand(n_periods=120, seed=42)
        train, test = time_aware_split(df, train_ratio=0.8)
        result = train_demand_forecast_model(train, test)
        assert result["r2"] > 0, f"Expected positive R2 for baseline, got {result['r2']:.4f}"


class TestFullPipeline:
    def test_run_full_pipeline_returns_dict(self):
        """Full pipeline end-to-end returns a result dict."""
        result = run_full_pipeline(n_periods=40, train_ratio=0.75, seed=42)
        assert isinstance(result, dict)
        assert "run_id" in result
        assert "mae" in result
        assert "rmse" in result
        assert "r2" in result

    def test_pipeline_produces_finite_metrics(self):
        """Pipeline metrics should all be finite."""
        result = run_full_pipeline(n_periods=60, train_ratio=0.8, seed=42)
        assert np.isfinite(result["mae"])
        assert np.isfinite(result["rmse"])
        assert np.isfinite(result["r2"])

    def test_pipeline_r2_positive(self):
        """Pipeline should achieve positive R2 with sufficient data."""
        result = run_full_pipeline(n_periods=120, train_ratio=0.8, seed=42)
        assert result["r2"] > 0, f"Expected positive R2, got {result['r2']:.4f}"