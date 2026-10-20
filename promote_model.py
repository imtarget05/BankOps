import mlflow
import sys

mlflow.set_tracking_uri("sqlite:///./mlflow.db")
client = mlflow.tracking.MlflowClient()
versions = client.search_model_versions("name=\"DemandForecastModel\"")
if versions:
    latest = versions[0]
    client.transition_model_version_stage(
        name="DemandForecastModel",
        version=str(latest.version),
        stage="Production"
    )
    print(f"Promoted version {latest.version} to Production")
else:
    print("No model versions found - checking for any registered model...")
    versions = client.search_model_versions("name=\"DemandForecastModel\"")
    if versions:
        latest = versions[0]
        print(f"Found version {latest.version} but no promotion needed")
    else:
        print("No DemandForecastModel found")
sys.exit(0)
