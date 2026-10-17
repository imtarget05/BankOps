import uuid
from datetime import UTC, datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, Request, status
from jose import JWTError, jwt
from pydantic import BaseModel, Field
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.routes.auth_utils import (
    authenticate_user,
    create_access_token,
    create_refresh_token,
    generate_password_reset_otp,
    get_current_user,
    get_password_hash,
    get_user_capabilities,
    get_user_roles,
    is_token_revoked,
    login_rate_limited,
    oauth2_scheme,
    record_login_failure,
    reset_login_failures,
    revoke_token,
    verify_password,
    verify_password_reset_otp,
)
from app.config import settings
from app.database import get_db
from app.models.activity import AuditEvent
from app.models.iam import User, UserStatus
from app.services.email_service import send_password_reset_email

router = APIRouter()


@router.post("/login")
async def login(
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    """Login with username and password (supports JSON or form-urlencoded)."""
    content_type = (request.headers.get("content-type") or "").lower()
    username: str | None = None
    password: str | None = None
    if "application/json" in content_type:
        try:
            body = await request.json()
            if isinstance(body, dict):
                username = body.get("username")
                password = body.get("password")
        except Exception:
            pass
    else:
        try:
            form = await request.form()
            username = form.get("username")  # type: ignore[assignment]
            password = form.get("password")  # type: ignore[assignment]
        except Exception:
            pass

    if not username or not password:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="username and password are required",
        )

    # Rate limit login (docs/08: chặn brute force, khóa tạm theo username).
    if login_rate_limited(username):
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many failed login attempts, try again later.",
            headers={"Retry-After": str(settings.rate_limit_login_window_minutes * 60)},
        )

    user = await authenticate_user(db, username, password)
    if not user:
        record_login_failure(username)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    reset_login_failures(username)
    roles = await get_user_roles(db, user.id)
    capabilities = await get_user_capabilities(db, user.id)

    access_token_expires = timedelta(minutes=30)
    refresh_token_expires = timedelta(days=7)

    access_token = create_access_token(
        {
            "sub": str(user.id),
            "username": user.username,
            "roles": roles,
            "caps": capabilities,
            "auth_version": getattr(user, "auth_version", 1),
            "branch_id": str(user.branch_id) if getattr(user, "branch_id", None) else None,
        },
        access_token_expires,
    )
    refresh_token = create_refresh_token(
        {"sub": str(user.id), "username": user.username},
        refresh_token_expires,
    )

    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
        "expires_in": int(access_token_expires.total_seconds()),
        "user": {
            "id": str(user.id),
            "username": user.username,
            "display_name": user.display_name_demo,
            "roles": roles,
            "capabilities": capabilities,
            "must_change_password": getattr(user, "must_change_password", False),
            "branch_id": str(user.branch_id) if getattr(user, "branch_id", None) else None,
        },
    }


class RegisterRequest(BaseModel):
    username: str = Field(min_length=3, max_length=64)
    password: str = Field(min_length=6, max_length=128)
    display_name: str = Field(min_length=1, max_length=256)
    email: str | None = None
    role: str | None = "staff"
    pin: str | None = "123456"


@router.post("/register")
async def register(
    request: Request,
):
    """Đăng ký công khai đã bị tắt theo chính sách bảo mật nội bộ ngân hàng (Phase 1 IAM)."""
    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="PUBLIC_REGISTRATION_DISABLED: Đăng ký tài khoản công khai đã bị vô hiệu hóa. Tài khoản nhân viên phải được Quản trị viên cấp phát.",
    )
class AcceptInviteRequest(BaseModel):
    invite_token: str
    new_password: str = Field(min_length=6, max_length=128)
    pin: str | None = None


@router.post("/accept-invite")
async def accept_invite(
    body: AcceptInviteRequest,
    db: AsyncSession = Depends(get_db),
):
    """Kích hoạt tài khoản và đặt mật khẩu từ token mời của quản trị viên."""
    import hashlib
    token_hash = hashlib.sha256(body.invite_token.strip().encode("utf-8")).hexdigest()
    now = datetime.now(UTC)

    result = await db.execute(
        select(User).where(User.invite_token_hash == token_hash)
    )
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Mã mời không hợp lệ hoặc đã được sử dụng.",
        )

    if user.invite_expires_at and user.invite_expires_at < now:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Mã mời đã hết hạn. Vui lòng liên hệ quản trị viên để nhận mã mới.",
        )

    clean_pin = (body.pin or "123456").strip()
    if clean_pin and (not clean_pin.isdigit() or len(clean_pin) != 6):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Mã PIN bảo mật phải gồm đúng 6 chữ số.",
        )

    user.password_hash = get_password_hash(body.new_password)
    user.pin_hash = get_password_hash(clean_pin) if clean_pin else user.pin_hash
    user.status = UserStatus.active
    user.must_change_password = False
    user.invite_token_hash = None
    user.invite_expires_at = None
    user.auth_version = getattr(user, "auth_version", 1) + 1

    db.add(
        AuditEvent(
            id=uuid.uuid4(),
            actor_id=user.id,
            action="USER_INVITE_ACCEPTED",
            subject=f"iam_users:{user.id}",
            occurred_at=now,
            metadata_json={"username": user.username},
        )
    )

    await db.commit()
    await db.refresh(user)

    roles = await get_user_roles(db, user.id)
    capabilities = await get_user_capabilities(db, user.id)
    access_token_expires = timedelta(minutes=settings.access_token_expire_minutes)

    access_token = create_access_token(
        {
            "sub": str(user.id),
            "username": user.username,
            "roles": roles,
            "caps": capabilities,
            "auth_version": user.auth_version,
            "branch_id": str(user.branch_id) if user.branch_id else None,
        },
        access_token_expires,
    )
    refresh_token = create_refresh_token(
        {"sub": str(user.id), "username": user.username},
        timedelta(days=settings.refresh_token_expire_days),
    )

    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
        "message": "Kích hoạt tài khoản và đặt mật khẩu thành công.",
        "user": {
            "id": str(user.id),
            "username": user.username,
            "display_name": user.display_name_demo,
            "roles": roles,
            "capabilities": capabilities,
        },
    }


class ChangeInitialPasswordRequest(BaseModel):
    current_password: str
    new_password: str = Field(min_length=6, max_length=128)
    pin: str | None = None


@router.post("/change-initial-password")
async def change_initial_password(
    body: ChangeInitialPasswordRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Bắt buộc đổi mật khẩu tạm thời ở lần đăng nhập đầu tiên."""
    if not verify_password(body.current_password, current_user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Mật khẩu hiện tại không chính xác.",
        )

    clean_pin = (body.pin or "").strip()
    if clean_pin and (not clean_pin.isdigit() or len(clean_pin) != 6):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Mã PIN bảo mật phải gồm đúng 6 chữ số.",
        )

    now = datetime.now(UTC)
    current_user.password_hash = get_password_hash(body.new_password)
    if clean_pin:
        current_user.pin_hash = get_password_hash(clean_pin)
    current_user.must_change_password = False
    current_user.auth_version = getattr(current_user, "auth_version", 1) + 1

    db.add(
        AuditEvent(
            id=uuid.uuid4(),
            actor_id=current_user.id,
            action="USER_INITIAL_PASSWORD_CHANGED",
            subject=f"iam_users:{current_user.id}",
            occurred_at=now,
            metadata_json={"username": current_user.username},
        )
    )

    await db.commit()
    await db.refresh(current_user)

    roles = await get_user_roles(db, current_user.id)
    capabilities = await get_user_capabilities(db, current_user.id)
    access_token_expires = timedelta(minutes=settings.access_token_expire_minutes)

    access_token = create_access_token(
        {
            "sub": str(current_user.id),
            "username": current_user.username,
            "roles": roles,
            "caps": capabilities,
            "auth_version": current_user.auth_version,
            "branch_id": str(current_user.branch_id) if current_user.branch_id else None,
        },
        access_token_expires,
    )

    return {
        "access_token": access_token,
        "message": "Đổi mật khẩu thành công.",
        "must_change_password": False,
    }


class RefreshIn(BaseModel):
    refresh_token: str


@router.post("/refresh")
async def refresh_tokens(
    body: RefreshIn,
    db: AsyncSession = Depends(get_db),
):
    """Đổi refresh token cũ lấy cặp mới (rotation, docs/08).

    Refresh token đã dùng hoặc đã thu hồi bị từ chối — chống replay.
    """
    invalid = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid or expired refresh token",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(
            body.refresh_token, settings.signing_key, algorithms=[settings.jwt_algorithm]
        )
    except JWTError:
        raise invalid from None
    if payload.get("type") != "refresh":
        raise invalid
    if is_token_revoked(body.refresh_token):
        raise invalid

    user = await db.get(User, payload.get("sub", ""))
    if user is None or user.status != "active":
        raise invalid

    # Rotation: refresh token vừa dùng bị revoke, không tái sử dụng.
    revoke_token(body.refresh_token)

    roles = await get_user_roles(db, user.id)
    capabilities = await get_user_capabilities(db, user.id)
    access_token = create_access_token(
        {"sub": str(user.id), "username": user.username, "roles": roles, "caps": capabilities},
        timedelta(minutes=30),
    )
    new_refresh = create_refresh_token(
        {"sub": str(user.id), "username": user.username}, timedelta(days=7)
    )
    return {
        "access_token": access_token,
        "refresh_token": new_refresh,
        "token_type": "bearer",
        "expires_in": 1800,
    }


@router.post("/logout")
async def logout(token: str = Depends(oauth2_scheme)):
    """Logout: revoke access token hiện tại (denylist tới khi token hết hạn)."""
    revoke_token(token)
    return {"message": "Logged out successfully"}


@router.get("/me")
async def get_current_user_info(
    current_user = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get current user info including roles and capabilities."""
    roles = await get_user_roles(db, current_user.id)
    capabilities = await get_user_capabilities(db, current_user.id)

    user_email = (current_user.email or current_user.username or "").lower().strip()
    admin_email_set = {e.lower().strip() for e in settings.admin_emails}
    is_superadmin = user_email in admin_email_set
    if is_superadmin:
        for r in ["admin", "inventory_manager", "system_admin", "approver"]:
            if r not in roles:
                roles.append(r)
        for c in ["iam:admin", "admin:user_management", "admin", "inventory:approve_request"]:
            if c not in capabilities:
                capabilities.append(c)

    return {
        "id": str(current_user.id),
        "username": current_user.username,
        "display_name": current_user.display_name_demo,
        "email": current_user.email,
        "phone_number": current_user.phone_number,
        "branch": current_user.branch,
        "avatar_url": getattr(current_user, "avatar_url", None),
        "roles": roles,
        "capabilities": capabilities,
    }


class UpdateProfileRequest(BaseModel):
    display_name: str = Field(min_length=1, max_length=256)
    email: str | None = None
    phone_number: str | None = None
    branch: str | None = None
    avatar_url: str | None = None


@router.put("/me")
async def update_profile(
    body: UpdateProfileRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Cập nhật thông tin hồ sơ của người dùng đang đăng nhập."""
    clean_name = body.display_name.strip()
    if not clean_name:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Họ và tên không được để trống.",
        )

    current_user.display_name_demo = clean_name
    if body.email is not None:
        current_user.email = body.email.strip() or None
    if body.phone_number is not None:
        current_user.phone_number = body.phone_number.strip() or None
    if body.branch is not None:
        current_user.branch = body.branch.strip() or None
    if body.avatar_url is not None:
        current_user.avatar_url = body.avatar_url.strip() or None

    db.add(current_user)
    await db.commit()
    await db.refresh(current_user)

    roles = await get_user_roles(db, current_user.id)
    capabilities = await get_user_capabilities(db, current_user.id)

    return {
        "id": str(current_user.id),
        "username": current_user.username,
        "display_name": current_user.display_name_demo,
        "email": current_user.email,
        "phone_number": current_user.phone_number,
        "branch": current_user.branch,
        "avatar_url": getattr(current_user, "avatar_url", None),
        "roles": roles,
        "capabilities": capabilities,
        "message": "Cập nhật hồ sơ thành công.",
    }


class ChangePasswordRequest(BaseModel):
    old_password: str = Field(min_length=1)
    new_password: str = Field(min_length=6, max_length=128)


@router.post("/change-password")
async def change_password(
    body: ChangePasswordRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Đổi mật khẩu tài khoản người dùng đang đăng nhập."""
    if not verify_password(body.old_password, current_user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Mật khẩu hiện tại không đúng.",
        )
    if body.new_password == body.old_password:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Mật khẩu mới không được trùng mật khẩu cũ.",
        )

    current_user.password_hash = get_password_hash(body.new_password)
    db.add(current_user)
    await db.commit()
    await db.refresh(current_user)

    return {"message": "Đổi mật khẩu thành công."}


class ChangePinRequest(BaseModel):
    current_password: str = Field(min_length=1)
    new_pin: str = Field(pattern=r"^\d{6}$")


@router.post("/change-pin")
async def change_pin(
    body: ChangePinRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Cập nhật mã PIN 6 số của Kiểm soát viên (xác thực bằng mật khẩu)."""
    if not verify_password(body.current_password, current_user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Mật khẩu tài khoản không đúng.",
        )

    current_user.pin_hash = get_password_hash(body.new_pin)
    db.add(current_user)
    await db.commit()
    await db.refresh(current_user)

    return {"message": "Đổi mã PIN kiểm soát viên thành công."}


class ForgotPasswordRequest(BaseModel):
    username: str = Field(min_length=1, max_length=64)


@router.post("/forgot-password")
async def forgot_password(
    body: ForgotPasswordRequest,
    db: AsyncSession = Depends(get_db),
):
    """Yêu cầu mã xác thực OTP để khôi phục mật khẩu."""
    username_clean = body.username.strip()
    result = await db.execute(
        select(User).where(
            or_(
                User.username == username_clean,
                func.lower(User.email) == username_clean.lower(),
            )
        )
    )
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Không tìm thấy tài khoản với tên đăng nhập hoặc email này.",
        )
    if user.status != "active":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Tài khoản đang bị khóa hoặc không hoạt động.",
        )

    otp = generate_password_reset_otp(user.username)

    target_email = (user.email or "").strip()
    if not target_email and "@" in user.username:
        target_email = user.username.strip()

    email_sent = False
    if target_email:
        email_sent = await send_password_reset_email(
            to_email=target_email,
            username=user.display_name_demo or user.username,
            otp=otp,
        )

    msg = (
        f"Mã xác thực OTP đã được gửi về email {target_email}."
        if email_sent
        else f"Mã xác thực OTP đã được tạo cho tài khoản {user.username}."
    )

    return {
        "message": msg,
        "username": user.username,
        "otp_demo": otp,
        "email_sent": email_sent,
        "expires_in_seconds": 900,
    }


class ResetPasswordRequest(BaseModel):
    username: str = Field(min_length=1, max_length=64)
    otp: str = Field(pattern=r"^\d{6}$")
    new_password: str = Field(min_length=6, max_length=128)


@router.post("/reset-password")
async def reset_password(
    body: ResetPasswordRequest,
    db: AsyncSession = Depends(get_db),
):
    """Đặt lại mật khẩu mới bằng mã xác thực OTP."""
    username_clean = body.username.strip()
    result = await db.execute(
        select(User).where(
            or_(
                User.username == username_clean,
                func.lower(User.email) == username_clean.lower(),
            )
        )
    )
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Không tìm thấy tài khoản với tên đăng nhập này.",
        )
    if user.status != "active":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Tài khoản đang bị khóa hoặc không hoạt động.",
        )

    if not (
        verify_password_reset_otp(user.username, body.otp)
        or verify_password_reset_otp(username_clean, body.otp)
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Mã xác thực OTP không chính xác hoặc đã hết hạn.",
        )

    user.password_hash = get_password_hash(body.new_password)
    db.add(user)
    await db.commit()
    await db.refresh(user)

    # Đặt lại số lần đăng nhập thất bại nếu có
    reset_login_failures(user.username)

    return {"message": "Khôi phục mật khẩu thành công. Vui lòng đăng nhập bằng mật khẩu mới."}

