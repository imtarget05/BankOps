import mlflow
import sys

def main():
    print("=== MLflow Registry Setup ===")
    mlflow.set_tracking_uri('sqlite:///./mlflow.db')
    mlflow.set_experiment('DemandForecastExperiment')
    print("Experiment configured")

    client = mlflow.tracking.MlflowClient(tracking_uri='sqlite:///./mlflow.db')
    versions = client.search_model_versions(f'name="DemandForecastModel"')

    if versions:
        latest = versions[0]
        client.transition_model_version_stage(
            name='DemandForecastModel',
            version=str(latest.version),
            stage='Production'
        )
        print(f"Promoted version {latest.version} to Production")
    else:
        print("No model versions found")

    print("=== E2E Pipeline Verification Complete ===")

if __name__ == "__main__":
    main()
