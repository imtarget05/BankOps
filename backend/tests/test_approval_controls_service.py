"""Unit tests for app.services.approval_controls — supervisor PIN gate."""

from __future__ import annotations

import pytest
from fastapi import HTTPException

from app.services.approval_controls import (
    DEMO_SUPERVISOR_PIN,
    PIN_RATE_LIMIT_ATTEMPTS,
    _pin_failures,
    reset_pin_failures,
    verify_supervisor_pin,
)


class FakeUser:
    def __init__(self, id_="user-1", username="user1", pin_hash=None):
        self.id = id_
        self.username = username
        self.pin_hash = pin_hash


class FakeSettings:
    """Cài đặt giả cho `Settings`.

    `demo_mode` mô phỏng demo mode **bật tường minh** (APP_ENV=demo +
    DEMO_MODE=true). Ngoài demo mode, PIN demo phải bị từ chối (D4).
    """

    def __init__(self, app_env="demo", supervisor_pin="123456", demo_mode=True):
        self.app_env = app_env
        self._supervisor_pin = supervisor_pin
        self._demo_mode = demo_mode

    @property
    def is_demo(self):
        return self.app_env == "demo"

    @property
    def is_demo_mode(self):
        return bool(self._demo_mode) and self.app_env == "demo"

    @property
    def supervisor_pin(self):
        class Secret:
            def get_secret_value(self):
                return self._secret

        s = Secret()
        s._secret = self._supervisor_pin
        return s


class TestVerifySupervisorPin:
    def setup_method(self):
        _pin_failures.clear()

    def test_not_required_returns_immediately(self):
        verify_supervisor_pin(None, FakeSettings(), required=False)
        verify_supervisor_pin("anything", FakeSettings(), required=False)

    def test_demo_pin_correct(self):
        settings = FakeSettings(app_env="demo", supervisor_pin=DEMO_SUPERVISOR_PIN)
        verify_supervisor_pin(DEMO_SUPERVISOR_PIN, settings, user=FakeUser())

    def test_demo_pin_wrong_raises_403(self):
        settings = FakeSettings(app_env="demo")
        with pytest.raises(HTTPException) as exc:
            verify_supervisor_pin("wrong-pin", settings, user=FakeUser())
        assert exc.value.status_code == 403

    def test_demo_pin_rejected_when_demo_mode_disabled(self):
        """D4 — ngoài demo mode, PIN demo không được chấp nhận."""
        settings = FakeSettings(app_env="demo", supervisor_pin="654321", demo_mode=False)
        with pytest.raises(HTTPException) as exc:
            verify_supervisor_pin(DEMO_SUPERVISOR_PIN, settings, user=FakeUser())
        assert exc.value.status_code == 403

    def test_configured_pin_accepted_when_demo_mode_disabled(self):
        settings = FakeSettings(app_env="demo", supervisor_pin="654321", demo_mode=False)
        verify_supervisor_pin("654321", settings, user=FakeUser())

    def test_pin_hash_path_verifies_password(self, monkeypatch):
        from app.services import approval_controls

        monkeypatch.setattr(
            approval_controls, "verify_password", lambda pin, h: pin == "correct-pin"
        )
        user = FakeUser(pin_hash="some-hash")
        settings = FakeSettings(app_env="production", supervisor_pin="unused")
        verify_supervisor_pin("correct-pin", settings, user=user)

    def test_pin_hash_path_wrong_raises_403(self, monkeypatch):
        from app.services import approval_controls

        monkeypatch.setattr(
            approval_controls, "verify_password", lambda pin, h: pin == "correct-pin"
        )
        user = FakeUser(pin_hash="some-hash")
        settings = FakeSettings(app_env="production", supervisor_pin="unused")
        with pytest.raises(HTTPException) as exc:
            verify_supervisor_pin("wrong-pin", settings, user=user)
        assert exc.value.status_code == 403

    def test_rate_limit_blocks_after_max_attempts(self):
        settings = FakeSettings(app_env="demo")
        user = FakeUser()
        for _ in range(PIN_RATE_LIMIT_ATTEMPTS):
            with pytest.raises(HTTPException):
                verify_supervisor_pin("wrong-pin", settings, user=user)
        # Next attempt should be rate-limited
        with pytest.raises(HTTPException) as exc:
            verify_supervisor_pin("wrong-pin", settings, user=user)
        assert exc.value.status_code == 403
        assert "quá 5 lần" in exc.value.detail

    def test_reset_pin_failures_clears_for_user(self):
        _pin_failures["user-1"] = [1.0, 2.0, 3.0]
        reset_pin_failures(FakeUser(id_="user-1"))
        assert "user-1" not in _pin_failures

    def test_rate_limit_expires_after_window(self):
        import time

        settings = FakeSettings(app_env="demo")
        user = FakeUser()
        # Use old timestamps to simulate expired window
        _pin_failures["user-1"] = [time.time() - 10000] * PIN_RATE_LIMIT_ATTEMPTS
        # Should not be rate-limited since attempts are old
        verify_supervisor_pin(DEMO_SUPERVISOR_PIN, settings, user=user)

    def test_missing_supervisor_pin_in_production_raises_503(self):
        settings = FakeSettings(app_env="production", supervisor_pin="")
        with pytest.raises(HTTPException) as exc:
            verify_supervisor_pin("any-pin", settings, user=FakeUser())
        assert exc.value.status_code == 503
