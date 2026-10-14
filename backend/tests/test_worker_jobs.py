"""Focused safety tests for the durable background-job worker."""

from __future__ import annotations

import asyncio
import uuid
from pathlib import Path

from app import worker
from app.models.activity import ActivityEvent, Job, OutboxEvent


class _ScalarResult:
    def __init__(self, value):
        self._value = value

    def scalar_one_or_none(self):
        return self._value

    def scalars(self):
        return self

    def all(self):
        return self._value


class _Session:
    def __init__(self, result):
        self.result = result
        self.statements = []
        self.added = []
        self.commits = 0

    async def execute(self, statement):
        self.statements.append(statement)
        return _ScalarResult(self.result)

    def add(self, value):
        self.added.append(value)

    async def commit(self):
        self.commits += 1


def test_job_claim_uses_a_postgres_skip_locked_lease_and_persists_retry_state():
    """Only one worker can claim a due job; retry state is schema-backed."""
    expected_columns = {
        "lease_owner",
        "lease_token",
        "lease_until",
        "heartbeat_at",
        "retry_count",
        "next_attempt",
    }
    assert expected_columns <= set(Job.__table__.columns.keys())

    job = Job(id=uuid.uuid4(), type="sla_reminder", status="queued")
    session = _Session(job)

    claimed = asyncio.run(worker.claim_job(session))

    assert claimed is job
    assert job.status == "running"
    assert job.lease_owner
    assert job.lease_token
    assert job.lease_until is not None
    assert job.heartbeat_at is not None
    assert session.statements[0]._for_update_arg.skip_locked is True
    assert session.commits == 1


def test_job_lease_migration_adds_claim_indexes():
    migration = Path(__file__).parents[1] / "alembic" / "versions" / "012_job_leases.py"
    source = migration.read_text()

    for field in (
        "lease_owner",
        "lease_token",
        "lease_until",
        "heartbeat_at",
        "retry_count",
        "next_attempt",
        "ix_jobs_claimable",
    ):
        assert field in source


def test_outbox_dispatch_creates_an_activity_event_before_marking_published():
    """The dispatcher turns durable outbox rows into durable activity rows."""
    event = OutboxEvent(
        id=uuid.uuid4(),
        event_type="inventory.request.posted",
        aggregate_id=str(uuid.uuid4()),
        payload_json={"status": "posted"},
        attempts=0,
    )
    session = _Session([event])

    dispatched = asyncio.run(worker.dispatch_outbox(session))

    assert dispatched == 1
    assert event.published_at is not None
    assert event.attempts == 1
    activities = [row for row in session.added if isinstance(row, ActivityEvent)]
    assert len(activities) == 1
    assert activities[0].outbox_event_id == event.id
    assert activities[0].type == event.event_type
    assert session.commits == 1


def test_worker_uses_existing_inventory_request_and_stock_level_models():
    """A scheduled SLA/threshold job must use ORM models that actually exist."""
    source = Path(worker.__file__).read_text()

    assert "StockRequest" not in source
    assert "InventoryRequest" in source
    assert "StockLevel" in source
