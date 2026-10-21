"""Cấu hình (theo biến môi trường) cho các DAG ingest của QuanLyKho.

Nguyên tắc: **không hardcode path tuyệt đối**.  Mọi đường dẫn nguồn dữ liệu,
DB đích và MLflow đều resolve theo thứ tự:

1. biến môi trường riêng của dataset (ví dụ ``QLK_INGEST_INVENTORY_SOURCE``),
2. biến môi trường chung (``QLK_INGEST_SOURCE_DIR``, ``QLK_INGEST_DATABASE_URL``,
   ``MLFLOW_TRACKING_URI``),
3. mặc định suy ra từ vị trí file trong repo (``backend/sample-data``).

DB đích bị **chặn an toàn**: nếu tên database không chứa ``test`` thì task
từ chối ghi, trừ khi bật ``QLK_INGEST_ALLOW_ANY_DB=1``.  Nhờ vậy DAG không
bao giờ ghi nhầm vào database dev ``bankops``.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[4]
BACKEND_DIR = REPO_ROOT / "backend"
DAGS_DIR = REPO_ROOT / "infra" / "airflow" / "dags"
SEED_DIR = DAGS_DIR / "seed"
DEFAULT_SAMPLE_DATA_DIR = BACKEND_DIR / "sample-data"

DEFAULT_STAGING_TABLE = "qlk_ingest_staging"
MLFLOW_EXPERIMENT = "inventory-demand"
MLFLOW_MODEL_NAME = "DemandForecastModel"


@dataclass(frozen=True)
class SourceSpec:
    """Mô tả một nguồn dữ liệu đầu vào của DAG."""

    dataset: str
    default_path: Path
    env_var: str
    collection: str | None
    required_fields: tuple[str, ...]
    business_key: str
    numeric_fields: tuple[str, ...] = ()


SOURCES: dict[str, SourceSpec] = {
    "inventory": SourceSpec(
        dataset="inventory",
        default_path=DEFAULT_SAMPLE_DATA_DIR / "inventory.json",
        env_var="QLK_INGEST_INVENTORY_SOURCE",
        collection="items",
        required_fields=("sku", "name"),
        business_key="sku",
    ),
    "expense": SourceSpec(
        dataset="expense",
        default_path=SEED_DIR / "expenses.csv",
        env_var="QLK_INGEST_EXPENSE_SOURCE",
        collection=None,
        required_fields=("expense_ref", "amount", "currency"),
        business_key="expense_ref",
        numeric_fields=("amount",),
    ),
    "supplier": SourceSpec(
        dataset="supplier",
        default_path=SEED_DIR / "suppliers.csv",
        env_var="QLK_INGEST_SUPPLIER_SOURCE",
        collection=None,
        required_fields=("supplier_code", "name"),
        business_key="supplier_code",
    ),
}


@dataclass(frozen=True)
class ResolvedSource:
    """Nguồn dữ liệu đã resolve (đường dẫn cụ thể + kiểu nguồn)."""

    dataset: str
    path: Path
    collection: str | None
    required_fields: tuple[str, ...]
    business_key: str
    numeric_fields: tuple[str, ...]
    env_var: str

    @property
    def source_type(self) -> str:
        suffix = self.path.suffix.lower()
        if suffix == ".json":
            return "json"
        if suffix in (".csv", ".txt"):
            return "csv"
        return "csv"


def resolve_source(dataset: str) -> ResolvedSource:
    """Resolve nguồn dữ liệu cho một dataset (fail-closed nếu tên lạ)."""
    spec = SOURCES.get(dataset)
    if spec is None:
        raise KeyError(f"Dataset không hợp lệ: {dataset!r}; hợp lệ: {sorted(SOURCES)}")

    override = os.environ.get(spec.env_var)
    if override:
        path = Path(override).expanduser()
    else:
        base = os.environ.get("QLK_INGEST_SOURCE_DIR")
        path = (Path(base).expanduser() / spec.default_path.name) if base else spec.default_path
    return ResolvedSource(
        dataset=spec.dataset,
        path=path,
        collection=spec.collection,
        required_fields=spec.required_fields,
        business_key=spec.business_key,
        numeric_fields=spec.numeric_fields,
        env_var=spec.env_var,
    )


def staging_table_name() -> str:
    """Tên bảng staging (mặc định ``qlk_ingest_staging``)."""
    return os.environ.get("QLK_INGEST_STAGING_TABLE", DEFAULT_STAGING_TABLE)


def resolve_database_url() -> str:
    """URL database đích cho bảng staging (fail-closed nếu chưa cấu hình)."""
    url = os.environ.get("QLK_INGEST_DATABASE_URL") or os.environ.get("DATABASE_URL")
    if not url:
        raise RuntimeError(
            "Chưa cấu hình database đích cho DAG ingest. "
            "Set QLK_INGEST_DATABASE_URL (ưu tiên) hoặc DATABASE_URL."
        )
    if not _database_allowed(url):
        raise RuntimeError(
            "Từ chối ghi staging vào database không phải môi trường test: "
            f"{_database_name(url)!r}. Hãy dùng database disposable có chứa 'test' "
            "hoặc set QLK_INGEST_ALLOW_ANY_DB=1 nếu thực sự cần."
        )
    return url


def _database_name(url: str) -> str:
    tail = url.rsplit("/", 1)[-1]
    return tail.split("?", 1)[0]


def _database_allowed(url: str) -> bool:
    if os.environ.get("QLK_INGEST_ALLOW_ANY_DB", "").lower() in ("1", "true", "yes", "on"):
        return True
    if url.startswith("sqlite"):
        return True
    return "test" in _database_name(url).lower()


def resolve_mlflow_tracking_uri() -> str:
    """Tracking URI cho MLflow (mặc định sqlite trong ``AIRFLOW_HOME``)."""
    uri = os.environ.get("QLK_INGEST_MLFLOW_TRACKING_URI") or os.environ.get("MLFLOW_TRACKING_URI")
    if uri:
        return uri
    base = Path(os.environ.get("AIRFLOW_HOME") or Path.cwd())
    return f"sqlite:///{base / 'mlflow.db'}"


def resolve_mlflow_artifact_dir() -> Path:
    """Thư mục lưu artifact MLflow (mặc định ``<AIRFLOW_HOME>/mlruns``)."""
    override = os.environ.get("QLK_INGEST_MLFLOW_ARTIFACT_DIR")
    if override:
        return Path(override).expanduser()
    base = Path(os.environ.get("AIRFLOW_HOME") or Path.cwd())
    return base / "mlruns"


def is_strict() -> bool:
    """Fail-closed khi có dòng dữ liệu không hợp lệ (mặc định True)."""
    return os.environ.get("QLK_INGEST_STRICT", "1").lower() not in ("0", "false", "no", "off")
