"""Server-side demo-only supervisor PIN gate for high-risk approvals."""
import hmac

from fastapi import HTTPException

from app.config import Settings

DEMO_SUPERVISOR_PIN = '123456'


def verify_supervisor_pin(pin: str | None, settings: Settings, *, required: bool = True) -> None:
    if not required:
        return
    if settings.is_demo:
        expected = DEMO_SUPERVISOR_PIN
    else:
        expected = settings.supervisor_pin.get_secret_value()
        if not expected:
            raise HTTPException(503, 'Xác thực kiểm soát viên chưa được cấu hình.')
    if pin is None or not pin or not hmac.compare_digest(pin, expected):
        raise HTTPException(403, 'Mã PIN kiểm soát viên không đúng.')
