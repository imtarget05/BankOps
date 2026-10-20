"""Shared keyset (cursor) pagination helpers.

Every list endpoint exposes ``limit`` (1..100) and an opaque ``cursor``
per docs/06. A cursor encodes the sort-key values of the last row on the
page; passing it back filters the queryset to rows *after* that row in the
endpoint's stable sort order.
"""
from __future__ import annotations

import base64
import binascii
import json
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from typing import Any

from sqlalchemy import and_, or_

from app.api.errors import AppError

MAX_LIMIT = 100
DEFAULT_LIMIT = 50


def clamp_limit(limit: Any, default: int = DEFAULT_LIMIT) -> int:
    try:
        value = int(limit)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return default
    return max(1, min(value, MAX_LIMIT))


def encode_cursor(payload: dict[str, Any]) -> str:
    raw = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode()
    return base64.urlsafe_b64encode(raw).decode()


def decode_cursor(cursor: str | None) -> dict[str, Any] | None:
    if cursor is None or not str(cursor).strip():
        return None
    text = str(cursor).strip()
    try:
        padded = text + "=" * (-len(text) % 4)
        raw = base64.urlsafe_b64decode(padded.encode()).decode()
    except (ValueError, TypeError, binascii.Error, UnicodeDecodeError):
        raise AppError(400, "INVALID_CURSOR", "cursor khong hop le") from None
    try:
        data = json.loads(raw)
    except (ValueError, TypeError):
        # Legacy balances cursors were plain ``base64("location_id:item_id")``
        # without JSON framing — accept them for backwards compatibility.
        legacy = _decode_legacy_balances_payload(raw)
        if legacy is not None:
            return legacy
        raise AppError(400, "INVALID_CURSOR", "cursor khong hop le") from None
    if isinstance(data, str):
        legacy = _decode_legacy_balances_payload(data)
        if legacy is not None:
            return legacy
        raise AppError(400, "INVALID_CURSOR", "cursor khong hop le") from None
    if not isinstance(data, dict):
        raise AppError(400, "INVALID_CURSOR", "cursor khong hop le")
    return data


def _decode_legacy_balances_payload(raw: str) -> dict[str, Any] | None:
    if ":" not in raw:
        return None
    loc, _, item = raw.partition(":")
    if not loc or not item:
        return None
    return {"location_id": loc, "item_id": item}


@dataclass(frozen=True)
class KeysetSpec:
    """Describes one endpoint's stable sort order for keyset paging."""

    columns: tuple[Any, ...]
    descending: tuple[bool, ...]
    keys: tuple[str, ...]
    attrs: tuple[str, ...]
    coerce: tuple[Callable[[Any], Any], ...]

    def __post_init__(self) -> None:
        n = len(self.columns)
        if not (len(self.descending) == len(self.keys) == len(self.attrs) == len(self.coerce) == n):
            raise ValueError("KeysetSpec fields must all have the same length")


def build_cursor_payload(spec: KeysetSpec, row: Any) -> dict[str, Any]:
    return {key: _json_scalar(getattr(row, attr)) for key, attr in zip(spec.keys, spec.attrs, strict=True)}


def apply_keyset(stmt: Any, spec: KeysetSpec, payload: dict[str, Any] | None) -> Any:
    """Apply the WHERE clause selecting rows after the cursor position."""
    if not payload:
        return stmt
    values: list[Any] = []
    try:
        raw_values = [payload[key] for key in spec.keys]
    except KeyError:
        raise AppError(400, "INVALID_CURSOR", "cursor khong hop le") from None
    for raw, coerce in zip(raw_values, spec.coerce, strict=True):
        try:
            values.append(coerce(raw))
        except (ValueError, TypeError, AttributeError):
            raise AppError(400, "INVALID_CURSOR", "cursor khong hop le") from None
    return stmt.where(_keyset_clause(spec.columns, values, spec.descending))


def _keyset_clause(columns: Sequence[Any], values: Sequence[Any], descending: Sequence[bool]) -> Any:
    parts = []
    n = len(columns)
    for i in range(n - 1, -1, -1):
        prefix = [columns[j] == values[j] for j in range(i)]
        col, val = columns[i], values[i]
        cmp_expr = col < val if descending[i] else col > val
        parts.append(and_(*prefix, cmp_expr) if prefix else cmp_expr)
    return or_(*parts)


def _json_scalar(value: Any) -> Any:
    if value is None:
        return None
    if isinstance(value, (str, int, float, bool)):
        return value
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return str(value)


def coerce_timestamp(raw: Any) -> Any:
    """Parse an ISO-8601 cursor value back into a datetime."""
    from datetime import datetime

    if isinstance(raw, datetime):
        return raw
    return datetime.fromisoformat(str(raw))
