import json
import logging

from app.api.request_context import correlation_id_var, request_id_var
from app.api.structured_logging import SafeJsonFormatter


def test_json_log_has_correlation_and_trace_context_without_sensitive_fields() -> None:
    request_token = request_id_var.set("req-123")
    correlation_token = correlation_id_var.set("corr-456")
    try:
        record = logging.LogRecord(
            name="bankops.http",
            level=logging.INFO,
            pathname=__file__,
            lineno=1,
            msg="request token=secret-value user=alice@example.com",
            args=(),
            exc_info=None,
        )
        record.otelTraceID = "4bf92f3577b34da6a3ce929d0e0e4736"
        record.otelSpanID = "00f067aa0ba902b7"
        record.account_number = "123456789"

        payload = json.loads(SafeJsonFormatter().format(record))
    finally:
        request_id_var.reset(request_token)
        correlation_id_var.reset(correlation_token)

    assert payload["request_id"] == "req-123"
    assert payload["correlation_id"] == "corr-456"
    assert payload["trace_id"] == "4bf92f3577b34da6a3ce929d0e0e4736"
    assert payload["span_id"] == "00f067aa0ba902b7"
    assert "secret-value" not in payload["message"]
    assert "alice@example.com" not in payload["message"]
    assert "account_number" not in payload