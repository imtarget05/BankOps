"""Unit tests for Langfuse AI Observability in QuanLyKho."""

from __future__ import annotations

import unittest.mock as mock
from pydantic import SecretStr

from app.config import Settings
from app.core.observability import (
    flush_langfuse,
    get_langfuse_client,
    mask_sensitive_data,
    record_ai_generation,
    reset_client_for_testing,
)


def test_mask_sensitive_data():
    sample = {
        "user": "Alice",
        "password": "SuperSecretPassword123!",
        "auth_token": "Bearer sk-1234567890abcdef1234567890abcdef",
        "notes": "Card is 4111 2222 3333 4444 here",
        "nested": {
            "pin": "1234",
            "normal_field": 42,
        },
        "items": [
            {"name": "Tea", "supervisor_pin": "9999"},
            {"name": "Sugar", "qty": 10},
        ],
    }
    masked = mask_sensitive_data(sample)
    assert masked["user"] == "Alice"
    assert masked["password"] == "[REDACTED]"
    assert masked["auth_token"] == "[REDACTED]"
    assert "[REDACTED_CARD]" in masked["notes"]
    assert masked["nested"]["pin"] == "[REDACTED]"
    assert masked["nested"]["normal_field"] == 42
    assert masked["items"][0]["supervisor_pin"] == "[REDACTED]"
    assert masked["items"][1]["qty"] == 10


def test_langfuse_client_disabled_by_default():
    reset_client_for_testing()
    settings = Settings(
        database_url="sqlite://",
        langfuse_enabled=False,
    )
    client = get_langfuse_client(settings)
    assert client is None
    # Tracing calls must be silent no-ops
    res = record_ai_generation(
        name="test",
        model="gpt-4o",
        input_data={"foo": "bar"},
        output_data={"baz": "qux"},
        settings=settings,
    )
    assert res is None
    flush_langfuse(settings)


def test_langfuse_client_enabled_with_keys(monkeypatch):
    reset_client_for_testing()
    settings = Settings(
        database_url="sqlite://",
        langfuse_enabled=True,
        langfuse_public_key="pk-lf-test",
        langfuse_secret_key=SecretStr("sk-lf-test"),
        langfuse_host="https://mock.langfuse.com",
    )

    mock_langfuse_cls = mock.MagicMock()
    mock_instance = mock.MagicMock()
    mock_gen = mock.MagicMock()
    mock_gen.id = "gen-123"
    mock_instance.generation.return_value = mock_gen
    mock_langfuse_cls.return_value = mock_instance

    monkeypatch.setattr("app.core.observability.Langfuse", mock_langfuse_cls)

    client = get_langfuse_client(settings)
    assert client is not None
    mock_langfuse_cls.assert_called_once_with(
        public_key="pk-lf-test",
        secret_key="sk-lf-test",
        host="https://mock.langfuse.com",
    )

    gen_id = record_ai_generation(
        name="ai.assess_request",
        model="qwen-2.5",
        input_data={"request_id": "REQ-1", "user_password": "secret"},
        output_data={"summary": "ok"},
        metadata={"source": "test"},
        latency_ms=125.456,
        settings=settings,
    )
    assert gen_id == "gen-123"
    mock_instance.generation.assert_called_once()
    call_kwargs = mock_instance.generation.call_args.kwargs
    assert call_kwargs["name"] == "ai.assess_request"
    assert call_kwargs["input"]["user_password"] == "[REDACTED]"
    assert call_kwargs["metadata"]["latency_ms"] == 125.46

    flush_langfuse(settings)
    mock_instance.flush.assert_called_once()
    reset_client_for_testing()


@pytest.mark.asyncio
async def test_ai_services_record_to_langfuse(monkeypatch):
    import httpx
    from app.services.ai import assess_request, generate

    reset_client_for_testing()
    settings = Settings(
        database_url="sqlite://",
        ai_provider="modal_llm",
        modal_llm_url="https://mock.modal.run/v1/chat/completions",
        modal_llm_model="Qwen2.5-1.5B",
        langfuse_enabled=True,
        langfuse_public_key="pk-lf-test",
        langfuse_secret_key=SecretStr("sk-lf-test"),
    )

    mock_langfuse_cls = mock.MagicMock()
    mock_instance = mock.MagicMock()
    mock_langfuse_cls.return_value = mock_instance
    monkeypatch.setattr("app.core.observability.Langfuse", mock_langfuse_cls)

    # 1. Test generate with modal_llm
    def fake_handler(req: httpx.Request):
        return httpx.Response(200, json={"choices": [{"message": {"content": "Xin chao"}}]})

    async with httpx.AsyncClient(transport=httpx.MockTransport(fake_handler)) as http_client:
        res = await generate("Chao ban", settings, http_client)
        assert res["answer"] == "Xin chao"

    # Verify Langfuse generation was recorded
    assert mock_instance.generation.called
    gen_call = mock_instance.generation.call_args.kwargs
    assert gen_call["name"] == "ai.generate"
    assert gen_call["input"] == "Chao ban"
    assert gen_call["output"] == "Xin chao"
    assert gen_call["model"] == "Qwen2.5-1.5B"
    assert mock_instance.flush.called
    reset_client_for_testing()

