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
* DAG serialize được bằng Airflow (``SerializedDAG``) — tức Airflow thật
  chấp nhận DAG này, không chỉ import được trong pytest.

DAG covered:
- ``inventory_ingestion``: read → parse → validate → load staging → train ML → promote
- ``expense_ingestion`` / ``supplier_ingestion``: read → parse → validate → load staging
"""

from __future__ import annotations

import importlib
import inspect
import sys
from pathlib import Path

import pytest

BACKEND_DIR = Path(__file__).resolve().parents[1]
AIRFLOW_DAGS_DIR = Path(__file__).resolve().parents[2] / "infra" / "airflow" / "dags"

for _candidate in (str(BACKEND_DIR), str(AIRFLOW_DAGS_DIR)):
    if _candidate not in sys.path:
        sys.path.insert(0, _candidate)

pytest.importorskip("airflow", reason="Airflow not installed – DAG tests skipped")

INVENTORY_TASKS = [
    "read_source",
    "parse_rows",
    "validate_rows",
    "load_staging",
    "train_demand_model",
    "promote_demand_model",
]
INGEST_TASKS = ["read_source", "parse_rows", "validate_rows", "load_staging"]

EXPECTED_DAGS = {
    "inventory_ingestion": INVENTORY_TASKS,
    "expense_ingestion": INGEST_TASKS,
    "supplier_ingestion": INGEST_TASKS,
}

DAG_MODULE_NAMES = sorted(EXPECTED_DAGS)


def _dag(dag_id: str):
    module = importlib.import_module(dag_id)
    dag = getattr(module, "dag", None)
    assert dag is not None, f"Module {dag_id} không expose đối tượng `dag`"
    return dag


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
        assert not inspect.isfunction(callable_) or callable_.__name__ != "<lambda>", (
            f"Task {task.task_id} dùng lambda — không serialize được cho Airflow"
        )
        assert getattr(callable_, "__name__", "") != "<lambda>"
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
    """catchup/schedule/max_active_runs/default_args hợp lệ."""
    dag = _dag(dag_id)
    assert dag.catchup is False, "catchup phải là False"
    assert dag.max_active_runs == 1, "max_active_runs phải bằng 1"
    assert dag.schedule is not None and str(dag.schedule) == "@daily"
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
    """Airflow serialize được DAG (chứng minh DAG thật, không chỉ import được)."""
    from airflow.serialization.serialized_objects import DagSerialization

    dag = _dag(dag_id)
    payload = DagSerialization.serialize_dag(dag)
    assert payload["dag_id"] == dag_id
    assert payload["catchup"] is False

    serialized_tasks = []
    for entry in payload["tasks"]:
        var = entry.get("__var") or entry.get("value") or {}
        serialized_tasks.append(var)

    assert {t["task_id"] for t in serialized_tasks} == set(EXPECTED_DAGS[dag_id])

    from qlk_ingest import tasks as qlk_tasks

    for task in serialized_tasks:
        callable_name = task["python_callable_name"]
        assert callable_name in {
            "read_source",
            "parse_rows",
            "validate_rows",
            "load_staging",
            "train_demand_model",
            "promote_demand_model",
        }, f"Task {task['task_id']} serialize thành callable lạ: {callable_name}"
        assert callable( getattr(qlk_tasks, callable_name) ), (
            f"Callable {callable_name} không import được từ qlk_ingest.tasks"
        )
