"""Langfuse AI Observability & Tracing for QuanLyKho.

Provides non-blocking, opt-in tracing for AI operations (assess_request, generate).
Fail-safe: when LANGFUSE_ENABLED is false or keys are not set, all tracing operations
are silent no-ops and never raise exceptions or impede core inventory/banking flows.
"""

from __future__ import annotations

import logging
import os
import re
from typing import Any

from app.config import Settings

logger = logging.getLogger("bankops.observability")

try:
    from langfuse import Langfuse
except ImportError:  # pragma: no cover
    Langfuse = None  # type: ignore[assignment,misc]

_client: Any = None
_client_initialized: bool = False

# Sensitive field patterns to redact in logged metadata or inputs
_SENSITIVE_KEYS = {"password", "secret", "pin", "token", "authorization", "api_key", "supervisor_pin"}
_CARD_OR_PIN_PATTERN = re.compile(r"\b(?:\d{4}[ -]?){3}\d{4}\b")


def mask_sensitive_data(data: Any) -> Any:
    """Recursively mask secrets and sensitive identifiers before tracing."""
    if isinstance(data, dict):
        masked: dict[str, Any] = {}
        for k, v in data.items():
            if any(s in str(k).lower() for s in _SENSITIVE_KEYS):
                masked[k] = "[REDACTED]"
            else:
                masked[k] = mask_sensitive_data(v)
        return masked
    elif isinstance(data, list):
        return [mask_sensitive_data(item) for item in data]
    elif isinstance(data, str):
        if len(data) > 30 and re.match(r"^sk-[A-Za-z0-9_-]+", data):
            return "[REDACTED_API_KEY]"
        return _CARD_OR_PIN_PATTERN.sub("[REDACTED_CARD]", data)
    return data


def get_langfuse_client(settings: Settings | None = None) -> Any:
    """Retrieve or initialize singleton Langfuse client with fail-safe fallback."""
    global _client, _client_initialized
    if _client_initialized:
        return _client

    if Langfuse is None:
        _client = None
        _client_initialized = True
        return None

    # Load from settings if provided, else check environment
    enabled = settings.langfuse_enabled if settings else os.getenv("LANGFUSE_ENABLED", "").lower() in ("1", "true", "yes")
    pub_key = (settings.langfuse_public_key if settings else "") or os.getenv("LANGFUSE_PUBLIC_KEY", "")
    secret_key = ""
    if settings and settings.langfuse_secret_key:
        secret_key = settings.langfuse_secret_key.get_secret_value()
    if not secret_key:
        secret_key = os.getenv("LANGFUSE_SECRET_KEY", "")
    host = (settings.langfuse_host if settings else "") or os.getenv("LANGFUSE_HOST", "https://cloud.langfuse.com")

    if enabled and pub_key and secret_key:
        try:
            _client = Langfuse(public_key=pub_key, secret_key=secret_key, host=host)
            logger.info("Langfuse tracing initialized (host=%s, pk=%s...)", host, pub_key[:8])
        except Exception as exc:  # pragma: no cover
            logger.warning("Failed to initialize Langfuse client: %s", exc)
            _client = None
    else:
        _client = None

    _client_initialized = True
    return _client


def record_ai_generation(
    name: str,
    model: str,
    input_data: Any,
    output_data: Any,
    metadata: dict[str, Any] | None = None,
    trace_id: str | None = None,
    user_id: str | None = None,
    session_id: str | None = None,
    latency_ms: float | None = None,
    settings: Settings | None = None,
) -> str | None:
    """Record an AI generation span with sanitized inputs and outputs."""
    client = get_langfuse_client(settings)
    if client is None:
        return None

    try:
        sanitized_input = mask_sensitive_data(input_data)
        sanitized_output = mask_sensitive_data(output_data)
        sanitized_metadata = mask_sensitive_data(metadata or {})
        if latency_ms is not None:
            sanitized_metadata["latency_ms"] = round(latency_ms, 2)

        gen = client.generation(
            name=name,
            model=model,
            input=sanitized_input,
            output=sanitized_output,
            metadata=sanitized_metadata,
            trace_id=trace_id,
            user_id=user_id,
            session_id=session_id,
        )
        return getattr(gen, "id", None) or name
    except Exception as exc:  # pragma: no cover
        logger.debug("Error recording Langfuse generation: %s", exc)
        return None


def flush_langfuse(settings: Settings | None = None) -> None:
    """Flush pending Langfuse events synchronously or queue them for ingestion."""
    client = get_langfuse_client(settings)
    if client is None:
        return
    try:
        client.flush()
    except Exception as exc:  # pragma: no cover
        logger.debug("Error flushing Langfuse client: %s", exc)


def reset_client_for_testing() -> None:
    """Reset the singleton client state (useful in test suites with monkeypatch)."""
    global _client, _client_initialized
    _client = None
    _client_initialized = False
