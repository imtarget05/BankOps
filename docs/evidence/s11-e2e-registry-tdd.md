# S11 registry verification TDD evidence

**Scope:** The S11 registry step must fail closed when training did not create
a registered model. It must emit a small JSON artifact only after inspecting
the configured MLflow tracking store.

| Stage | Command | Result | Guarantee |
|---|---|---|---|
| RED | `DATABASE_URL=...bankops_test poetry run pytest tests/test_e2e_verify.py -q` | Failed with `AttributeError: module 'e2e_verify' has no attribute 'verify_registry'` | The previous command-only script had no testable, fail-closed contract. |
| GREEN | Same command | `1 passed` | Missing model versions yield `{status: failed, reason: no_model_versions}` rather than a successful workflow. |
| Static check | `poetry run ruff check scripts/e2e_verify.py tests/test_e2e_verify.py` | Passed | The command and its contract test meet the repository lint rules. |

The workflow now trains a synthetic model before invoking the gate and uploads
`backend/evidence/e2e-registry.json`. This is registry evidence only. Airflow
execution and an Azure deployment remain separate, unverified gates until a
properly bootstrapped runtime produces their own evidence.
