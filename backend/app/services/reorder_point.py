"""AI Reorder Point Optimization (Phase 2 — P2.2).

Tính toán điểm đặt hàng tối thiểu dựa trên:
- Demand forecast từ model MLflow
- Lead time (ngày)
- Desired service level (Z-score)

Công thức:
    Reorder Point = (Avg Daily Demand × Lead Time) + Safety Stock
    Safety Stock = Z × σ_demand × √(Lead Time)
"""

from decimal import Decimal
from typing import Any

# Z-score lookup for common service levels
Z_SCORE = {
    "0.8000": 0.8416,
    "0.8500": 1.0364,
    "0.9000": 1.2816,
    "0.9500": 1.6449,
    "0.9900": 2.3263,
}


def _z_score(service_level: float) -> float:
    """Get Z-score for a service level; fallback to 95%."""
    key = f"{service_level:.4f}"
    return float(Z_SCORE.get(key, Z_SCORE["0.9500"]))


def calculate_reorder_point(
    forecast_values: list[float],
    lead_time_days: float,
    service_level: float = 0.95,
    current_stock: float = 0.0,
    min_order_quantity: float = 1.0,
    max_stock: float = 0.0,
) -> dict[str, Any]:
    """Calculate optimal reorder point and related metrics.

    Args:
        forecast_values: List of demand predictions (1 period = 1 day by default).
        lead_time_days: Time from order placement to receipt (days).
        service_level: Desired service level (0-1). Default 0.95.
        current_stock: Current inventory quantity (absolute, not forecast).
        min_order_quantity: Minimum order quantity (MOQ).
        max_stock: Maximum stock level cap.

    Returns:
        Dict with reorder_point, safety_stock, avg_daily_demand, z_score,
        and actionable flags.
    """
    if not forecast_values:
        raise ValueError("forecast_values must not be empty")

    avg_demand = sum(forecast_values) / len(forecast_values)
    variance = sum((x - avg_demand) ** 2 for x in forecast_values) / len(forecast_values)
    std_demand = variance ** 0.5

    demand_during_lead_time = avg_demand * lead_time_days
    sigma_lead_time = std_demand * (lead_time_days ** 0.5)
    z = _z_score(service_level)
    safety_stock = z * sigma_lead_time
    reorder_point = demand_during_lead_time + safety_stock

    # Convert to Decimal for precision (required in this codebase)
    reorder_point_dec = Decimal(str(round(reorder_point, 2)))
    current_stock_dec = Decimal(str(current_stock))
    safety_stock_dec = Decimal(str(round(safety_stock, 2)))
    min_order_quant_dec = Decimal(str(min_order_quantity))
    max_stock_dec = Decimal(str(max_stock)) if max_stock > 0 else None

    # Actionable flags
    needs_order = current_stock_dec <= reorder_point_dec

    # Suggested order quantity (fill gap up to reorder point, or at least MOQ)
    if max_stock_dec is not None:
        gap_to_max = (reorder_point_dec - current_stock_dec + max_stock_dec) / 2
        suggested_qty = max(
            min_order_quant_dec,
            min(gap_to_max, max_stock_dec - current_stock_dec),
        )
    else:
        suggested_qty = max(min_order_quant_dec, reorder_point_dec - current_stock_dec)

    return {
        "reorder_point": reorder_point_dec,
        "safety_stock": safety_stock_dec,
        "avg_daily_demand": Decimal(str(round(avg_demand, 4))),
        "std_demand": Decimal(str(round(std_demand, 4))),
        "z_score": Decimal(str(round(z, 4))),
        "lead_time_days": lead_time_days,
        "service_level": Decimal(str(round(service_level, 4))),
        "needs_order": bool(needs_order),
        "suggested_order_quantity": Decimal(str(round(suggested_qty, 2))),
        "current_stock": Decimal(str(current_stock)),
        "risk_level": _risk_level(needs_order, current_stock_dec, reorder_point_dec),
    }


def _risk_level(
    needs_order: bool,
    current_stock: Decimal,
    reorder_point: Decimal,
) -> str:
    """Determine reorder risk level."""
    if needs_order and current_stock <= reorder_point * Decimal("0.5"):
        return "critical"
    if needs_order:
        return "warning"
    return "healthy"
def detect_anomaly(
    actual_demand: float,
    expected_demand: float,
    std_demand: float,
    threshold_z: float = 2.5,
) -> dict[str, Any]:
    """Detect demand anomaly (unusually high/low demand).

    Uses Z-score based detection:
        z = (actual - expected) / std
        |z| > threshold → anomaly

    Returns:
        Dict with is_anomaly, z_score, direction, severity.
    """
    if std_demand <= 0:
        return {
            "is_anomaly": False,
            "z_score": Decimal("0.0"),
            "direction": "unknown",
            "severity": "none",
            "reason": "Zero variance in forecast; cannot detect anomaly.",
        }

    z = (actual_demand - expected_demand) / std_demand
    is_anomaly = abs(z) > threshold_z

    if z > threshold_z:
        direction = "spike"
        severity = "high"
    elif z < -threshold_z:
        direction = "dip"
        severity = "high"
    elif abs(z) > threshold_z * 0.7:
        direction = "above_expected" if z > 0 else "below_expected"
        severity = "medium"
    else:
        direction = "normal"
        severity = "none"

    return {
        "is_anomaly": bool(is_anomaly),
        "z_score": Decimal(str(round(z, 4))),
        "direction": direction,
        "severity": severity,
        "expected_demand": Decimal(str(round(expected_demand, 4))),
        "actual_demand": Decimal(str(round(actual_demand, 4))),
        "threshold_z": threshold_z,
        "reason": _anomaly_reason(z),
    }


def _anomaly_reason(z: float) -> str:
    """Generate human-readable reason for anomaly detection."""
    if z > 0:
        return f"Demand {z:.2f}σ above expected (spike)"
    if z < 0:
        return f"Demand {abs(z):.2f}σ below expected (dip)"
    return "Unusual flat demand"

