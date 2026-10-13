"""Real-time SSE event bus for approval notifications (Maker-Checker 4-Eyes dual-control)."""

import asyncio
import json
import logging
from datetime import UTC, datetime
from typing import Any

logger = logging.getLogger(__name__)


class ApprovalEventBus:
    """In-memory pub/sub event bus delivering real-time approval updates to connected SSE clients."""

    def __init__(self, max_queue_size: int = 100):
        self._subscribers: set[asyncio.Queue[str]] = set()
        self._lock = asyncio.Lock()
        self._max_queue_size = max_queue_size

    async def subscribe(self) -> asyncio.Queue[str]:
        queue: asyncio.Queue[str] = asyncio.Queue(maxsize=self._max_queue_size)
        async with self._lock:
            self._subscribers.add(queue)
            count = len(self._subscribers)
        logger.debug("SSE subscriber connected. Total active listeners: %d", count)
        return queue

    async def unsubscribe(self, queue: asyncio.Queue[str]) -> None:
        async with self._lock:
            self._subscribers.discard(queue)
            count = len(self._subscribers)
        logger.debug("SSE subscriber disconnected. Remaining active listeners: %d", count)

    @property
    def subscriber_count(self) -> int:
        return len(self._subscribers)

    async def publish(self, event_type: str, data: dict[str, Any]) -> int:
        payload = {
            "event": event_type,
            "data": data,
            "timestamp": datetime.now(UTC).isoformat(),
        }
        encoded = json.dumps(payload, ensure_ascii=False)
        async with self._lock:
            subscribers = list(self._subscribers)

        delivered = 0
        for queue in subscribers:
            try:
                queue.put_nowait(encoded)
                delivered += 1
            except asyncio.QueueFull:
                try:
                    queue.get_nowait()
                    queue.put_nowait(encoded)
                    delivered += 1
                except Exception:
                    pass
        return delivered


approval_event_bus = ApprovalEventBus()


async def broadcast_approval_event(
    action: str,
    request_id: str,
    kind: str,
    status: str,
    message: str,
    meta: dict[str, Any] | None = None,
) -> int:
    """Convenience helper to broadcast an approval lifecycle event."""
    data = {
        "action": action,
        "request_id": str(request_id),
        "kind": kind,
        "status": status,
        "message": message,
    }
    if meta:
        data["meta"] = meta
    return await approval_event_bus.publish("approval_update", data)
