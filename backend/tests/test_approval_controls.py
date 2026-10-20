"""D4 — cổng PIN kiểm soát viên: chỉ chấp nhận PIN demo khi DEMO MODE bật.

Demo mode là opt-in tường minh (`APP_ENV=demo` + `DEMO_MODE=true`). Ngoài demo
mode, PIN demo (`123456`) phải bị từ chối (fail-closed) — chỉ PIN đã cấu hình
mới được dùng.
"""
import pytest
from fastapi import HTTPException

from app.config import Settings
from app.services.approval_controls import DEMO_SUPERVISOR_PIN, verify_supervisor_pin


def _demo_settings(**kwargs) -> Settings:
    """Cấu hình demo mode bật tường minh."""
    return Settings(database_url="sqlite://", app_env="demo", demo_mode=True, **kwargs)


def _non_demo_settings(**kwargs) -> Settings:
    """Demo mode TẮT (app_env=demo nhưng không bật demo_mode)."""
    return Settings(database_url="sqlite://", app_env="demo", demo_mode=False, **kwargs)


def test_demo_accepts_demo_pin():
    verify_supervisor_pin(DEMO_SUPERVISOR_PIN, _demo_settings())


def test_demo_rejects_wrong_pin():
    with pytest.raises(HTTPException) as error:
        verify_supervisor_pin("000000", _demo_settings())
    assert error.value.status_code == 403


def test_demo_pin_is_rejected_outside_demo_mode():
    """D4(d): ngoài demo mode, PIN demo `123456` KHÔNG được chấp nhận."""
    settings = _non_demo_settings(supervisor_pin="654321")
    with pytest.raises(HTTPException) as error:
        verify_supervisor_pin(DEMO_SUPERVISOR_PIN, settings)
    assert error.value.status_code == 403


def test_non_demo_mode_uses_configured_pin():
    settings = _non_demo_settings(supervisor_pin="654321")
    verify_supervisor_pin("654321", settings)


def test_non_demo_mode_without_configured_pin_fails_closed():
    """Không có PIN cấu hình và không bật demo mode -> 503 (fail-closed)."""
    settings = _non_demo_settings()
    with pytest.raises(HTTPException) as error:
        verify_supervisor_pin(DEMO_SUPERVISOR_PIN, settings)
    assert error.value.status_code == 503


def test_production_requires_configured_pin():
    settings = Settings(database_url="sqlite://", app_env="production")
    with pytest.raises(HTTPException) as error:
        verify_supervisor_pin(None, settings)
    assert error.value.status_code == 503


def test_pin_is_not_required_for_low_risk_requests():
    settings = Settings(database_url="sqlite://", app_env="production")
    verify_supervisor_pin(None, settings, required=False)


def test_production_checks_secret_pin():
    settings = Settings(
        database_url="sqlite://", app_env="production", supervisor_pin="654321"
    )
    verify_supervisor_pin("654321", settings)


def test_user_pin_hash_precedence():
    from app.api.routes.auth_utils import get_password_hash

    settings = _demo_settings()

    class MockUser:
        pin_hash = get_password_hash("888999")

    user = MockUser()
    with pytest.raises(HTTPException) as error:
        verify_supervisor_pin("123456", settings, user=user)
    assert error.value.status_code == 403

    verify_supervisor_pin("888999", settings, user=user)


def test_supervisor_pin_rate_limiting():
    from app.services.approval_controls import reset_pin_failures

    settings = _demo_settings()

    class MockUser:
        id = "mock-ksv-001"
        pin_hash = None

    user = MockUser()
    reset_pin_failures(user)

    # 4 wrong attempts should fail with 403
    for _ in range(4):
        with pytest.raises(HTTPException) as err:
            verify_supervisor_pin("000000", settings, user=user)
        assert err.value.status_code == 403

    # 5th wrong attempt also 403
    with pytest.raises(HTTPException) as err:
        verify_supervisor_pin("000000", settings, user=user)
    assert err.value.status_code == 403

    # 6th attempt should be blocked by rate limiting with locked message
    with pytest.raises(HTTPException) as err:
        verify_supervisor_pin("123456", settings, user=user)
    assert err.value.status_code == 403
    assert "quá 5 lần" in err.value.detail

    # Clean up
    reset_pin_failures(user)
