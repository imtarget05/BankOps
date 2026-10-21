"""Tests for ApprovalEventBus with Redis Pub/Sub distributed backplane & fallback."""

import asyncio
import json
from unittest.mock import AsyncMock, MagicMock

import pytest

from app.services.approval_events import ApprovalEventBus, broadcast_approval_event


@pytest.mark.asyncio
async def test_approval_event_bus_in_memory_fallback():
    """Verify that without Redis, ApprovalEventBus delivers in-memory to subscribers."""
    bus = ApprovalEventBus(redis_client=None)
    queue = await bus.subscribe()
    assert bus.subscriber_count == 1

    delivered = await bus.publish(
        "approval_update", {"request_id": "test-123", "status": "approved"}
    )
    assert delivered == 1

    msg_raw = await asyncio.wait_for(queue.get(), timeout=1.0)
    msg = json.loads(msg_raw)
    assert msg["event"] == "approval_update"
    assert msg["data"]["request_id"] == "test-123"
    assert msg["data"]["status"] == "approved"
    assert "timestamp" in msg
    assert "origin" in msg

    await bus.unsubscribe(queue)
    assert bus.subscriber_count == 0
    await bus.stop()


@pytest.mark.asyncio
async def test_approval_event_bus_redis_pubsub_fanout():
    """Verify that when a Redis client is injected, publish forwards to Redis channel."""
    mock_redis = MagicMock()
    mock_redis.publish = AsyncMock(return_value=1)
    mock_pubsub = MagicMock()
    mock_pubsub.subscribe = AsyncMock()
    mock_pubsub.unsubscribe = AsyncMock()
    mock_pubsub.close = AsyncMock()

    # Async generator simulating incoming messages from Redis
    async def fake_listen():
        yield {
            "type": "message",
            "data": json.dumps(
                {
                    "event": "approval_update",
                    "data": {"request_id": "remote-999"},
                    "origin": "other-pod-123",
                }
            ),
        }

    mock_pubsub.listen = fake_listen
    mock_redis.pubsub.return_value = mock_pubsub

    bus = ApprovalEventBus(redis_client=mock_redis, channel="test:approval:events")
    queue = await bus.subscribe()
    assert bus.subscriber_count == 1

    # 1. Test publishing from this node
    delivered = await bus.publish(
        "approval_update", {"request_id": "req-456", "action": "approve"}
    )
    assert delivered == 1
    assert mock_redis.publish.called
    channel_called, payload_called = mock_redis.publish.call_args[0]
    assert channel_called == "test:approval:events"
    assert "req-456" in payload_called

    # Local queue received this pod's local publish:
    msg_local = await asyncio.wait_for(queue.get(), timeout=1.0)
    assert "req-456" in msg_local

    # 2. Wait for remote message from fake_listen to arrive via Redis Pub/Sub:
    msg_remote = await asyncio.wait_for(queue.get(), timeout=1.0)
    assert "remote-999" in msg_remote

    await bus.unsubscribe(queue)
    await bus.stop()


@pytest.mark.asyncio
async def test_approval_event_bus_redis_failure_degrades_gracefully():
    """Verify that if Redis throws an exception during publish, it logs and degrades to local queue."""
    mock_redis = MagicMock()
    mock_redis.publish = AsyncMock(side_effect=ConnectionError("Redis connection refused"))
    mock_pubsub = MagicMock()
    mock_pubsub.subscribe = AsyncMock(side_effect=ConnectionError("Redis down"))
    mock_redis.pubsub.return_value = mock_pubsub

    bus = ApprovalEventBus(redis_client=mock_redis)
    queue = await bus.subscribe()

    delivered = await bus.publish(
        "approval_update", {"request_id": "req-degraded", "status": "rejected"}
    )
    assert delivered == 1

    msg_raw = await asyncio.wait_for(queue.get(), timeout=1.0)
    msg = json.loads(msg_raw)
    assert msg["data"]["request_id"] == "req-degraded"

    await bus.unsubscribe(queue)
    await bus.stop()


@pytest.mark.asyncio
async def test_broadcast_approval_event_helper():
    """Verify broadcast_approval_event convenience helper formats data correctly."""
    delivered = await broadcast_approval_event(
        action="approve",
        request_id="req-helper-1",
        kind="receipt",
        status="posted",
        message="Voucher approved and inventory moved",
        meta={"lines": 3},
    )
    assert isinstance(delivered, int)
