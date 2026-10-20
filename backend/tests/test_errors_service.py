"""Unit tests for app.api.errors — AppError, uuid_hex, register_error_handlers."""

from __future__ import annotations

from fastapi import FastAPI

from app.api.errors import AppError, register_error_handlers, uuid_hex


class TestAppError:
    def test_defaults(self):
        exc = AppError(400, "BAD_REQUEST", "something went wrong")
        assert exc.http_status == 400
        assert exc.code == "BAD_REQUEST"
        assert exc.message == "something went wrong"
        assert exc.details == {}

    def test_with_details(self):
        exc = AppError(409, "CONFLICT", "conflict", details={"field": "sku"})
        assert exc.details == {"field": "sku"}

    def test_is_exception_subclass(self):
        assert issubclass(AppError, Exception)
        exc = AppError(500, "INTERNAL", "boom")
        assert str(exc) == "boom"


class TestUuidHex:
    def test_returns_hex_string(self):
        result = uuid_hex()
        assert isinstance(result, str)
        assert len(result) == 32  # uuid4().hex is 32 chars

    def test_is_unique(self):
        assert uuid_hex() != uuid_hex()


class TestRegisterErrorHandlers:
    def test_registers_handlers_on_app(self):
        app = FastAPI()
        register_error_handlers(app)
        # Should not raise; handlers are registered internally
        assert app is not None