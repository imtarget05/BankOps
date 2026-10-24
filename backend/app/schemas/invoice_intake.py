from decimal import Decimal
from typing import Any

from pydantic import BaseModel, Field


class InvoiceLineItem(BaseModel):
    raw_name: str = Field(..., description="Item name from invoice")
    sku: str | None = Field(None, description="Extracted SKU / item code")
    matched_item_id: str | None = Field(
        None, description="Resolved inv_items.id in database"
    )
    quantity: Decimal = Field(..., gt=0, description="Delivered quantity")
    unit: str | None = Field(None, description="Unit of measurement")
    unit_price: Decimal = Field(..., ge=0, description="Unit price before tax")
    line_total: Decimal = Field(..., ge=0, description="Total for this line")
    lot_no: str | None = Field(None, description="Extracted lot number")
    expiry_date: str | None = Field(
        None, description="Extracted expiry date YYYY-MM-DD"
    )


class InvoiceExtraction(BaseModel):
    supplier_name: str = Field(..., description="Supplier / vendor name")
    supplier_tax_code: str | None = Field(None, description="Tax identification code")
    invoice_no: str = Field(..., description="Invoice / receipt number")
    invoice_date: str = Field(..., description="Invoice issue date YYYY-MM-DD")
    line_items: list[InvoiceLineItem] = Field(default_factory=list)
    subtotal: Decimal = Field(..., ge=0, description="Sum of line items")
    tax_rate: Decimal | None = Field(None, description="VAT rate (e.g. 0.08 or 0.10)")
    tax_amount: Decimal = Field(
        default=Decimal("0"), ge=0, description="Tax / VAT amount"
    )
    total_amount: Decimal = Field(
        ..., ge=0, description="Total payment amount on invoice"
    )
    confidence: float = Field(
        default=1.0, ge=0.0, le=1.0, description="Overall extraction confidence score"
    )


class ValidationReport(BaseModel):
    is_valid: bool = Field(
        ..., description="True if all mathematical and mandatory checks pass"
    )
    line_math_valid: bool = Field(
        ..., description="True if each line item quantity * price == line_total"
    )
    subtotal_valid: bool = Field(
        ..., description="True if sum of line totals == subtotal"
    )
    total_valid: bool = Field(
        ..., description="True if subtotal + tax_amount == total_amount"
    )
    errors: list[str] = Field(
        default_factory=list, description="Rejection errors blocking draft creation"
    )
    warnings: list[str] = Field(
        default_factory=list, description="Non-blocking warnings (e.g. unmapped SKU)"
    )


class InvoiceIntakeResponse(BaseModel):
    extraction: InvoiceExtraction
    validation: ValidationReport
    draft_request_id: str | None = None
    status: str = Field(
        "extracted",
        description="'extracted', 'draft_created', or 'validation_failed'",
    )
    message: str


class CreateDraftFromExtractionRequest(BaseModel):
    extraction: InvoiceExtraction
    dest_location_id: str = Field(
        ..., description="Target warehouse / store location ID"
    )
