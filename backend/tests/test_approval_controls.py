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


def test_production_checks_secret_pin():
    settings = Settings(
        database_url='sqlite://', app_env='production', supervisor_pin='654321'
    )
    verify_supervisor_pin('654321', settings)
