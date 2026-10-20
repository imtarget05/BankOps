"""JSON logging with an allowlist and conservative PII/secret redaction."""
from __future__ import annotations

import json
import logging
import logging.config
import re
from datetime import UTC, datetime

from app.api.request_context import correlation_id_var, request_id_var

_SECRET_RE = re.compile(r"(?i)\b(password|token|secret|api[_-]?key)\s*[=:]\s*[^\s,;]+")
_BEARER_RE = re.compile(r"(?i)\bBearer\s+[A-Za-z0-9._~+/-]+=*")
_EMAIL_RE = re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b")
_LONG_NUMBER_RE = re.compile(r"\b\d{8,}\b")


def _redact(value: str) -> str:
    value = _BEARER_RE.sub("Bearer [REDACTED]", value)
    value = _SECRET_RE.sub(lambda match: f"{match.group(1)}=[REDACTED]", value)
    value = _EMAIL_RE.sub("[EMAIL]", value)
    return _LONG_NUMBER_RE.sub("[REDACTED_NUMBER]", value)


class SafeJsonFormatter(logging.Formatter):
    _allowed_fields = (
        "http_method",
        "http_route",
        "http_status_class",
        "duration_ms",
        "event_code",
    )

    def format(self, record: logging.LogRecord) -> str:
        message = _redact(record.getMessage())
        payload = {
            "timestamp": datetime.now(UTC).isoformat(),
            "level": record.levelname.lower(),
            "logger": record.name,
            "message": message,
            "request_id": request_id_var.get(),
            "correlation_id": correlation_id_var.get(),
        }
        trace_id = getattr(record, "otelTraceID", None)
        span_id = getattr(record, "otelSpanID", None)
        if trace_id and trace_id != "0":
            payload["trace_id"] = trace_id
        if span_id and span_id != "0":
            payload["span_id"] = span_id

        for field in self._allowed_fields:
            value = getattr(record, field, None)
            if value is not None:
                payload[field] = _redact(str(value)) if isinstance(value, str) else value

        if record.exc_info:
            payload["exception_type"] = type(record.exc_info[1]).__name__
        return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))


def configure_json_logging() -> None:
    logging.config.dictConfig(
        {
            "version": 1,
            "disable_existing_loggers": False,
            "formatters": {"safe_json": {"()": "app.api.structured_logging.SafeJsonFormatter"}},
            "handlers": {
                "stdout": {
                    "class": "logging.StreamHandler",
                    "formatter": "safe_json",
                    "stream": "ext://sys.stdout",
                }
            },
            "root": {"level": "INFO", "handlers": ["stdout"]},
            "loggers": {
                "uvicorn": {"handlers": [], "level": "INFO", "propagate": True},
                "uvicorn.error": {"handlers": [], "level": "INFO", "propagate": True},
                "uvicorn.access": {"handlers": [], "level": "INFO", "propagate": True},
            },
        }
    )