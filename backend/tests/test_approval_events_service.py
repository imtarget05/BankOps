"""Unit tests for app.services.approval_events — SSE event bus."""

from __future__ import annotations

import asyncio
import json

import pytest

from app.services.approval_events import (
    ApprovalEventBus,
    approval_event_bus,
    broadcast_approval_event,
)


class TestApprovalEventBus:
    def setup_method(self):
        self.bus = ApprovalEventBus(max_queue_size=10)

    @pytest.mark.asyncio
    async def test_subscribe_returns_queue(self):
        queue = await self.bus.subscribe()
        assert isinstance(queue, asyncio.Queue)
        assert self.bus.subscriber_count == 1

    @pytest.mark.asyncio
    async def test_unsubscribe_removes_queue(self):
        queue = await self.bus.subscribe()
        assert self.bus.subscriber_count == 1
        await self.bus.unsubscribe(queue)
        assert self.bus.subscriber_count == 0

    @pytest.mark.asyncio
    async def test_publish_delivers_to_all_subscribers(self):
        q1 = await self.bus.subscribe()
        q2 = await self.bus.subscribe()
        delivered = await self.bus.publish("approval_update", {"action": "approve"})
        assert delivered == 2
        msg1 = await asyncio.wait_for(q1.get(), timeout=1)
        msg2 = await asyncio.wait_for(q2.get(), timeout=1)
        payload1 = json.loads(msg1)
        payload2 = json.loads(msg2)
        assert payload1["event"] == "approval_update"
        assert payload1["data"]["action"] == "approve"
        assert payload2["event"] == "approval_update"
        assert payload2["data"]["action"] == "approve"

    @pytest.mark.asyncio
    async def test_publish_handles_queue_full(self):
        small_bus = ApprovalEventBus(max_queue_size=1)
        q = await small_bus.subscribe()
        # Fill the queue
        await small_bus.publish("event_1", {"a": 1})
        assert q.full()
        # Publish again — should evict oldest and still deliver
        delivered = await small_bus.publish("event_2", {"a": 2})
        assert delivered == 1
        msg = await asyncio.wait_for(q.get(), timeout=1)
        payload = json.loads(msg)
        assert payload["data"]["a"] == 2

    @pytest.mark.asyncio
    async def test_publish_with_no_subscribers_returns_zero(self):
        delivered = await self.bus.publish("event", {})
        assert delivered == 0


class TestBroadcastApprovalEvent:
    @pytest.mark.asyncio
    async def test_broadcast_returns_delivered_count(self):
        # Use the global bus; subscribe then broadcast
        queue = await approval_event_bus.subscribe()
        try:
            delivered = await broadcast_approval_event(
                action="approve",
                request_id="req-123",
                kind="purchase",
                status="approved",
                message="Approved by manager",
            )
            assert delivered == 1
            msg = await asyncio.wait_for(queue.get(), timeout=1)
            payload = json.loads(msg)
            assert payload["event"] == "approval_update"
            assert payload["data"]["request_id"] == "req-123"
            assert payload["data"]["kind"] == "purchase"
            assert payload["data"]["status"] == "approved"
            assert payload["data"]["message"] == "Approved by manager"
        finally:
            await approval_event_bus.unsubscribe(queue)

    @pytest.mark.asyncio
    async def test_broadcast_with_meta(self):
        queue = await approval_event_bus.subscribe()
        try:
            await broadcast_approval_event(
                action="reject",
                request_id="req-456",
                kind="refund",
                status="rejected",
                message="Insufficient funds",
                meta={"reason": "low_balance"},
            )
            msg = await asyncio.wait_for(queue.get(), timeout=1)
            payload = json.loads(msg)
            assert payload["data"]["meta"] == {"reason": "low_balance"}
        finally:
            await approval_event_bus.unsubscribe(queue)