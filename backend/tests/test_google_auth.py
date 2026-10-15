"""Tests for Google Authentication (ID token & Access token flow)."""
import json
import uuid
from unittest.mock import MagicMock, patch


def test_google_login_validation_errors(client):
    """Missing or short tokens must return 422 with validation envelope."""
    # 1. Missing both tokens
    r = client.post("/api/v1/auth/google", json={})
    assert r.status_code == 422
    data = r.json()
    assert data["error"]["code"] == "VALIDATION_ERROR"
    assert data["error"]["message"] == "Validation failed"

    # 2. Short id_token
    r = client.post("/api/v1/auth/google", json={"id_token": "short"})
    assert r.status_code == 422
    assert r.json()["error"]["code"] == "VALIDATION_ERROR"

    # 3. Short access_token
    r = client.post("/api/v1/auth/google", json={"access_token": "short"})
    assert r.status_code == 422
    assert r.json()["error"]["code"] == "VALIDATION_ERROR"


def test_google_login_mock_id_token(client):
    """Mock id_token flow provisions staff user and returns JWT."""
    username = f"mock_u_{uuid.uuid4().hex[:6]}@bankops.internal"
    mock_token = f"mock-google-token:{username}:Mock Test User"
    r = client.post("/api/v1/auth/google", json={"id_token": mock_token})
    assert r.status_code == 200, r.text
    body = r.json()
    assert "access_token" in body
    assert "refresh_token" in body
    assert body["user"]["username"] == username
    assert "staff" in body["user"]["roles"]
    assert body["is_new_user"] is True

    # Subsequent login is not a new user
    r2 = client.post("/api/v1/auth/google", json={"id_token": mock_token})
    assert r2.status_code == 200
    assert r2.json()["is_new_user"] is False


def test_google_login_mock_access_token(client):
    """Mock access_token flow provisions staff user and returns JWT."""
    username = f"mock_acc_{uuid.uuid4().hex[:6]}@bankops.internal"
    mock_token = f"mock-google-token:{username}:Mock Access User"
    r = client.post("/api/v1/auth/google", json={"access_token": mock_token})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["user"]["username"] == username
    assert "staff" in body["user"]["roles"]


def test_google_login_access_token_mocked_google_api(client):
    """Test real access token flow with mocked Google tokeninfo & userinfo."""
    email = "test_verified_user@gmail.com"
    tokeninfo_resp = json.dumps({
        "azp": "1070073470852-hc12cgovbt9h7micnu072vpkvigee28u.apps.googleusercontent.com",
        "aud": "1070073470852-hc12cgovbt9h7micnu072vpkvigee28u.apps.googleusercontent.com",
        "sub": "12345678901234567890",
        "email": email,
        "email_verified": "true",
    }).encode()

    userinfo_resp = json.dumps({
        "sub": "12345678901234567890",
        "name": "Verified Google User",
        "email": email,
        "email_verified": True,
    }).encode()

    def fake_urlopen(req, timeout=10):
        url = req.full_url if hasattr(req, "full_url") else str(req)
        mock_cm = MagicMock()
        if "tokeninfo" in url:
            mock_cm.__enter__.return_value.read.return_value = tokeninfo_resp
        else:
            mock_cm.__enter__.return_value.read.return_value = userinfo_resp
        return mock_cm

    with patch("urllib.request.urlopen", side_effect=fake_urlopen):
        r = client.post("/api/v1/auth/google", json={"access_token": "ya29.a0AWY7C1234567890"})
        assert r.status_code == 200, r.text
        body = r.json()
        assert body["user"]["username"] == email
        assert "access_token" in body


def test_google_login_disambiguates_email_and_username(client):
    """When a user has matching email and another has matching username, no MultipleResultsFound."""
    shared_email = "tanmainguyenbinh@gmail.com"
    mock_token = f"mock-google-token:{shared_email}:Tan Mai"
    r = client.post("/api/v1/auth/google", json={"id_token": mock_token})
    assert r.status_code == 200, r.text
    body = r.json()
    # Should resolve to admin user whose email is tanmainguyenbinh@gmail.com
    assert body["user"]["username"] in ("admin", shared_email)
    assert "access_token" in body
