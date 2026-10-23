#!/usr/bin/env python3
"""CLI entry point for promoting model with R² gate.

Used by CI workflow to enforce R² ≥ 0.7 before promoting to Production.
"""
import os
import sys

# Ensure backend is on path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from app.services import ml_registry


def main() -> int:
    tracking_uri = os.environ.get('MLFLOW_TRACKING_URI')
    if not tracking_uri:
        print("ERROR: MLFLOW_TRACKING_URI not set", file=sys.stderr)
        return 1

    model_name = os.environ.get('MODEL_NAME', 'DemandForecastModel')
    threshold = float(os.environ.get('PROMOTION_THRESHOLD_R2', '0.7'))
    to_stage = os.environ.get('PROMOTION_STAGE', 'Production')

    ml_registry.set_tracking_uri(tracking_uri)
    result = ml_registry.promote_model_with_r2_gate(
        model_name=model_name,
        threshold=threshold,
        to_stage=to_stage,
    )

    print(f"Promotion result: {result}")
    return 0 if result['success'] else 1


if __name__ == '__main__':
    sys.exit(main())