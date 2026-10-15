"""Email notification service for Quản Lý Kho Trà Sữa."""
import asyncio
import logging
import re
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

from app.config import settings

logger = logging.getLogger("khotrasua.email")

# Regex email thực dụng: local@domain.tld (≥2 ký tự TLD), không chứa space.
_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]{2,}$")


def is_valid_email(value: str | None) -> bool:
    """Chỉ chấp nhận email thật có format hợp lệ (dùng cho invite & reset)."""
    return bool(value) and bool(_EMAIL_RE.match(value.strip().lower()))


def _build_otp_html(username: str, otp: str) -> str:
    return f"""<!DOCTYPE html>
<html lang="vi">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Mã xác thực khôi phục mật khẩu - Quản Lý Kho Trà Sữa</title>
</head>
<body style="margin: 0; padding: 0; background-color: #f4f6f8; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; color: #1e293b;">
  <table width="100%" border="0" cellspacing="0" cellpadding="0" style="background-color: #f4f6f8; padding: 40px 20px;">
    <tr>
      <td align="center">
        <table width="100%" max-width="580" style="max-width: 580px; background-color: #ffffff; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 12px rgba(0, 0, 0, 0.08); border: 1px solid #e2e8f0;">
          <!-- Header -->
          <tr>
            <td style="background-color: #0A2540; padding: 28px 32px; text-align: left;">
              <table width="100%" border="0" cellspacing="0" cellpadding="0">
                <tr>
                  <td>
                    <span style="color: #ffffff; font-size: 22px; font-weight: 800; letter-spacing: 0.5px;">Quản Lý Kho Trà Sữa</span>
                    <span style="color: #FDE68A; font-size: 13px; font-weight: 600; margin-left: 8px; padding: 3px 8px; background: rgba(255,255,255,0.12); border-radius: 4px;">NHẬP · XUẤT · TỒN</span>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- Body -->
          <tr>
            <td style="padding: 36px 32px 24px 32px;">
              <h2 style="margin: 0 0 16px 0; font-size: 19px; font-weight: 700; color: #0f172a;">Yêu Cầu Khôi Phục Mật Khẩu</h2>
              <p style="margin: 0 0 16px 0; font-size: 14px; line-height: 1.6; color: #475569;">
                Xin chào <strong>{username}</strong>,
              </p>
              <p style="margin: 0 0 24px 0; font-size: 14px; line-height: 1.6; color: #475569;">
                Hệ thống Quản Lý Kho Trà Sữa vừa nhận được yêu cầu đặt lại mật khẩu cho tài khoản của bạn. Vui lòng sử dụng mã xác thực OTP dùng một lần dưới đây để hoàn tất:
              </p>

              <!-- OTP Code Display -->
              <div style="background-color: #f8fafc; border: 2px dashed #0A2540; border-radius: 8px; padding: 20px; text-align: center; margin-bottom: 24px;">
                <span style="display: block; font-size: 12px; font-weight: 600; text-transform: uppercase; color: #64748b; margin-bottom: 6px; letter-spacing: 1px;">MÃ XÁC THỰC OTP</span>
                <span style="font-family: 'SF Mono', Consolas, Monaco, monospace; font-size: 34px; font-weight: 800; letter-spacing: 8px; color: #0A2540;">{otp}</span>
                <span style="display: block; font-size: 12px; color: #dc2626; margin-top: 8px; font-weight: 600;">Hiệu lực trong vòng 15 phút (900 giây)</span>
              </div>

              <!-- Security Notice -->
              <div style="background-color: #fffbeb; border-left: 4px solid #f59e0b; padding: 12px 16px; border-radius: 4px; margin-bottom: 24px;">
                <p style="margin: 0; font-size: 12.5px; line-height: 1.5; color: #92400e;">
                  <strong>Lưu ý bảo mật:</strong> Không chia sẻ mã OTP này cho bất kỳ ai. Nếu bạn không thực hiện yêu cầu này, vui lòng bỏ qua email và thông báo ngay cho quản lý cửa hàng.
                </p>
              </div>

              <p style="margin: 0; font-size: 13px; line-height: 1.5; color: #64748b;">
                Trân trọng,<br>
                <strong>Ban Vận Hành Quản Lý Kho Trà Sữa</strong>
              </p>
            </td>
          </tr>

          <!-- Footer -->
          <tr>
            <td style="background-color: #f8fafc; border-top: 1px solid #e2e8f0; padding: 20px 32px; text-align: center;">
              <p style="margin: 0; font-size: 11.5px; color: #94a3b8; line-height: 1.4;">
                Đây là email tự động từ hệ thống Quản Lý Kho Trà Sữa. Vui lòng không trả lời trực tiếp email này.
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>"""


def _send_smtp_sync(
    host: str,
    port: int,
    user: str,
    password: str,
    to_email: str,
    subject: str,
    html_content: str,
    from_name: str = "Quản Lý Kho Trà Sữa",
) -> bool:
    """Synchronous SMTP email sender designed to run inside asyncio.to_thread."""
    try:
        msg = MIMEMultipart("alternative")
        msg["Subject"] = subject
        msg["From"] = f"{from_name} <{user}>"
        msg["To"] = to_email

        part = MIMEText(html_content, "html", "utf-8")
        msg.attach(part)

        # Support STARTTLS (port 587) and SSL (port 465)
        if port == 465:
            with smtplib.SMTP_SSL(host, port, timeout=12) as server:
                server.login(user, password)
                server.send_message(msg)
        else:
            with smtplib.SMTP(host, port, timeout=12) as server:
                server.starttls()
                server.login(user, password)
                server.send_message(msg)

        logger.info("Successfully sent OTP email to %s via %s:%d", to_email, host, port)
        return True
    except Exception as exc:
        logger.error("Failed to send email to %s: %s", to_email, exc)
        return False


async def send_password_reset_email(to_email: str, username: str, otp: str) -> bool:
    """Send a password recovery OTP email asynchronously.
    
    If SMTP credentials are not configured, logs a helpful warning and returns False without raising error.
    """
    clean_email = to_email.strip()
    if not clean_email or "@" not in clean_email:
        logger.warning("Invalid recipient email: %s", to_email)
        return False

    smtp_user = settings.smtp_user.strip()
    smtp_pass = settings.smtp_password.strip()

    if not smtp_user or not smtp_pass:
        logger.info(
            "[EmailService (Demo mode)] SMTP not configured. OTP for user '%s' (%s) is %s",
            username,
            clean_email,
            otp,
        )
        return False

    subject = f"[{settings.smtp_from_name}] Mã xác thực OTP khôi phục mật khẩu: {otp}"
    html_body = _build_otp_html(username=username, otp=otp)

    return await asyncio.to_thread(
        _send_smtp_sync,
        host=settings.smtp_host,
        port=settings.smtp_port,
        user=smtp_user,
        password=smtp_pass,
        to_email=clean_email,
        subject=subject,
        html_content=html_body,
        from_name=settings.smtp_from_name,
    )


def _build_invite_html(username: str, invite_link: str, expires_label: str) -> str:
    """HTML nội dung email mời kích hoạt tài khoản nhân viên."""
    return f"""<!DOCTYPE html>
<html lang="vi">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>
<body style="margin:0;padding:0;background-color:#f1f5f9;font-family:Arial,Helvetica,sans-serif;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#f1f5f9;padding:32px 12px;">
    <tr><td align="center">
      <table role="presentation" width="560" cellpadding="0" cellspacing="0" style="background-color:#ffffff;border-radius:16px;overflow:hidden;border:1px solid #e2e8f0;">
        <tr>
          <td style="background:linear-gradient(135deg,#2563eb,#0891b2);padding:28px 32px;">
            <p style="margin:0;font-size:20px;font-weight:700;color:#ffffff;">Mời kích hoạt tài khoản</p>
            <p style="margin:6px 0 0;font-size:13px;color:#dbeafe;">{settings.smtp_from_name}</p>
          </td>
        </tr>
        <tr>
          <td style="padding:28px 32px;">
            <p style="margin:0 0 12px;font-size:14px;color:#334155;">Xin chào <strong>{username}</strong>,</p>
            <p style="margin:0 0 20px;font-size:14px;color:#334155;line-height:1.6;">
              Quản trị viên đã mời bạn tham gia hệ thống. Bấm nút bên dưới để đặt mật khẩu và kích hoạt tài khoản
              (hạn sử dụng: <strong>{expires_label}</strong>).
            </p>
            <table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 0 20px;">
              <tr>
                <td style="background-color:#2563eb;border-radius:10px;">
                  <a href="{invite_link}" style="display:inline-block;padding:14px 28px;font-size:15px;font-weight:700;color:#ffffff;text-decoration:none;">Kích hoạt tài khoản</a>
                </td>
              </tr>
            </table>
            <p style="margin:0;font-size:12.5px;color:#92400e;background-color:#fffbeb;border:1px solid #fde68a;border-radius:8px;padding:12px 14px;line-height:1.5;">
              <strong>Lưu ý bảo mật:</strong> Không chuyển tiếp email này cho người khác. Nếu bạn không được mời,
              vui lòng bỏ qua email và báo ngay cho quản lý cửa hàng.
            </p>
            <p style="margin:20px 0 0;font-size:13px;color:#64748b;">Trân trọng,<br><strong>Ban Vận Hành Quản Lý Kho Trà Sữa</strong></p>
          </td>
        </tr>
        <tr>
          <td style="background-color:#f8fafc;border-top:1px solid #e2e8f0;padding:18px 32px;text-align:center;">
            <p style="margin:0;font-size:11.5px;color:#94a3b8;">Đây là email tự động từ hệ thống {settings.smtp_from_name}. Vui lòng không trả lời trực tiếp email này.</p>
          </td>
        </tr>
      </table>
    </td></tr>
  </table>
</body>
</html>"""


async def send_invite_email(to_email: str, username: str, invite_link: str, expires_at) -> bool:
    """Gửi email mời kích hoạt tài khoản (onboarding `invite_email`).

    Yêu cầu email thật (format hợp lệ). Nếu SMTP chưa cấu hình thì log cảnh báo
    và trả False (không raise) — caller vẫn trả invite_link trong response.
    """
    clean_email = (to_email or "").strip().lower()
    if not is_valid_email(clean_email):
        logger.warning("Invite skipped: email không hợp lệ cho user '%s': %s", username, to_email)
        return False

    smtp_user = settings.smtp_user.strip()
    smtp_pass = settings.smtp_password.strip()
    if not smtp_user or not smtp_pass:
        logger.info(
            "[EmailService (Demo mode)] SMTP not configured. Invite for user '%s' (%s) link: %s",
            username, clean_email, invite_link,
        )
        return False

    expires_label = (
        expires_at.strftime("%d/%m/%Y %H:%M") if getattr(expires_at, "year", None) else "7 ngày"
    )
    subject = f"[{settings.smtp_from_name}] Lời mời kích hoạt tài khoản cho {username}"
    html_body = _build_invite_html(username=username, invite_link=invite_link, expires_label=expires_label)

    return await asyncio.to_thread(
        _send_smtp_sync,
        host=settings.smtp_host,
        port=settings.smtp_port,
        user=smtp_user,
        password=smtp_pass,
        to_email=clean_email,
        subject=subject,
        html_content=html_body,
        from_name=settings.smtp_from_name,
    )

