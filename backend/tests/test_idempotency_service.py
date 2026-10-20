"""Unit tests for app.services.idempotency — pure in-memory idempotency store."""

from __future__ import annotations

import hashlib
import json

import pytest

from app.services.idempotency import IdempotencyConflict, check, payload_hash, remember


class TestPayloadHash:
    def test_returns_sha256_hexdigest(self):
        result = payload_hash({"a": 1})
        assert isinstance(result, str)
        assert len(result) == 64

    def test_is_deterministic(self):
        assert payload_hash({"b": 2, "a": 1}) == payload_hash({"a": 1, "b": 2})

    def test_different_payloads_different_hash(self):
        assert payload_hash({"a": 1}) != payload_hash({"a": 2})

    def test_handles_non_dict(self):
        assert payload_hash([1, 2, 3]) == hashlib.sha256(
            json.dumps([1, 2, 3], sort_keys=True, default=str).encode("utf-8")
        ).hexdigest()


class TestIdempotencyConflict:
    def test_stores_status_and_body(self):
        exc = IdempotencyConflict(200, {"id": "abc"})
        assert exc.existing_status == 200
        assert exc.existing_body == {"id": "abc"}

    def test_is_exception_subclass(self):
        assert issubclass(IdempotencyConflict, Exception)


class TestCheckAndRemember:
    def setup_method(self):
        # Clear in-memory store between tests
        from app.services import idempotency as idem_mod
        idem_mod._store.clear()

    def test_check_returns_none_for_new_key(self):
        assert check("new-key", "abc123") is None

    def test_check_returns_stored_entry_for_matching_hash(self):
        remember(None, "key-1", "hash-a", 201, {"created": True})
        assert check("key-1", "hash-a") == (201, {"created": True})

    def test_check_raises_conflict_for_different_hash(self):
        remember(None, "key-2", "hash-old", 200, {"old": True})
        with pytest.raises(IdempotencyConflict) as exc:
            check("key-2", "hash-new")
        assert exc.value.existing_status == 200
        assert exc.value.existing_body == {"old": True}

    def test_remember_stores_entry(self):
        remember(None, "key-3", "hash-x", 202, {"accepted": True})
        assert check("key-3", "hash-x") == (202, {"accepted": True})

    def test_purge_expired_removes_old_entries(self):
        import time

        from app.services import idempotency as idem_mod

        idem_mod._store["expired-key"] = ("hash", 200, {}, time.time() - 100000)
        idem_mod._store["fresh-key"] = ("hash", 200, {}, time.time())
        idem_mod._purge_expired()
        assert "expired-key" not in idem_mod._store
        assert "fresh-key" in idem_mod._store