"""Application configuration."""
import os
import secrets
from pathlib import Path
from typing import Literal

from dotenv import dotenv_values
from pydantic import Field, SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings

_backend_env = Path(__file__).resolve().parent.parent / ".env"
_root_env = Path(__file__).resolve().parent.parent.parent / ".env"
_env_vals: dict[str, str | None] = {}
if _root_env.exists():
    _env_vals.update(dotenv_values(_root_env))
if _backend_env.exists():
    _env_vals.update(dotenv_values(_backend_env))

# Secret ephemeral per-process cho môi trường demo/test: không hardcode hằng
# công khai, không ký JWT bằng key rỗng, và không thể forge từ bên ngoài
# (không chia sẻ process). Sản xuất bắt buộc set env (xem `signing_key`).
_ephemeral_secrets: dict[str, str] = {}


def _ephemeral_secret(name: str) -> str:
    if name not in _ephemeral_secrets:
        _ephemeral_secrets[name] = secrets.token_urlsafe(48)
    return _ephemeral_secrets[name]


class Settings(BaseSettings):
    app_env: str = Field(default="demo")
    app_name: str = Field(default="kho-tra-sua-api")

    database_url: str = Field(
        default_factory=lambda: os.environ.get("DATABASE_URL")
        or _env_vals.get("DATABASE_URL")
        or "postgresql+psycopg2://kho-tra-sua:kho-tra-sua@localhost:5432/kho-tra-sua"
    )

    jwt_signing_key_ref: str = Field(default="signing")
    jwt_algorithm: str = Field(default="HS256")
    access_token_expire_minutes: int = Field(default=30)
    refresh_token_expire_days: int = Field(default=7)

    allowed_origins: list[str] | str = Field(
        default=[
            "http://localhost:3000",
            "http://localhost:5000",
            "http://localhost:8080",
            "http://127.0.0.1:3000",
            "http://127.0.0.1:5000",
            "http://127.0.0.1:8080",
            "https://quan-ly-kho-tra-sua.tanmainguyenbinh.workers.dev",
            # Thay bằng domain deploy của bạn ở đây (https://...).
            "https://your-domain.example.com",
        ]
    )

    @field_validator("allowed_origins", mode="after")
    @classmethod
    def _parse_allowed_origins(cls, v: list[str] | str) -> list[str]:
        if isinstance(v, str):
            return [x.strip() for x in v.split(",") if x.strip()]
        return v

    idempotency_key_retention_hours: int = Field(default=24)

    # Origin của frontend để tạo link absolute trong email mời (invite) / OTP.
    # Local mặc định; production bắt buộc set FRONTEND_BASE_URL=https://domain-cua-ban.
    frontend_base_url: str = Field(
        default_factory=lambda: os.environ.get("FRONTEND_BASE_URL")
        or _env_vals.get("FRONTEND_BASE_URL")
        or "https://quan-ly-kho-tra-sua.tanmainguyenbinh.workers.dev"
    )

    server_host: str = Field(default="0.0.0.0")
    server_port: int = Field(default=8000)
    server_reload: bool = Field(default=True)

    connector_secret_ref: str = Field(default="")
    sse_retention_days: int = Field(default=7)
    staging_ttl_hours: int = Field(default=24)
    sheets_timeout_seconds: int = Field(default=15)

    # Integration Hub (docs/09): secret cho Apps Script webhook + Sheet sandbox.
    google_sheets_api_key: str = Field(default="")
    apps_script_webhook_secret: str = Field(default="")

    rate_limit_login_attempts: int = Field(default=5)
    rate_limit_login_window_minutes: int = Field(default=15)

    # SMTP Email Configuration (Gmail / Transactional Email)
    smtp_host: str = Field(
        default_factory=lambda: os.environ.get("SMTP_HOST")
        or _env_vals.get("SMTP_HOST")
        or "smtp.gmail.com"
    )
    smtp_port: int = Field(
        default_factory=lambda: int(
            os.environ.get("SMTP_PORT") or _env_vals.get("SMTP_PORT") or 587
        )
    )
    smtp_user: str = Field(
        default_factory=lambda: os.environ.get("SMTP_USER")
        or _env_vals.get("SMTP_USER")
        or ""
    )
    smtp_password: str = Field(
        default_factory=lambda: os.environ.get("SMTP_PASSWORD")
        or _env_vals.get("SMTP_PASSWORD")
        or ""
    )
    smtp_from_name: str = Field(
        default_factory=lambda: os.environ.get("SMTP_FROM_NAME")
        or _env_vals.get("SMTP_FROM_NAME")
        or "quan-ly-kho-tra-sua.tanmainguyenbinh.workers.dev"
    )

    ai_provider: Literal['disabled', 'cloudflare', 'ollama', 'modal_llm'] = 'disabled'
    cloudflare_account_id: str = Field(default='', pattern=r'^([a-fA-F0-9]{32})?$')
    cloudflare_api_token: SecretStr = SecretStr('')
    cloudflare_model: str = '@cf/meta/llama-3.1-8b-instruct'
    ollama_base_url: str = 'http://localhost:11434'
    ollama_model: str = 'qwen2.5:1.5b'
    modal_llm_url: str = Field(
        default='',
        description='Endpoint OpenAI-compatible của space LLM bạn (thay thế bằng giá trị thực tế).',
    )
    modal_llm_model: str = Field(default='Qwen2.5-1.5B-Instruct.Q4_K_M')
    ai_timeout_seconds: int = Field(default=120, ge=1, le=300)
    ai_requests_per_minute: int = Field(default=10, ge=1, le=100)
    supervisor_pin: SecretStr = SecretStr('')

    # Google Sign-In: OAuth client IDs are public identifiers (safe in code).
    # The web client *secret* must never be committed; it lives only in server
    # env for a future authorization-code exchange flow (not needed for the
    # ID-token flow used by the mobile app).
    google_allowed_audiences: list[str] = Field(
        default=[
            # iOS client (GoogleService-Info.plist CLIENT_ID)
            "1070073470852-apcl0c8sgvt9c4f6qscpjgcrgtje4tjn.apps.googleusercontent.com",
            # Web client (used by some Android configurations as audience)
            "1070073470852-hc12cgovbt9h7micnu072vpkvigee28u.apps.googleusercontent.com",
        ]
    )
    google_client_id: str = Field(
        default="1070073470852-apcl0c8sgvt9c4f6qscpjgcrgtje4tjn.apps.googleusercontent.com"
    )

    admin_emails: list[str] = Field(
        default=[
            "tanmainguyenbinh@gmail.com",
            "tanmainguyenbinhtan@gmail.com",
        ]
    )

    @property
    def is_demo(self) -> bool:
        return self.app_env == "demo"

    @property
    def session_secret(self) -> str:
        """Env trước; demo/test fallback secret ephemeral (không hardcode)."""
        env_value = os.environ.get("BANKOPS_SESSION_SECRET", "")
        if env_value:
            return env_value
        if self.app_env in ("demo", "test"):
            return _ephemeral_secret("session")
        raise RuntimeError(
            "BANKOPS_SESSION_SECRET must be set outside demo environments"
        )

    @property
    def signing_key(self) -> str:
        key = os.environ.get("BANKOPS_SIGNING_KEY", "") or os.environ.get(
            f"BANKOPS_{self.jwt_signing_key_ref}", ""
        )
        if key:
            return key
        if self.app_env in ("demo", "test"):
            return _ephemeral_secret("jwt-signing")
        raise RuntimeError(
            "JWT signing key must be set via BANKOPS_SIGNING_KEY environment variable"
        )

    @model_validator(mode='after')
    def _validate_ai_provider(self) -> 'Settings':
        """Bắt buộc cấu hình LLM ở môi trường sản xuất/staging; dev mặc định 'disabled'.

        Quy tắc:
          - `disabled` (mặc định dev): không yêu cầu env, app không bị chặn khởi động.
          - `cloudflare`: production/staging bắt buộc CLOUDFLARE_ACCOUNT_ID + CLOUDFLARE_API_TOKEN.
          - `ollama`: production/staging bắt buộc OLLAMA_BASE_URL + OLLAMA_MODEL.
          - `modal_llm`: production/staging bắt buộc MODAL_LLM_URL + MODAL_LLM_MODEL.
            Giá trị rỗng ở bất kỳ môi trường nào → lỗi khởi động, không để nguyên
            mô hình fine-tune cũ trên máy làm giá trị tạm.
        """
        provider = self.ai_provider
        if provider == 'disabled':
            return self
        if self.app_env not in ('production', 'staging'):
            return self

        required = []
        if provider == 'cloudflare':
            if not self.cloudflare_account_id:
                required.append('CLOUDFLARE_ACCOUNT_ID')
            if not self.cloudflare_api_token.get_secret_value():
                required.append('CLOUDFLARE_API_TOKEN')
        elif provider == 'ollama':
            if not self.ollama_base_url:
                required.append('OLLAMA_BASE_URL')
            if not self.ollama_model:
                required.append('OLLAMA_MODEL')
        elif provider == 'modal_llm':
            if not self.modal_llm_url:
                required.append('MODAL_LLM_URL')
            if not self.modal_llm_model:
                required.append('MODAL_LLM_MODEL')
        else:  # pragma: no cover - deveris safeguard
            required.append(f'{provider.upper()}_PROVIDER')

        if required:
            raise ValueError(
                f"Không khởi động được: AI provider '{provider}' không được cấu hình "
                f"ở chế độ sản xuất/staging. Thiếu: {', '.join(required)}. "
                "Cấu hình qua biến môi trường (ví dụ: CLOUDFLARE_ACCOUNT_ID=..., "
                "CLOUDFLARE_API_TOKEN=...); **không dùng mô hình fine-tune cũ trên máy làm "
                "giá trị tạm** — bắt buộc redeploy LLM lên HF -> Modal trước, rồi "
                "set MODAL_LLM_URL/MODAL_LLM_MODEL trỏ đúng space đã deploy."
            )
        return self


settings = Settings()
