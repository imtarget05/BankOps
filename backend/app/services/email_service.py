"""Email notification service for Quản Lý Kho Trà Sữa."""
import asyncio
import logging
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

from app.config import settings

logger = logging.getLogger("khotrasua.email")


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
