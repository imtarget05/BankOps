"""Server-side supervisor PIN gate for high-risk approvals."""
import hmac
import time
from typing import Any

from fastapi import HTTPException

from app.api.routes.auth_utils import verify_password
from app.config import Settings

DEMO_SUPERVISOR_PIN = '123456'

# Track failed PIN verification attempts: user_key -> list of timestamp epochs
_pin_failures: dict[str, list[float]] = {}
PIN_RATE_LIMIT_ATTEMPTS = 5
PIN_RATE_LIMIT_WINDOW_SECONDS = 900  # 15 minutes


def _user_key(user: Any | None) -> str:
    if user is not None:
        return str(getattr(user, "id", getattr(user, "username", "global")))
    return "global"


def reset_pin_failures(user: Any | None = None) -> None:
    _pin_failures.pop(_user_key(user), None)


def verify_supervisor_pin(
    pin: str | None,
    settings: Settings,
    *,
    required: bool = True,
    user: Any | None = None,
) -> None:
    if not required:
        return

    key = _user_key(user)
    now = time.time()
    recent = [t for t in _pin_failures.get(key, []) if now - t < PIN_RATE_LIMIT_WINDOW_SECONDS]
    _pin_failures[key] = recent
    if len(recent) >= PIN_RATE_LIMIT_ATTEMPTS:
        raise HTTPException(
            403,
            'Đã nhập sai mã PIN quá 5 lần liên tiếp. Quyền duyệt tạm thời bị khóa trong 15 phút để bảo đảm an toàn kiểm soát kép.',
        )

    user_pin_hash = getattr(user, "pin_hash", None)
    if user_pin_hash:
        if pin is None or not pin or not verify_password(pin, user_pin_hash):
            _pin_failures.setdefault(key, []).append(time.time())
            raise HTTPException(403, 'Mã PIN kiểm soát viên không đúng.')
        reset_pin_failures(user)
        return

    if settings.is_demo_mode:
        # PIN demo CHỈ được dùng khi demo mode bật tường minh
        # (`APP_ENV=demo` + `DEMO_MODE=true`). Ngoài demo mode, đường này bị
        # chặn hoàn toàn -> fail-closed (không bypass PIN được).
        expected = DEMO_SUPERVISOR_PIN
    else:
        expected = settings.supervisor_pin.get_secret_value()
        if not expected:
            raise HTTPException(503, 'Xác thực kiểm soát viên chưa được cấu hình.')

    if pin is None or not pin or not hmac.compare_digest(pin, expected):
        _pin_failures.setdefault(key, []).append(time.time())
        raise HTTPException(403, 'Mã PIN kiểm soát viên không đúng.')

    reset_pin_failures(user)

