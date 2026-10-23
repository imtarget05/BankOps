"""FastAPI serving smoke test for the S11 gate (fail-closed).

It exercises the SERVING app — `app.api.inference:app` (Phase M — S6), which
owns `GET /health` and `POST /predict`. The monolith `app.main:app` does NOT
mount the inference router, so pointing this script there was hitting a 404.

Exit code: 0 only when health and predict both answer HTTP 200 with a real
prediction; any other outcome exits 1 so the CI gate actually closes.
"""

import sys

from fastapi.testclient import TestClient

from app.api.inference import app

client = TestClient(app)

failures: list[str] = []

print("Testing /health endpoint...")
health_response = client.get('/health')
print(f"  Health status: {health_response.status_code}")
if health_response.status_code != 200:
    failures.append(f"/health returned {health_response.status_code}")

print("Testing /predict endpoint...")
predict_response = client.post(
    "/predict",
    json={"period": 1, "month": 6},
)
print(f"  Predict status: {predict_response.status_code}")
predicted_demand = None
if predict_response.status_code == 200:
    data = predict_response.json()
    predicted_demand = data.get("predicted_demand")
    print(f"  Predicted demand: {predicted_demand if predicted_demand is not None else 'N/A'}")
    print(f"  Model version: {data.get('model_version', 'N/A')}")
else:
    failures.append(f"/predict returned {predict_response.status_code}")
    if predict_response.text:
        print(f"  Error: {predict_response.text[:200]}")

if not failures:
    print("  FastAPI serving test PASSED")
    sys.exit(0)

print("  FastAPI serving test FAILED")
for failure in failures:
    print(f"  - {failure}")
sys.exit(1)
