"""Unit tests for app.config — Settings, session_secret, signing_key, AI validator."""

from __future__ import annotations

import os
from unittest.mock import patch

import pytest

from app.config import Settings


class TestSettingsDefaults:
    def test_default_app_env_is_production(self, monkeypatch):
        """Mặc định FAIL-CLOSED: không set `APP_ENV` -> `production` (không phải demo).

        STEP 5: mặc định `demo` khiến app chạy với secret JWT ephemeral (token
        hết hạn sau mỗi lần restart) và `assert_runtime_secrets()` không
        kích hoạt. Muốn chạy demo thì phải set tường minh `APP_ENV=demo`.
        """
        # Bộ test chạy với `APP_ENV=demo` (xem `backend/conftest.py`) -> gỡ để
        # kiểm tra đúng GIÁ TRỊ MẶC ĐỊNH của `Settings`.
        monkeypatch.delenv("APP_ENV", raising=False)
        s = Settings()
        assert s.app_env == "production"

    def test_default_server_host_port(self):
        s = Settings()
        assert s.server_host == "0.0.0.0"
        assert s.server_port == 8000

    def test_is_demo_property(self):
        assert Settings(app_env="demo").is_demo is True
        assert Settings(app_env="production").is_demo is False

    def test_allowed_origins_string_parsing(self):
        s = Settings(allowed_origins="http://a.com, http://b.com ")
        assert s.allowed_origins == ["http://a.com", "http://b.com"]

    def test_allowed_origins_list_unchanged(self):
        s = Settings(allowed_origins=["http://a.com"])
        assert s.allowed_origins == ["http://a.com"]


class TestSessionSecret:
    def test_env_value_takes_precedence(self):
        with patch.dict(os.environ, {"BANKOPS_SESSION_SECRET": "env-secret-123"}):
            s = Settings()
            assert s.session_secret == "env-secret-123"

    def test_demo_returns_ephemeral(self):
        with patch.dict(os.environ, {}, clear=True):
            s = Settings(app_env="demo")
            secret = s.session_secret
            assert isinstance(secret, str)
            assert len(secret) > 0

    def test_test_returns_ephemeral(self):
        with patch.dict(os.environ, {}, clear=True):
            s = Settings(app_env="test")
            secret = s.session_secret
            assert isinstance(secret, str)
            assert len(secret) > 0

    def test_production_without_env_raises(self):
        with patch.dict(os.environ, {}, clear=True):
            s = Settings(app_env="production")
            with pytest.raises(RuntimeError, match="BANKOPS_SESSION_SECRET must be set"):
                _ = s.session_secret


class TestSigningKey:
    def test_env_value_takes_precedence(self):
        with patch.dict(os.environ, {"BANKOPS_SIGNING_KEY": "env-signing-key"}):
            s = Settings()
            assert s.signing_key == "env-signing-key"

    def test_jwt_signing_key_ref_env(self):
        with patch.dict(os.environ, {"BANKOPS_signing": "ref-key-value"}):
            s = Settings(jwt_signing_key_ref="signing")
            assert s.signing_key == "ref-key-value"

    def test_demo_returns_ephemeral(self):
        with patch.dict(os.environ, {}, clear=True):
            s = Settings(app_env="demo")
            key = s.signing_key
            assert isinstance(key, str)
            assert len(key) > 0

    def test_production_without_env_raises(self):
        with patch.dict(os.environ, {}, clear=True):
            s = Settings(app_env="production")
            with pytest.raises(RuntimeError, match="JWT signing key must be set"):
                _ = s.signing_key


class TestAIValidator:
    def test_disabled_provider_no_validation(self):
        s = Settings(ai_provider="disabled", app_env="production")
        assert s.ai_provider == "disabled"

    def test_dev_environment_no_validation(self):
        s = Settings(ai_provider="cloudflare", app_env="demo")
        # Should not raise even without Cloudflare creds in demo
        assert s.ai_provider == "cloudflare"

    def test_cloudflare_production_missing_creds_raises(self):
        with patch.dict(os.environ, {}, clear=True):
            with pytest.raises(ValueError, match="CLOUDFLARE_ACCOUNT_ID"):
                Settings(ai_provider="cloudflare", app_env="production")

