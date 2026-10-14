import pytest
from fastapi import HTTPException

from app.config import Settings
from app.services.approval_controls import verify_supervisor_pin


def test_demo_accepts_demo_pin():
    settings = Settings(database_url='sqlite://', app_env='demo')
    verify_supervisor_pin('123456', settings)


def test_demo_rejects_wrong_pin():
    settings = Settings(database_url='sqlite://', app_env='demo')
    with pytest.raises(HTTPException) as error:
        verify_supervisor_pin('000000', settings)
    assert error.value.status_code == 403


def test_production_requires_configured_pin():
    settings = Settings(database_url='sqlite://', app_env='production')
    with pytest.raises(HTTPException) as error:
        verify_supervisor_pin(None, settings)
    assert error.value.status_code == 503


def test_pin_is_not_required_for_low_risk_requests():
    settings = Settings(database_url='sqlite://', app_env='production')
    verify_supervisor_pin(None, settings, required=False)


def test_production_checks_secret_pin():
    settings = Settings(
        database_url='sqlite://', app_env='production', supervisor_pin='654321'
    )
    verify_supervisor_pin('654321', settings)


def test_user_pin_hash_precedence():
    from app.api.routes.auth_utils import get_password_hash

    settings = Settings(database_url='sqlite://', app_env='demo')

    class MockUser:
        pin_hash = get_password_hash('888999')

    user = MockUser()
    with pytest.raises(HTTPException) as error:
        verify_supervisor_pin('123456', settings, user=user)
    assert error.value.status_code == 403

    verify_supervisor_pin('888999', settings, user=user)


def test_supervisor_pin_rate_limiting():
    from app.services.approval_controls import reset_pin_failures

    settings = Settings(database_url='sqlite://', app_env='demo')

    class MockUser:
        id = "mock-ksv-001"
        pin_hash = None

    user = MockUser()
    reset_pin_failures(user)

    # 4 wrong attempts should fail with 403
    for _ in range(4):
        with pytest.raises(HTTPException) as err:
            verify_supervisor_pin('000000', settings, user=user)
        assert err.value.status_code == 403

    # 5th wrong attempt also 403
    with pytest.raises(HTTPException) as err:
        verify_supervisor_pin('000000', settings, user=user)
    assert err.value.status_code == 403

    # 6th attempt should be blocked by rate limiting with locked message
    with pytest.raises(HTTPException) as err:
        verify_supervisor_pin('123456', settings, user=user)
    assert err.value.status_code == 403
    assert "quá 5 lần" in err.value.detail

    # Clean up
    reset_pin_failures(user)

