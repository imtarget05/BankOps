"""Test cấu trúc DAG Airflow của QuanLyKho (Phase M — S2).

Trước đây file này assert ``len(task_ids) >= 0`` — tức **vacuous green**: DAG
có thể rỗng mà test vẫn xanh.  Bản này assert có ý nghĩa:

* mỗi DAG import được và **có task (> 0)**;
* ``dag.task_ids`` khớp đúng danh sách task khai báo;
* mọi task **đã gắn đúng DAG** (``task.dag is dag``) — trước đây operator
  chưa gắn vào DAG nên `operator.dag` ném ``RuntimeError``;
* ``python_callable`` là **hàm thật** (không phải ``lambda``/``lambda: None``)
  và nằm trong module ``qlk_ingest.tasks`` (serialize được cho Airflow);
* chuỗi phụ thuộc ``>>`` nối liền từ task đầu tới task cuối;
* cấu hình DAG hợp lệ: ``catchup=False``, ``max_active_runs=1``,
  ``schedule='@daily'``, ``default_args`` có ``owner``/``retries``/
  ``retry_delay``/``start_date``;
* DAG serialize được bằng Airflow — tức Airflow thật chấp nhận DAG này, không
  chỉ import được trong pytest;
* mỗi file DAG **parse được** và **gán `dag` ở cấp module** (kiểm tra ``ast`` —
  hợp nhất hướng kiểm tra cú pháp của ``main``; hỗ trợ cả ``dag = DAG(...)``
  lẫn ``with DAG(...) as dag:``).

**Tương thích nhiều version Airflow** (2.10.x và 3.x):

* Airflow 2.10 đặt lịch ở ``dag.schedule_interval`` và **không có**
  ``dag.schedule``; Airflow 3.x ngược lại — bỏ ``schedule_interval``, chỉ có
  ``schedule``.  Test đọc cả hai nên không phụ thuộc version.
* Class serializer của Airflow bị đổi tên theo version
  (``SerializedDAG`` ở 2.10.4, ``DagSerialization`` ở 3.x).  Test dò class
  theo tên thay vì import thẳng một tên cụ thể.

**Không còn skip im lặng.**  Airflow là *runtime bắt buộc* của module này:

* nếu Airflow **thiếu** → test ``skip`` kèm lý do rõ ràng;
* nếu job CI **bắt buộc** phải có Airflow (``QLK_REQUIRE_AIRFLOW=1``, đặt trong
  workflow ``.github/workflows/s11-e2e-cloud-ci.yml``) → test **fail** với thông
  báo lỗi, không được biến thành xanh vacuous.

DAG covered:
- ``inventory_ingestion``: read → parse → validate → load staging → train ML → promote → detect drift
- ``expense_ingestion`` / ``supplier_ingestion``: read → parse → validate → load staging
"""

from __future__ import annotations

import ast
import importlib
import inspect
import os
import sys
from pathlib import Path

import pytest

BACKEND_DIR = Path(__file__).resolve().parents[1]
AIRFLOW_DAGS_DIR = Path(__file__).resolve().parents[2] / "infra" / "airflow" / "dags"

for _candidate in (str(BACKEND_DIR), str(AIRFLOW_DAGS_DIR)):
    if _candidate not in sys.path:
        sys.path.insert(0, _candidate)

# --- Airflow là runtime bắt buộc: import thẳng để lỗi import được báo rõ ----
def _airflow_runtime_unavailable() -> str | None:
    """``None`` nếu Airflow dùng được; ngược lại trả lý do **không** dùng được.

    "Không dùng được" gồm 2 trường hợp: chưa cài Airflow, hoặc cài rồi nhưng
    thiếu provider (``airflow.providers.standard`` ở Airflow 3.x — đây chính là
    lỗi làm CI xanh vacuous trước đây: Airflow cài ở *system python* còn pytest
    chạy trong venv khác).
    """
    try:
        importlib.import_module("airflow")
    except Exception as exc:  # pragma: no cover - phụ thuộc môi trường
        return f"import `airflow` lỗi: {exc}"

    try:
        importlib.import_module("inventory_ingestion")
    except ModuleNotFoundError as exc:  # pragma: no cover - phụ thuộc môi trường
        missing = exc.name or ""
        if missing == "airflow" or missing.startswith("airflow."):
            return f"import DAG lỗi vì thiếu `{missing}`: {exc}"
        raise
    return None

#: Job CI bắt buộc phải có Airflow sẽ đặt ``QLK_REQUIRE_AIRFLOW=1``.
#: Khi đó thiếu Airflow ⇒ **fail**, không phải skip (chống CI xanh vacuous).
REQUIRE_AIRFLOW = os.environ.get("QLK_REQUIRE_AIRFLOW", "").strip().lower() in {
    "1",
    "true",
    "yes",
}

INVENTORY_TASKS = [
    "read_source",
    "parse_rows",
    "validate_rows",
    "load_staging",
    "train_demand_model",
    "promote_demand_model",
    "detect_drift",
]
INGEST_TASKS = ["read_source", "parse_rows", "validate_rows", "load_staging"]

EXPECTED_DAGS = {
    "inventory_ingestion": INVENTORY_TASKS,
    "expense_ingestion": INGEST_TASKS,
    "supplier_ingestion": INGEST_TASKS,
}

DAG_MODULE_NAMES = sorted(EXPECTED_DAGS)

#: Mọi file DAG ở cấp thư mục dags (bỏ qua file ẩn và file bắt đầu bằng ``_``).
DAG_FILES = sorted(
    path
    for path in AIRFLOW_DAGS_DIR.glob("*.py")
    if not path.name.startswith("_") and not path.name.startswith(".")
)

EXPECTED_CALLABLES = {
    "read_source",
    "parse_rows",
    "validate_rows",
    "load_staging",
    "train_demand_model",
    "promote_demand_model",
    "detect_drift",
}


@pytest.fixture(autouse=True)
def airflow_runtime() -> None:
    """Guard runtime: nếu Airflow biến mất giữa chừng thì phải báo, không im lặng."""
    reason = _airflow_runtime_unavailable()
    assert reason is None, f"Airflow không dùng được nữa: {reason}"


_AIRFLOW_UNAVAILABLE = _airflow_runtime_unavailable()
if _AIRFLOW_UNAVAILABLE is not None:
    _MESSAGE = (
        "Airflow chưa dùng được trong môi trường này nên không kiểm chứng được "
        f"DAG: {_AIRFLOW_UNAVAILABLE}. Cài `apache-airflow` (kèm provider cần thiết) "
        "vào ĐÚNG môi trường đang chạy pytest, hoặc đặt QLK_REQUIRE_AIRFLOW=1 để "
        "biến thiếu Airflow thành lỗi CI. Xem "
        "docs/mlops/airflow-ingest-evidence-2026-10-20.md."
    )
    if REQUIRE_AIRFLOW:
        # Job CI bắt buộc có Airflow: thiếu là LỖI (collection error ⇒ job đỏ),
        # tuyệt đối không được biến thành xanh vacuous.
        raise RuntimeError(_MESSAGE)
    # Job CI không cần Airflow: bỏ qua nhưng **có lý do rõ ràng** (không phải
    # skip im lặng của `pytest.importorskip`).
    pytest.skip(_MESSAGE, allow_module_level=True)


def _dag(dag_id: str):
    module = importlib.import_module(dag_id)
    dag = getattr(module, "dag", None)
    assert dag is not None, f"Module {dag_id} không expose đối tượng `dag`"
    return dag


def _dag_schedule(dag) -> str:
    """Lịch của DAG, tương thích Airflow 2.x (``schedule_interval``) và 3.x (``schedule``)."""
    for attr in ("schedule", "schedule_interval"):
        value = getattr(dag, attr, None)
        if value is not None:
            return str(value)
    return ""


def _is_daily(schedule: str) -> bool:
    """``@daily`` (Airflow 2/3) hoặc biểu thức cron tương đương (``0 0 * * *``)."""
    normalized = schedule.strip()
    return normalized in {"@daily", "0 0 * * *", "0 0 * * ?", "0 0 * * * *"}


def _serializer_class():
    """Class serializer của Airflow: tên đổi theo version (2.10 vs 3.x)."""
    from airflow.serialization import serialized_objects

    for name in ("DagSerialization", "SerializedDAG"):
        candidate = getattr(serialized_objects, name, None)
        if candidate is not None and hasattr(candidate, "serialize_dag"):
            return candidate
    return None


def _payload_task_ids(payload: dict) -> set[str]:
    """Task id trong payload serialize (shape khác nhau giữa 2.x và 3.x)."""
    task_ids: set[str] = set()
    for entry in payload.get("tasks") or []:
        if not isinstance(entry, dict):
            continue
        var = entry.get("__var")
        if not isinstance(var, dict):
            var = entry
        task_id = var.get("task_id")
        if task_id:
            task_ids.add(str(task_id))
    return task_ids


def _payload_callable_names(payload: dict) -> list[str]:
    """Tên ``python_callable`` trong payload (chỉ có ở một số version Airflow)."""
    names: list[str] = []
    for entry in payload.get("tasks") or []:
        if not isinstance(entry, dict):
            continue
        var = entry.get("__var")
        if not isinstance(var, dict):
            var = entry
        name = var.get("python_callable_name")
        if name:
            names.append(str(name))
    return names


# ---------------------------------------------------------------------------
# 0. Syntax + binding `dag` ở cấp module (kiểm tra AST — hợp nhất hướng của main)
# ---------------------------------------------------------------------------


def _module_bound_names(tree: ast.AST) -> set[str]:
    """Tên được gán ở cấp module, gồm CẢ HAI dạng khai báo DAG:

    * ``dag = DAG(...)``        → ``ast.Assign``
    * ``with DAG(...) as dag:`` → ``ast.With`` / ``ast.AsyncWith``
    """
    names: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name):
                    names.add(target.id)
        elif isinstance(node, ast.With | ast.AsyncWith):
            for item in node.items:
                optional_vars = item.optional_vars
                if isinstance(optional_vars, ast.Name):
                    names.add(optional_vars.id)
    return names


@pytest.mark.parametrize("dag_file", DAG_FILES, ids=lambda path: path.stem)
def test_dag_file_is_valid_python_and_binds_a_dag(dag_file: Path) -> None:
    """File DAG phải parse được VÀ gán một đối tượng `dag` ở cấp module.

    Giữ assert của hướng ``ast.parse`` ở ``main``: bắt được DAG hỏng cú pháp
    hoặc DAG không export ``dag`` — kể cả khi Airflow không cài trong môi
    trường đang chạy. Không vacuous: ``ast.parse`` ném ``SyntaxError`` ⇒ test
    fail, và tên ``dag`` phải thật sự được gán.
    """
    source = dag_file.read_text(encoding="utf-8")
    tree = ast.parse(source)  # SyntaxError ⇒ test fail với thông báo rõ ràng
    assert "dag" in _module_bound_names(tree), (
        f"DAG file {dag_file.name} không gán đối tượng `dag` ở cấp module"
    )


# ---------------------------------------------------------------------------
# 1. Import + cấu trúc task
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("dag_id", DAG_MODULE_NAMES)
def test_dag_imports_and_has_expected_tasks(dag_id: str) -> None:
    """Mỗi DAG import được và khai báo đúng danh sách task (> 0)."""
    dag = _dag(dag_id)
    expected = EXPECTED_DAGS[dag_id]
    assert len(expected) > 0
    assert len(dag.task_ids) > 0, f"DAG {dag_id} không có task nào"
    assert sorted(dag.task_ids) == sorted(expected), (
        f"DAG {dag_id} task_ids={dag.task_ids} khác kỳ vọng {expected}"
    )


@pytest.mark.parametrize("dag_id", DAG_MODULE_NAMES)
def test_every_task_is_attached_to_its_dag(dag_id: str) -> None:
    """Operator phải gắn đúng DAG (trước đây `operator.dag` → RuntimeError)."""
    dag = _dag(dag_id)
    for task in dag.tasks:
        assert task.dag is dag, f"Task {task.task_id} của {dag_id} chưa gắn vào DAG"
        assert task.has_dag()


@pytest.mark.parametrize("dag_id", DAG_MODULE_NAMES)
def test_task_callables_are_real_functions(dag_id: str) -> None:
    """`python_callable` phải là hàm thật, không phải lambda/placeholder."""
    dag = _dag(dag_id)
    for task in dag.tasks:
        callable_ = getattr(task, "python_callable", None)
        assert callable_ is not None, f"Task {task.task_id} không có python_callable"
        assert getattr(callable_, "__name__", "") != "<lambda>", (
            f"Task {task.task_id} dùng lambda — không serialize được cho Airflow"
        )
        assert getattr(callable_, "__module__", "").startswith("qlk_ingest.tasks"), (
            f"Task {task.task_id} phải gọi hàm trong qlk_ingest.tasks, "
            f"thực tế: {getattr(callable_, '__module__', None)}"
        )
        assert inspect.isfunction(callable_), (
            f"Task {task.task_id} python_callable phải là function, "
            f"thực tế: {type(callable_)}"
        )
        source = inspect.getsource(callable_)
        assert "lambda: None" not in source
        assert "placeholder" not in source.lower()


@pytest.mark.parametrize("dag_id", DAG_MODULE_NAMES)
def test_task_dependencies_form_a_single_chain(dag_id: str) -> None:
    """Chuỗi `>>` nối liền: task đầu không có upstream, task cuối không có downstream."""
    dag = _dag(dag_id)
    tasks = {t.task_id: t for t in dag.tasks}
    expected = EXPECTED_DAGS[dag_id]

    first = tasks[expected[0]]
    last = tasks[expected[-1]]
    assert not first.upstream_task_ids, f"{expected[0]} phải là task đầu chuỗi"
    assert not last.downstream_task_ids, f"{expected[-1]} phải là task cuối chuỗi"

    for upstream_id, downstream_id in zip(expected, expected[1:], strict=False):
        assert downstream_id in tasks[upstream_id].downstream_task_ids, (
            f"{upstream_id} chưa truyền cho {downstream_id}"
        )
        assert upstream_id in tasks[downstream_id].upstream_task_ids


@pytest.mark.parametrize("dag_id", DAG_MODULE_NAMES)
def test_dag_configuration_is_production_sane(dag_id: str) -> None:
    """catchup/schedule/max_active_runs/default_args hợp lệ (đọc được trên 2.x và 3.x)."""
    dag = _dag(dag_id)
    assert dag.catchup is False, "catchup phải là False"
    assert dag.max_active_runs == 1, "max_active_runs phải bằng 1"
    schedule = _dag_schedule(dag)
    assert schedule, "DAG không có lịch (schedule/schedule_interval rỗng)"
    assert _is_daily(schedule), f"schedule={schedule!r} — DAG phải chạy @daily"
    assert dag.tags, "DAG phải có tags"

    default_args = dag.default_args or {}
    assert default_args.get("owner"), "default_args thiếu owner"
    assert default_args.get("start_date") is not None, "default_args thiếu start_date"
    assert int(default_args.get("retries", 0)) >= 1, "default_args thiếu retries hợp lý"
    assert default_args.get("retry_delay") is not None, "default_args thiếu retry_delay"


@pytest.mark.parametrize("dag_id", DAG_MODULE_NAMES)
def test_dag_has_no_placeholder_source(dag_id: str) -> None:
    """File DAG không được chứa `lambda: None` / comment placeholder."""
    source = (AIRFLOW_DAGS_DIR / f"{dag_id}.py").read_text(encoding="utf-8")
    assert "lambda: None" not in source, f"{dag_id}.py còn placeholder `lambda: None`"
    assert "placeholder" not in source.lower(), f"{dag_id}.py còn comment placeholder"


@pytest.mark.parametrize("dag_id", DAG_MODULE_NAMES)
def test_dag_is_serializable_by_airflow(dag_id: str) -> None:
    """Airflow serialize được DAG (chứng minh DAG thật, không chỉ import được).

    Tên class serializer khác nhau giữa Airflow 2.10 (``SerializedDAG``) và 3.x
    (``DagSerialization``) nên test dò theo tên, không import cứng một tên.
    """
    serializer = _serializer_class()
    assert serializer is not None, (
        "Airflow không expose class serialize_dag — bản Airflow này không được hỗ trợ"
    )

    dag = _dag(dag_id)
    payload = serializer.serialize_dag(dag)
    assert isinstance(payload, dict)

    payload_dag_id = payload.get("dag_id") or payload.get("_dag_id")
    assert payload_dag_id == dag_id
    assert payload.get("catchup") is False

    assert _payload_task_ids(payload) == set(EXPECTED_DAGS[dag_id])

    # `python_callable_name` chỉ xuất hiện ở một số version Airflow; nếu có thì
    # phải trỏ đúng hàm trong qlk_ingest.tasks.
    for callable_name in _payload_callable_names(payload):
        assert callable_name in EXPECTED_CALLABLES, (
            f"Task serialize thành callable lạ: {callable_name}"
        )

    from qlk_ingest import tasks as qlk_tasks

    for callable_name in EXPECTED_CALLABLES:
        assert callable(getattr(qlk_tasks, callable_name)), (
            f"Callable {callable_name} không import được từ qlk_ingest.tasks"
        )
