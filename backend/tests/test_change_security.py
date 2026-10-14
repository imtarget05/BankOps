"""Test change password and change PIN endpoints."""
import pytest
from fastapi import HTTPException

from app.config import Settings
from app.services.approval_controls import verify_supervisor_pin

DEMO_PASSWORD = "DemoPass123!"


def test_change_password_flow(client):
    # 1. Login with demo_maker
    login_resp = client.post(
        "/api/v1/auth/login",
        data={"username": "demo_maker", "password": DEMO_PASSWORD},
    )
    assert login_resp.status_code == 200, login_resp.text
    token = login_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 2. Try changing password with wrong old password -> 400
    bad_resp = client.post(
        "/api/v1/auth/change-password",
        headers=headers,
        json={"old_password": "WrongPassword123!", "new_password": "NewSecretPassword123!"},
    )
    assert bad_resp.status_code == 400
    assert "Mật khẩu hiện tại không đúng" in bad_resp.json()["error"]["message"]

    # 3. Change password successfully
    new_pass = "BrandNewPass2026!"
    ok_resp = client.post(
        "/api/v1/auth/change-password",
        headers=headers,
        json={"old_password": DEMO_PASSWORD, "new_password": new_pass},
    )
    assert ok_resp.status_code == 200
    assert "Đổi mật khẩu thành công" in ok_resp.json()["message"]

    # 4. Verify login with old password fails
    old_login = client.post(
        "/api/v1/auth/login",
        data={"username": "demo_maker", "password": DEMO_PASSWORD},
    )
    assert old_login.status_code == 401

    # 5. Verify login with new password succeeds
    new_login = client.post(
        "/api/v1/auth/login",
        data={"username": "demo_maker", "password": new_pass},
    )
    assert new_login.status_code == 200
    assert new_login.json()["access_token"]

    # Revert password back to DEMO_PASSWORD so other test suites stay idempotent
    rev_token = new_login.json()["access_token"]
    revert_resp = client.post(
        "/api/v1/auth/change-password",
        headers={"Authorization": f"Bearer {rev_token}"},
        json={"old_password": new_pass, "new_password": DEMO_PASSWORD},
    )
    assert revert_resp.status_code == 200


def test_change_pin_flow(client):
    # 1. Login with demo_checker
    login_resp = client.post(
        "/api/v1/auth/login",
        data={"username": "demo_checker", "password": DEMO_PASSWORD},
    )
    assert login_resp.status_code == 200, login_resp.text
    token = login_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 2. Try with wrong account password -> 400
    wrong_resp = client.post(
        "/api/v1/auth/change-pin",
        headers=headers,
        json={"current_password": "WrongPassword999!", "new_pin": "654321"},
    )
    assert wrong_resp.status_code == 400
    assert "Mật khẩu tài khoản không đúng" in wrong_resp.json()["error"]["message"]

    # 3. Try with invalid pin format (not 6 digits) -> 422
    invalid_resp = client.post(
        "/api/v1/auth/change-pin",
        headers=headers,
        json={"current_password": DEMO_PASSWORD, "new_pin": "1234"},
    )
    assert invalid_resp.status_code == 422

    # 4. Change pin successfully to '777888'
    ok_resp = client.post(
        "/api/v1/auth/change-pin",
        headers=headers,
        json={"current_password": DEMO_PASSWORD, "new_pin": "777888"},
    )
    assert ok_resp.status_code == 200
    assert "Đổi mã PIN kiểm soát viên thành công" in ok_resp.json()["message"]

    # 5. Verify unit logic with updated user pin
    class MockUserWithPin:
        from app.api.routes.auth_utils import get_password_hash
        pin_hash = get_password_hash("777888")

    settings = Settings(database_url="sqlite://", app_env="demo")
    user = MockUserWithPin()

    # Old demo PIN '123456' must now be rejected
    with pytest.raises(HTTPException) as exc:
        verify_supervisor_pin("123456", settings, user=user)
    assert exc.value.status_code == 403

    # New PIN '777888' must be accepted
    verify_supervisor_pin("777888", settings, user=user)

    # Revert pin back to '123456'
    rev_resp = client.post(
        "/api/v1/auth/change-pin",
        headers=headers,
        json={"current_password": DEMO_PASSWORD, "new_pin": "123456"},
    )
    assert rev_resp.status_code == 200


def test_forgot_password_and_reset_flow(client):
    # 1. Request reset for non-existent user -> 404
    bad_req = client.post(
        "/api/v1/auth/forgot-password",
        json={"username": "non_existent_user_999"},
    )
    assert bad_req.status_code == 404
    assert "Không tìm thấy tài khoản" in bad_req.json()["error"]["message"]

    # 2. Request OTP for demo_maker -> 200
    forgot_resp = client.post(
        "/api/v1/auth/forgot-password",
        json={"username": "demo_maker"},
    )
    assert forgot_resp.status_code == 200
    data = forgot_resp.json()
    assert data["username"] == "demo_maker"
    otp = data["otp_demo"]
    assert len(otp) == 6

    # 3. Reset with wrong OTP -> 400
    wrong_otp_resp = client.post(
        "/api/v1/auth/reset-password",
        json={"username": "demo_maker", "otp": "000000", "new_password": "NewResetPassword2026!"},
    )
    assert wrong_otp_resp.status_code == 400
    assert "Mã xác thực OTP không chính xác" in wrong_otp_resp.json()["error"]["message"]

    # 4. Reset with valid OTP -> 200
    new_password = "NewResetPassword2026!"
    ok_reset = client.post(
        "/api/v1/auth/reset-password",
        json={"username": "demo_maker", "otp": otp, "new_password": new_password},
    )
    assert ok_reset.status_code == 200
    assert "Khôi phục mật khẩu thành công" in ok_reset.json()["message"]

    # 5. Verify old password no longer works
    old_login = client.post(
        "/api/v1/auth/login",
        data={"username": "demo_maker", "password": DEMO_PASSWORD},
    )
    assert old_login.status_code == 401

    # 6. Verify new password works
    new_login = client.post(
        "/api/v1/auth/login",
        data={"username": "demo_maker", "password": new_password},
    )
    assert new_login.status_code == 200
    assert new_login.json()["access_token"]

    # Revert password back to DEMO_PASSWORD
    rev_token = new_login.json()["access_token"]
    revert_resp = client.post(
        "/api/v1/auth/change-password",
        headers={"Authorization": f"Bearer {rev_token}"},
        json={"old_password": new_password, "new_password": DEMO_PASSWORD},
    )
    assert revert_resp.status_code == 200


def test_update_profile_flow(client):
    # 1. Login with demo_maker
    login_resp = client.post(
        "/api/v1/auth/login",
        data={"username": "demo_maker", "password": DEMO_PASSWORD},
    )
    assert login_resp.status_code == 200
    token = login_resp.json()["access_token"]
    orig_display_name = login_resp.json()["user"]["display_name"]
    headers = {"Authorization": f"Bearer {token}"}

    # 2. Validation error: empty display_name
    bad_resp = client.put(
        "/api/v1/auth/me",
        headers=headers,
        json={"display_name": "   "},
    )
    assert bad_resp.status_code == 422

    # 3. Update profile successfully via /api/v1/auth/me
    updated_name = "Nguyễn Hoàng An (Trưởng GDV)"
    ok_resp = client.put(
        "/api/v1/auth/me",
        headers=headers,
        json={
            "display_name": updated_name,
            "email": "hoangan@bankops.vn",
            "phone_number": "0912 345 678",
            "branch": "Chi nhánh Bến Thành (Hội sở)",
        },
    )
    assert ok_resp.status_code == 200
    data = ok_resp.json()
    assert data["display_name"] == updated_name
    assert data["email"] == "hoangan@bankops.vn"
    assert data["phone_number"] == "0912 345 678"

    # 4. Verify GET /api/v1/auth/me returns updated display_name
    me_resp = client.get("/api/v1/auth/me", headers=headers)
    assert me_resp.status_code == 200
    assert me_resp.json()["display_name"] == updated_name

    # 5. Verify alias PUT /api/v1/me works
    alias_resp = client.put(
        "/api/v1/me",
        headers=headers,
        json={"display_name": "Nguyễn Hoàng An (Maker Lead)"},
    )
    assert alias_resp.status_code == 200
    assert alias_resp.json()["display_name"] == "Nguyễn Hoàng An (Maker Lead)"

    # 6. Revert back to original display name
    revert_resp = client.put(
        "/api/v1/auth/me",
        headers=headers,
        json={"display_name": orig_display_name},
    )
    assert revert_resp.status_code == 200
    assert revert_resp.json()["display_name"] == orig_display_name

