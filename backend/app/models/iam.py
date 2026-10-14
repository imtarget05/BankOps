"""IAM models - Identity, Organization, Scopes, and Access Management."""
import enum
from datetime import datetime

from sqlalchemy import Boolean, Column, DateTime, Enum, ForeignKey, Integer, String
from sqlalchemy.dialects.postgresql import UUID

from app.db.base import Base, TimestampMixin, utc_now


class UserStatus(enum.StrEnum):
    active = "active"
    inactive = "inactive"
    locked = "locked"


class Branch(Base, TimestampMixin):
    """Organizational branch."""
    __tablename__ = "org_branches"

    id: str = Column(UUID(as_uuid=True), primary_key=True)
    code: str = Column(String(64), unique=True, nullable=False, index=True)
    name: str = Column(String(256), nullable=False)
    address: str | None = Column(String(512), nullable=True)
    active: bool = Column(Boolean, default=True, nullable=False)

    def __repr__(self):
        return f"<Branch {self.code}: {self.name}>"


class User(Base, TimestampMixin):
    __tablename__ = "iam_users"

    id: str = Column(UUID(as_uuid=True), primary_key=True)
    username: str = Column(String(64), unique=True, nullable=False, index=True)
    password_hash: str = Column(String(256), nullable=False)
    pin_hash: str | None = Column(String(256), nullable=True)
    status: UserStatus = Column(Enum(UserStatus), nullable=False, default=UserStatus.active)
    display_name_demo: str = Column(String(256), nullable=False)
    email: str | None = Column(String(256), nullable=True)
    phone_number: str | None = Column(String(32), nullable=True)
    branch: str | None = Column(String(256), nullable=True)
    branch_id: str | None = Column(UUID(as_uuid=True), ForeignKey("org_branches.id", ondelete="SET NULL"), nullable=True)

    # User provisioning & session controls
    must_change_password: bool = Column(Boolean, default=False, nullable=False)
    invite_token_hash: str | None = Column(String(128), nullable=True)
    invite_expires_at: datetime | None = Column(DateTime(timezone=True), nullable=True)
    auth_version: int = Column(Integer, default=1, nullable=False)

    def __repr__(self):
        return f"<User {self.username}>"


class ScopeGrant(Base, TimestampMixin):
    """Data scope grant for a user (branch and/or location level)."""
    __tablename__ = "iam_scope_grants"

    id: str = Column(UUID(as_uuid=True), primary_key=True)
    user_id: str = Column(UUID(as_uuid=True), ForeignKey("iam_users.id", ondelete="CASCADE"), nullable=False, index=True)
    branch_id: str | None = Column(UUID(as_uuid=True), ForeignKey("org_branches.id", ondelete="CASCADE"), nullable=True)
    location_id: str | None = Column(UUID(as_uuid=True), ForeignKey("inv_locations.id", ondelete="CASCADE"), nullable=True)
    capability: str | None = Column(String(64), nullable=True)
    valid_from: datetime | None = Column(DateTime(timezone=True), nullable=True)
    valid_to: datetime | None = Column(DateTime(timezone=True), nullable=True)
    granted_by: str | None = Column(UUID(as_uuid=True), ForeignKey("iam_users.id", ondelete="SET NULL"), nullable=True)

    def is_currently_valid(self, at: datetime | None = None) -> bool:
        check_time = at or utc_now()
        if self.valid_from and check_time < self.valid_from:
            return False
        if self.valid_to and check_time > self.valid_to:
            return False
        return True

    def __repr__(self):
        return f"<ScopeGrant user={self.user_id} branch={self.branch_id} loc={self.location_id}>"


class Role(Base, TimestampMixin):
    __tablename__ = "iam_roles"

    code: str = Column(String(64), primary_key=True)
    name: str = Column(String(128), nullable=False)
    description: str = Column(String(512), nullable=True)

    def __repr__(self):
        return f"<Role {self.code}>"


class Capability(Base, TimestampMixin):
    __tablename__ = "iam_capabilities"

    code: str = Column(String(64), primary_key=True)
    name: str = Column(String(128), nullable=False)
    description: str = Column(String(512), nullable=True)

    def __repr__(self):
        return f"<Capability {self.code}>"


class UserRole(Base):
    __tablename__ = "iam_user_roles"

    user_id: str = Column(UUID(as_uuid=True), primary_key=True)
    role_code: str = Column(String(64), primary_key=True)

    def __repr__(self):
        return f"<UserRole {self.user_id} -> {self.role_code}>"


class RoleCapability(Base):
    __tablename__ = "iam_role_capabilities"

    role_code: str = Column(String(64), primary_key=True)
    capability_code: str = Column(String(64), primary_key=True)