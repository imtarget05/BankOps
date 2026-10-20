"""Expense & Supplier models (Phase M — S1: Data Engineering foundation).

Master data for expense tracking and supplier master, used by Airflow
ingestion DAGs and ML expense anomaly detection / inventory demand forecasting.

Enforces:
  - Branch scoping (multi-tenant)
  - Supplier code uniqueness
  - Expense code uniqueness
  - Non-negative amount
"""

from datetime import date

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Column,
    Date,
    ForeignKey,
    Index,
    Numeric,
    String,
)
from sqlalchemy.dialects.postgresql import UUID

from app.db.base import Base, TimestampMixin, uuid_gen


class Supplier(Base, TimestampMixin):
    """Nha cung cap — master data duoc boi chuong trinh Airflow nhap vao."""

    __tablename__ = "suppliers"

    id: str = Column(UUID(as_uuid=True), primary_key=True, default=uuid_gen)
    code: str = Column(String(64), unique=True, nullable=False, index=True)
    name: str = Column(String(256), nullable=False)
    contact_person: str | None = Column(String(256), nullable=True)
    phone: str | None = Column(String(32), nullable=True)
    email: str | None = Column(String(256), nullable=True)
    address: str | None = Column(String(512), nullable=True)
    is_active: bool = Column(Boolean, default=True, nullable=False)
    branch_id: str | None = Column(
        UUID(as_uuid=True), ForeignKey("org_branches.id", ondelete="SET NULL"), nullable=True
    )

    __table_args__ = (
        Index("ix_suppliers_branch_id", "branch_id"),
    )

    def __repr__(self) -> str:
        return f"<Supplier {self.code}>"


class Expense(Base, TimestampMixin):
    """Giao dich chi phi — duoc nhap bang Airflow DAG, du lieu dau vao cho ML anomaly detection."""

    __tablename__ = "expenses"

    id: str = Column(UUID(as_uuid=True), primary_key=True, default=uuid_gen)
    expense_code: str = Column(String(64), unique=True, nullable=False, index=True)
    supplier_id: str | None = Column(
        UUID(as_uuid=True), ForeignKey("suppliers.id", ondelete="SET NULL"), nullable=True
    )
    category: str = Column(String(128), nullable=False)
    amount: float = Column(Numeric(14, 2), nullable=False)
    currency: str = Column(String(8), nullable=False, default="VND")
    expense_date: date = Column(Date, nullable=False)
    description: str | None = Column(String(1024), nullable=True)
    status: str = Column(String(32), nullable=False, default="draft")  # draft, posted, cancelled
    branch_id: str | None = Column(
        UUID(as_uuid=True), ForeignKey("org_branches.id", ondelete="SET NULL"), nullable=True
    )

    __table_args__ = (
        CheckConstraint("amount >= 0", name="ck_expenses_amount_non_negative"),
        Index("ix_expenses_branch_id", "branch_id"),
        Index("ix_expenses_expense_date", "expense_date"),
        Index("ix_expenses_supplier_id", "supplier_id"),
    )

    def __repr__(self) -> str:
        return f"<Expense {self.expense_code}>"
