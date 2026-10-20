"""Unit tests for app.api.middleware.correlation — CorrelationIdMiddleware."""

from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock

from app.api.middleware.correlation import CorrelationIdMiddleware


class TestCorrelationIdMiddleware:
    def test_init_stores_app(self):
        mock_app = MagicMock()
        mw = CorrelationIdMiddleware(mock_app)
        assert mw.app is mock_app

    def test_non_http_scope_passes_through(self):
        async def run():
            mock_app = AsyncMock()
            mw = CorrelationIdMiddleware(mock_app)
            scope = {"type": "lifespan"}
            await mw(scope, AsyncMock(), AsyncMock())
            mock_app.assert_called_once()

        import asyncio

        asyncio.run(run())

    def test_http_scope_generates_ids_when_missing(self):
        async def run():
            mock_app = AsyncMock()
            mw = CorrelationIdMiddleware(mock_app)
            scope = {
                "type": "http",
                "headers": [],
            }
            receive = AsyncMock()
            send = AsyncMock()
            await mw(scope, receive, send)
            # App was called with modified scope
            call_args = mock_app.call_args
            assert call_args is not None
            modified_scope = call_args[0][0]
            headers = dict(modified_scope["headers"])
            assert b"x-correlation-id" in headers
            assert b"x-request-id" in headers
            assert headers[b"x-correlation-id"] != b""
            assert headers[b"x-request-id"] != b""

        import asyncio

        asyncio.run(run())

    def test_http_scope_preserves_existing_ids(self):
        async def run():
            mock_app = AsyncMock()
            mw = CorrelationIdMiddleware(mock_app)
            scope = {
                "type": "http",
                "headers": [
                    (b"x-correlation-id", b"existing-cid"),
                    (b"x-request-id", b"existing-rid"),
                ],
            }
            receive = AsyncMock()
            send = AsyncMock()
            await mw(scope, receive, send)
            modified_scope = mock_app.call_args[0][0]
            headers = dict(modified_scope["headers"])
            assert headers[b"x-correlation-id"] == b"existing-cid"
            assert headers[b"x-request-id"] == b"existing-rid"

        import asyncio

        asyncio.run(run())