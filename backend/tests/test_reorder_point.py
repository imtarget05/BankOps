"""Tests for reorder_point service (Phase 2 — P2.2).

Runs *before* touching the API layer: unit-level correctness only.
Uses synthetic data; no DB, no MLflow dependency.

Run:
    cd backend && python -m pytest tests/test_reorder_point.py -v
"""

from decimal import Decimal

import pytest

from app.services.reorder_point import (
    _risk_level,
    calculate_reorder_point,
    detect_anomaly,
)


import pytest

from app.services.reorder_point import (
    _risk_level,
    calculate_reorder_point,
    detect_anomaly,
)


class TestCalculateReorderPoint:
    """T-01: Reorder point math correctness (no DB, no MLflow)."""

    def test_basic_reorder_point(self):
        forecast = [40, 50, 60, 50, 45, 55, 50, 45, 55, 50]
        result = calculate_reorder_point(
            forecast_values=forecast,
            lead_time_days=7,
            service_level=0.95,
        )
        assert result["avg_daily_demand"] == Decimal("50.0000")
        assert result["z_score"] == Decimal("1.6449")  # 95%
        assert result["reorder_point"] > Decimal("350")  # demand * lead time

    def test_anomaly_flag_when_below_reorder_point(self):
        # Scenario: stock is below reorder point
        forecast = [100, 110, 95, 105, 100]
        result = calculate_reorder_point(
            forecast_values=forecast,
            lead_time_days=3,
            service_level=0.95,
            current_stock=100,
        )
        assert result["needs_order"] is True
        assert result["risk_level"] in ("critical", "warning")

    def test_low_variance_bounded(self):
        # Scenario: constant demand, zero variance
        forecast = [50] * 10
        result = calculate_reorder_point(
            forecast_values=forecast,
            lead_time_days=14,
            current_stock=0,
        )
        assert result["std_demand"] == Decimal("0.0000")
        assert result["reorder_point"] > Decimal("0")

    def test_service_level_adjusts_z(self):
        # 95% vs 99% should give different safety stock
        forecast = [100, 110, 95, 105, 100]  # has variance
        r95 = calculate_reorder_point(forecast_values=forecast, lead_time_days=7, service_level=0.95)
        r99 = calculate_reorder_point(forecast_values=forecast, lead_time_days=7, service_level=0.99)
        assert r95["safety_stock"] < r99["safety_stock"]


class TestDetectAnomaly:
    """T-02: Demand anomaly detection (z-score based)."""

    def test_normal_demand(self):
        result = detect_anomaly(
            actual_demand=100,
            expected_demand=100,
            std_demand=10,
            threshold_z=2.5,
        )
        assert result["is_anomaly"] is False
        assert result["severity"] == "none"

    def test_spike_demand(self):
        result = detect_anomaly(
            actual_demand=150,
            expected_demand=100,
            std_demand=10,
            threshold_z=2.5,
        )
        assert result["is_anomaly"] is True
        assert result["direction"] == "spike"
        assert result["severity"] == "high"

    def test_dip_demand(self):
        result = detect_anomaly(
            actual_demand=60,
            expected_demand=100,
            std_demand=10,
            threshold_z=2.5,
        )
        assert result["is_anomaly"] is True
        assert result["direction"] == "dip"

    def test_zero_variance(self):
        result = detect_anomaly(
            actual_demand=100,
            expected_demand=100,
            std_demand=0,
            threshold_z=2.5,
        )
        assert result["is_anomaly"] is False
        assert result["reason"].startswith("Zero variance")


class TestRiskLevel:
    """T-03: Risk classification."""

    def test_critical(self):
        assert _risk_level(
            needs_order=True,
            current_stock=Decimal("10"),
            reorder_point=Decimal("50"),
        ) == "critical"

    def test_warning(self):
        assert _risk_level(
            needs_order=True,
            current_stock=Decimal("30"),
            reorder_point=Decimal("50"),
        ) == "warning"

    def test_healthy(self):
        assert _risk_level(
            needs_order=False,
            current_stock=Decimal("100"),
            reorder_point=Decimal("50"),
        ) == "healthy"
