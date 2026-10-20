import sys
sys.path.insert(0, '/app')
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

print("Testing /health endpoint...")
health_response = client.get('/health')
print(f"  Health status: {health_response.status_code}")

print("Testing /predict endpoint...")
predict_response = client.post(
    "/predict",
    json={"period": 1, "month": 6}
)
print(f"  Predict status: {predict_response.status_code}")
if predict_response.status_code == 200:
    data = predict_response.json()
    print(f"  Predicted demand: {data.get('predicted_demand', 'N/A')}")
    print(f"  Model version: {data.get('model_version', 'N/A')}")
    print("  FastAPI serving test PASSED")
else:
    print(f"  FastAPI serving test FAILED (status {predict_response.status_code})")
    if predict_response.text:
        print(f"  Error: {predict_response.text[:200]}")
