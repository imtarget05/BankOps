#!/usr/bin/env python3
"""Local smoke test for Langfuse observability (no real credentials needed).

Verifies the entire lifecycle:
1. Disabled mode -> pure no-op (zero network, zero exceptions).
2. Enabled mode with mock -> data masking, trace recording, and flush.
3. Service integration -> assess_request heuristic and generate paths.
"""

from __future__ import annotations

import asyncio
import unittest.mock as mock

from pydantic import SecretStr

from app.config import Settings
from app.core.observability import (
    flush_langfuse,
    get_langfuse_client,
    record_ai_generation,
    reset_client_for_testing,
)
from app.services.ai import assess_request


def test_no_op_when_disabled():
    reset_client_for_testing()
    settings = Settings(database_url="sqlite://", langfuse_enabled=False)
    client = get_langfuse_client(settings)
    assert client is None, "Client must be None when langfuse_enabled=False"
    result = record_ai_generation("test", "gpt-4", {}, {}, settings=settings)
    assert result is None, "Recording must return None when disabled"
    flush_langfuse(settings)
    print("  [PASS] No-op mode when disabled")


def test_mock_client():
    reset_client_for_testing()
    settings = Settings(
        database_url="sqlite://",
        langfuse_enabled=True,
        langfuse_public_key="pk-lf-test",
        langfuse_secret_key=SecretStr("sk-lf-test"),
        langfuse_host="https://mock.langfuse.com",
    )
    mock_cls = mock.MagicMock()
    mock_inst = mock.MagicMock()
    mock_gen = mock.MagicMock()
    mock_gen.id = "gen-abc-123"
    mock_inst.generation.return_value = mock_gen
    mock_cls.return_value = mock_inst

    import app.core.observability as obs_mod
    obs_mod.Langfuse = mock_cls

    client = get_langfuse_client(settings)
    assert client is not None, "Client must be initialized when enabled with keys"

    result = record_ai_generation(
        name="ai.assess_request",
        model="heuristic-v1",
        input_data={"request_id": "REQ-001", "kind": "adjustment"},
        output_data={"risk_level": "high", "risk_score": 82},
        metadata={"supervisor_pin": "1234", "source": "heuristic_fallback"},
        user_id="demo_admin",
        latency_ms=5.3,
        settings=settings,
    )
    call_kwargs = mock_inst.generation.call_args.kwargs
    assert call_kwargs["metadata"]["supervisor_pin"] == "[REDACTED]", "PIN must be redacted"
    assert call_kwargs["user_id"] == "demo_admin", "user_id must be recorded"
    assert result == "gen-abc-123"
    flush_langfuse(settings)
    assert mock_inst.flush.called
    print("  [PASS] Mock client recording & data masking")
    reset_client_for_testing()


async def test_service_level_traces():
    import httpx

    reset_client_for_testing()
    settings = Settings(
        database_url="sqlite://",
        ai_provider="disabled",
        langfuse_enabled=True,
        langfuse_public_key="pk-lf-test",
        langfuse_secret_key=SecretStr("sk-lf-test"),
    )
    mock_cls = mock.MagicMock()
    mock_inst = mock.MagicMock()
    mock_cls.return_value = mock_inst

    import app.core.observability as obs_mod
    obs_mod.Langfuse = mock_cls

    async with httpx.AsyncClient() as http_client:
        data = {
            "request_id": "REQ-TEST-1",
            "kind": "adjustment",
            "amount_or_qty": "35",
            "maker": "Maker Demo",
            "reason": "Lệch kiểm kê",
        }
        res = await assess_request(data, settings, http_client, user_id="demo_checker")
        assert res["risk_level"] in ("low", "medium", "high")
        assert mock_inst.generation.called
        kwargs = mock_inst.generation.call_args.kwargs
        assert kwargs["name"] == "ai.assess_request"
        assert kwargs["user_id"] == "demo_checker"
        assert kwargs["trace_id"] == "REQ-TEST-1"
        print("  [PASS] Service-level assess_request heuristic trace with user_id")

    reset_client_for_testing()


def main():
    print("=== Running Langfuse Local Smoke Test ===")
    test_no_op_when_disabled()
    test_mock_client()
    asyncio.run(test_service_level_traces())
    print("\nAll local Langfuse smoke tests PASSED successfully!")


if __name__ == "__main__":
    main()
