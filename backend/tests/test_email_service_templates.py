"""Unit tests for email_service templates and validation."""
from app.services.email_service import (
    EmailSendResult,
    _build_activation_confirmation_html,
    _build_activation_confirmation_plain,
    _build_invite_html,
    _build_invite_plain,
    _build_otp_html,
    is_valid_email,
)


def test_is_valid_email():
    assert is_valid_email("admin@khotrasua.vn") is True
    assert is_valid_email("mainguyenbinhtan2005@gmail.com") is True
    assert is_valid_email("user.name+tag@sub.domain.co") is True

    assert is_valid_email("") is False
    assert is_valid_email(None) is False
    assert is_valid_email("plainaddress") is False
    assert is_valid_email("@missinguser.com") is False
    assert is_valid_email("missingdomain@") is False
    assert is_valid_email("spaces in@email.com") is False
    assert is_valid_email("user@domain.c") is False  # TLD < 2 chars


def test_email_send_result_bool_and_props():
    res_ok = EmailSendResult(True, "Gửi thành công")
    assert bool(res_ok) is True
    assert res_ok.ok is True
    assert res_ok.success is True
    assert res_ok.message == "Gửi thành công"

    res_fail = EmailSendResult(False, "Lỗi kết nối")
    assert bool(res_fail) is False
    assert res_fail.ok is False
    assert res_fail.success is False
    assert res_fail.message == "Lỗi kết nối"


def test_build_invite_html_enterprise_structure():
    html_content = _build_invite_html(
        username="binhtan_admin",
        invite_link="https://app.khotrasua.vn/accept-invite?token=abc123token",
        expires_label="25/10/2026 12:00",
        to_email="mainguyenbinhtan2005@gmail.com",
        display_name="Mai Nguyễn Bình Tân",
        roles=["admin", "manager"],
        token="abc123token",
        inviter_name="Mai Nguyễn Bình Tân",
    )

    # Header styling & Enterprise Branding
    assert "#0F172A" in html_content
    assert "HỆ THỐNG QUẢN TRỊ DOANH NGHIỆP" in html_content
    assert "ENTERPRISE OPERATIONS SYSTEM" in html_content

    # Inviter greeting
    assert "Quản trị viên <strong>Mai Nguyễn Bình Tân</strong>" in html_content

    # Account info table
    assert "Mai Nguyễn Bình Tân" in html_content
    assert "@binhtan_admin" in html_content
    assert "mainguyenbinhtan2005@gmail.com" in html_content
    assert "Chủ Quán / Quản Trị Viên (Administrator)" in html_content
    assert "Quản Lý Cửa Hàng / Trưởng Ca (Store Manager)" in html_content
    assert "25/10/2026 12:00" in html_content

    # Hero CTA Button (No emojis, clean text)
    assert "Kích Hoạt Tài Khoản Quản Trị" in html_content
    assert 'href="https://app.khotrasua.vn/accept-invite?token=abc123token"' in html_content

    # Enterprise Fallback link
    assert "Nếu nút bấm phía trên không hoạt động" in html_content
    assert "MÃ KÍCH HOẠT NHANH TRÊN APP MOBILE / POS" not in html_content
    assert "QUY TRÌNH 3 BƯỚC BẮT ĐẦU VẬN HÀNH" not in html_content
    assert "Lưu ý bảo mật:" not in html_content
    assert "ISO 27001" in html_content


def test_build_invite_html_escapes_xss():
    html_content = _build_invite_html(
        username="user<script>alert(1)</script>",
        invite_link="https://app.khotrasua.vn/invite?tok=1&a=2",
        expires_label="7 ngày",
        display_name="Hacker <img src=x onerror=alert(1)>",
        roles=["admin"],
        inviter_name="Admin <script>hack</script>",
    )

    assert "<script>" not in html_content
    assert "&lt;script&gt;alert(1)&lt;/script&gt;" in html_content
    assert "<img src=x" not in html_content
    assert "&lt;img src=x" in html_content
    assert "&lt;script&gt;hack&lt;/script&gt;" in html_content


def test_build_invite_plain():
    plain_content = _build_invite_plain(
        username="binhtan_admin",
        invite_link="https://app.khotrasua.vn/accept-invite?token=abc123token",
        expires_label="25/10/2026 12:00",
        to_email="mainguyenbinhtan2005@gmail.com",
        display_name="Mai Nguyễn Bình Tân",
        roles=["admin"],
        token="abc123token",
        inviter_name="Mai Nguyễn Bình Tân",
    )

    assert "THƯ MỜI THAM GIA QUẢN TRỊ HỆ THỐNG" in plain_content
    assert "HỆ THỐNG QUẢN TRỊ DOANH NGHIỆP" in plain_content
    assert "Quản trị viên Mai Nguyễn Bình Tân" in plain_content
    assert "Mai Nguyễn Bình Tân" in plain_content
    assert "binhtan_admin" in plain_content
    assert "https://app.khotrasua.vn/accept-invite?token=abc123token" in plain_content


def test_build_activation_confirmation_html():
    html_content = _build_activation_confirmation_html(
        username="binhtan_admin",
        display_name="Mai Nguyễn Bình Tân",
        activated_at_str="17:00:00 ngày 18/10/2026",
        app_url="https://quan-ly-kho-tra-sua.tanmainguyenbinh.workers.dev",
    )

    assert "HỆ THỐNG QUẢN TRỊ DOANH NGHIỆP" in html_content
    assert "Tài Khoản Đã Kích Hoạt Thành Công" in html_content
    assert "Mai Nguyễn Bình Tân" in html_content
    assert "@binhtan_admin" in html_content
    assert "17:00:00 ngày 18/10/2026" in html_content
    assert "BẢO MẬT & THU HỒI TÀI NGUYÊN HOÀN TẤT" in html_content
    assert "thu hồi và hủy bỏ vĩnh viễn (Revoked & Released)" in html_content
    assert "Truy Cập Hệ Thống Ngay" in html_content
    assert "https://quan-ly-kho-tra-sua.tanmainguyenbinh.workers.dev" in html_content


def test_build_activation_confirmation_plain():
    plain_content = _build_activation_confirmation_plain(
        username="binhtan_admin",
        display_name="Mai Nguyễn Bình Tân",
        activated_at_str="17:00:00 ngày 18/10/2026",
        app_url="https://quan-ly-kho-tra-sua.tanmainguyenbinh.workers.dev",
    )

    assert "XÁC NHẬN KÍCH HOẠT TÀI KHOẢN THÀNH CÔNG" in plain_content
    assert "HỆ THỐNG QUẢN TRỊ DOANH NGHIỆP" in plain_content
    assert "Mai Nguyễn Bình Tân" in plain_content
    assert "@binhtan_admin" in plain_content
    assert "BẢO MẬT & THU HỒI TÀI NGUYÊN" in plain_content
    assert "Revoked & Released" in plain_content


def test_build_otp_html_escapes_input():
    html_content = _build_otp_html(
        username="test<script>bad</script>",
        otp="123456",
    )
    assert "<script>" not in html_content
    assert "123456" in html_content

