"""B1.5 — retention của durable Idempotency-Key (cửa sổ 24h).

Cơ chế retention (xem `backend/app/services/idempotency.py`):
- Mỗi lần claim/store ghi `expires_at = now + 24h` (`_RETENTION_SECONDS`).
- Bản ghi HẾT HẠN bị dọn (purge) khi có đủ số lần claim (`_PURGE_EVERY`).
- Store in-memory cũng tự dọn theo cùng cửa sổ.

Test dùng **timestamp inject** (monkeypatch `time.time` / chèn `expires_at` quá khứ
trực tiếp) nên KHÔNG phải `sleep` — chạy nhanh và không phụ thuộc đồng hồ thật.

Bản thân `app/services/idempotency.py` KHÔNG được sửa ở bước này; test chỉ
quan sát hành vi.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import select

from app.models.idempotency import IdempotencyKey
from app.services import idempotency


@pytest.fixture(scope="module")
def sync_engine():
    engine = idempotency._get_sync_engine()
    yield engine
    engine.dispose()


def _insert_row(engine, key: str, *, expires_at: datetime, scope: str = "test") -> None:
    import uuid as _uuid

    with engine.begin() as conn:
        conn.execute(
            IdempotencyKey.__table__.insert().values(
                id=_uuid.uuid4(),
                key=key,
                scope=scope,
                request_hash=idempotency.payload_hash({"amount": 1}),
                status_code=None,
                response_body=None,
                created_at=datetime.now(UTC),
                updated_at=datetime.now(UTC),
                expires_at=expires_at,
            )
        )


def _exists(engine, key: str) -> bool:
    with engine.connect() as conn:
        return (
            conn.execute(
                select(IdempotencyKey.__table__.c.key).where(
                    IdempotencyKey.__table__.c.key == key
                )
            ).first()
            is not None
        )


def test_retention_window_matches_config():
    """Cửa sổ retention = `idempotency_key_retention_hours` (mặc định 24h)."""
    from app.config import settings

    assert settings.idempotency_key_retention_hours == 24
    assert idempotency._RETENTION_SECONDS == 24 * 3600


def test_in_memory_store_purges_expired_entries(monkeypatch):
    """Store in-memory: entry cũ hơn 24h bị dọn, entry còn hạn thì giữ."""
    now = 1_000_000.0
    monkeypatch.setattr(idempotency.time, "time", lambda: now)

    old_key = f"mem-old-{uuid.uuid4().hex}"
    fresh_key = f"mem-fresh-{uuid.uuid4().hex}"
    idempotency._store[old_key] = ("h", 200, {}, now - (25 * 3600))
    idempotency._store[fresh_key] = ("h", 200, {}, now - (23 * 3600))

    idempotency._purge_expired()

    assert old_key not in idempotency._store, "entry quá hạn phải bị dọn"
    assert fresh_key in idempotency._store, "entry còn hạn phải được giữ"

    idempotency._store.pop(old_key, None)
    idempotency._store.pop(fresh_key, None)


def test_durable_claim_sets_expiry_24h_in_the_future(sync_engine):
    """Claim mới -> `expires_at` = now + 24h (không giữ vô hạn)."""
    key = f"ret-claim-{uuid.uuid4().hex}"
    before = datetime.now(UTC)

    claimed = idempotency._durable_claim(key, idempotency.payload_hash({"a": 1}))

    assert claimed is True
    with sync_engine.connect() as conn:
        expires_at = conn.execute(
            select(IdempotencyKey.__table__.c.expires_at).where(
                IdempotencyKey.__table__.c.key == key
            )
        ).scalar()
    assert expires_at is not None, "bản ghi durable PHẢI có `expires_at`"
    delta = expires_at - before
    assert timedelta(hours=23) < delta <= timedelta(hours=24, minutes=1), (
        f"`expires_at` phải cách `now` ~24h, thấy {delta}"
    )


def test_expired_durable_rows_are_purged(sync_engine, monkeypatch):
    """Bản ghi đã hết hạn bị dọn khi đủ số lần claim (không giữ vô hạn)."""
    expired_key = f"ret-expired-{uuid.uuid4().hex}"
    live_key = f"ret-live-{uuid.uuid4().hex}"
    now = datetime.now(UTC)

    _insert_row(sync_engine, expired_key, expires_at=now - timedelta(hours=1))
    _insert_row(sync_engine, live_key, expires_at=now + timedelta(hours=10))
    assert _exists(sync_engine, expired_key) is True

    # Chuẩn bị tới ngưỡng purge: chỉ cần 1 claim nữa là dọn.
    monkeypatch.setattr(idempotency, "_claims_since_purge", idempotency._PURGE_EVERY - 1)

    fresh_key = f"ret-fresh-{uuid.uuid4().hex}"
    assert idempotency._durable_claim(fresh_key, idempotency.payload_hash({"b": 2})) is True

    assert _exists(sync_engine, expired_key) is False, (
        "bản ghi idempotency đã hết hạn phải bị dọn, không giữ vô hạn"
    )
    assert _exists(sync_engine, live_key) is True, (
        "bản ghi còn hạn KHÔNG được dọn"
    )
    assert _exists(sync_engine, fresh_key) is True


def test_expired_row_is_still_replayable_until_purged(sync_engine):
    """`expires_at` là cửa sổ DỌN (GC), CHƯA phải hạn sử dụng của key.

    Ghi nhận hành vi hiện tại: một key đã quá 24h nhưng CHƯA được purge vẫn
    được replay response cũ. Client sinh key ngẫu nhiên (uuid) nên rủi ro
    thấp, nhưng đây là điểm cần biết — xem residual risk trong báo cáo B1.5.
    """
    key = f"ret-replay-{uuid.uuid4().hex}"
    _insert_row(
        sync_engine,
        key,
        expires_at=datetime.now(UTC) - timedelta(minutes=5),
    )
    with sync_engine.begin() as conn:
        conn.execute(
            IdempotencyKey.__table__.update()
            .where(IdempotencyKey.__table__.c.key == key)
            .values(status_code=200, response_body={"ok": True})
        )

    record = idempotency._durable_lookup(key)
    assert record is not None
    assert record[1] == 200


def test_purge_runs_on_a_bounded_threshold():
    """Purge chạy theo ngưỡng số lần claim (không quét DB mỗi request)."""
    assert idempotency._PURGE_EVERY > 0
    assert idempotency._RETENTION_SECONDS > 0
