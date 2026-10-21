"""Real-time SSE event bus for approval notifications (Maker-Checker 4-Eyes dual-control).

Supports local in-memory fanout with optional Redis Pub/Sub distributed backplane
for multi-replica deployments.
"""

import asyncio
import json
import logging
import uuid
from datetime import UTC, datetime
from typing import Any

from app.config import settings

logger = logging.getLogger(__name__)


class ApprovalEventBus:
    """Pub/sub event bus delivering real-time approval updates to connected SSE clients.

    When Redis is configured via `redis_url` or `REDIS_URL`, events are published to a
    shared Redis channel (`approval:events`) and forwarded across all cluster replicas.
    When Redis is absent or unreachable, the bus gracefully degrades to in-process delivery.
    """

    def __init__(
        self,
        max_queue_size: int = 100,
        channel: str = "approval:events",
        redis_client: Any = None,
    ):
        self._subscribers: set[asyncio.Queue[str]] = set()
        self._lock = asyncio.Lock()
        self._max_queue_size = max_queue_size
        self._channel = channel
        self._redis_client = redis_client
        self._instance_id = uuid.uuid4().hex[:12]
        self._listener_task: asyncio.Task[None] | None = None
        self._pubsub: Any = None
        self._started = False

    async def _ensure_redis_connected(self) -> Any:
        if self._redis_client is not None:
            return self._redis_client
        redis_url = settings.redis_url.strip()
        if not redis_url:
            return None
        try:
            import redis.asyncio as aioredis

            self._redis_client = aioredis.from_url(redis_url, decode_responses=True)
            return self._redis_client
        except Exception as exc:
            logger.warning("Could not initialize Redis client for SSE backplane: %s", exc)
            return None

    async def _redis_listener_loop(self) -> None:
        """Background task that reads events from Redis Pub/Sub and delivers to local queues."""
        client = await self._ensure_redis_connected()
        if client is None:
            return
        try:
            self._pubsub = client.pubsub()
            await self._pubsub.subscribe(self._channel)
            logger.info("SSE Redis backplane listening on channel '%s'", self._channel)
            async for message in self._pubsub.listen():
                if message and message.get("type") == "message":
                    raw_payload = message.get("data")
                    if isinstance(raw_payload, str):
                        try:
                            parsed = json.loads(raw_payload)
                            if parsed.get("origin") == self._instance_id:
                                continue  # Already delivered locally on publishing node
                        except Exception:
                            pass
                        await self._deliver_local(raw_payload)
        except asyncio.CancelledError:
            pass
        except Exception as exc:
            logger.warning("SSE Redis backplane listener exited: %s", exc)
        finally:
            if self._pubsub:
                try:
                    await self._pubsub.unsubscribe(self._channel)
                    await self._pubsub.close()
                except Exception:
                    pass

    async def start(self) -> None:
        """Start distributed Redis backplane listener if configured."""
        if self._started:
            return
        self._started = True
        redis_url = settings.redis_url.strip()
        if redis_url or self._redis_client is not None:
            self._listener_task = asyncio.create_task(self._redis_listener_loop())

    async def stop(self) -> None:
        """Gracefully stop listener and close connection."""
        if self._listener_task:
            self._listener_task.cancel()
            try:
                await self._listener_task
            except asyncio.CancelledError:
                pass
            self._listener_task = None
        if self._redis_client:
            try:
                await self._redis_client.close()
            except Exception:
                pass
            self._redis_client = None
        self._started = False

    async def subscribe(self) -> asyncio.Queue[str]:
        if not self._started and (settings.redis_url.strip() or self._redis_client is not None):
            await self.start()
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

    async def _deliver_local(self, encoded: str) -> int:
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

    async def publish(self, event_type: str, data: dict[str, Any]) -> int:
        payload = {
            "event": event_type,
            "data": data,
            "timestamp": datetime.now(UTC).isoformat(),
            "origin": self._instance_id,
        }
        encoded = json.dumps(payload, ensure_ascii=False)

        # 1. If Redis is configured, broadcast to cluster
        client = await self._ensure_redis_connected()
        if client is not None:
            try:
                await client.publish(self._channel, encoded)
            except Exception as exc:
                logger.warning(
                    "Failed to publish SSE event to Redis, degrading to local queue: %s", exc
                )

        # 2. Local in-memory delivery to this pod's active listeners
        return await self._deliver_local(encoded)


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
