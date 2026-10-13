import asyncio
import json
from collections.abc import AsyncGenerator

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from fastapi.responses import StreamingResponse
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.routes.auth_utils import (
    get_user_capabilities,
    get_user_from_token_string,
    require_capability,
)
from app.database import get_db
from app.models.cash_sim import CashRequest
from app.models.iam import User
from app.models.inventory import InventoryRequest, InventoryRequestLine
from app.services.approval_events import approval_event_bus

router = APIRouter()


@router.get("/inbox")
async def get_approval_inbox(
    current_user=Depends(require_capability("approval:view_inbox")),
    db: AsyncSession = Depends(get_db),
):
    """Get pending approvals for current user (cần capability approve — docs/06)."""
    users = {
        str(u.id): (u.display_name_demo or u.username)
        for u in (await db.execute(select(User))).scalars().all()
    }
    inv_rows = (
        await db.execute(
            select(InventoryRequest)
            .where(InventoryRequest.status == "submitted")
            .order_by(InventoryRequest.submitted_at.asc())
        )
    ).scalars().all()
    cash_rows = (
        await db.execute(
            select(CashRequest)
            .where(CashRequest.status == "submitted")
            .order_by(CashRequest.submitted_at.asc())
        )
    ).scalars().all()

    approvals = []
    for r in inv_rows:
        line_count = (
            await db.execute(
                select(func.coalesce(func.sum(InventoryRequestLine.quantity), 0)).where(
                    InventoryRequestLine.request_id == r.id
                )
            )
        ).scalar_one()
        maker_id = str(r.maker_id)
        approvals.append(
            {
                "id": str(r.id),
                "kind": "inventory",
                "sub_kind": r.kind,
                "status": r.status,
                "maker_id": maker_id,
                "maker": users.get(maker_id, maker_id),
                "impact": f"Kho ({r.kind}) · {line_count} đơn vị",
                "approval_detail": {"kind": r.kind, "total_quantity": str(line_count)},
                "detail": r.reason or f"Phiếu kho {r.kind}",
            }
        )

    for r in cash_rows:
        maker_id = str(r.maker_id)
        approvals.append(
            {
                "id": str(r.id),
                "kind": "cash",
                "sub_kind": r.kind,
                "status": r.status,
                "maker_id": maker_id,
                "maker": users.get(maker_id, maker_id),
                "impact": f"Quỹ ({r.kind}) · {r.amount} VND",
                "detail": r.reason or f"Phiếu quỹ {r.kind}",
            }
        )
    return {"approvals": approvals}


async def approval_event_generator(request: Request, user: User) -> AsyncGenerator[str, None]:
    queue = await approval_event_bus.subscribe()
    try:
        init_payload = json.dumps(
            {"status": "connected", "username": user.username, "user_id": str(user.id)},
            ensure_ascii=False,
        )
        yield f"event: connected\ndata: {init_payload}\n\n"
        while True:
            if await request.is_disconnected():
                break
            try:
                payload = await asyncio.wait_for(queue.get(), timeout=15.0)
                yield f"event: approval_update\ndata: {payload}\n\n"
            except asyncio.TimeoutError:
                yield ": keepalive ping\n\n"
    finally:
        await approval_event_bus.unsubscribe(queue)


@router.get("/stream")
async def stream_approval_events(
    request: Request,
    token: str | None = Query(None, description="JWT access token for EventSource / SSE"),
    db: AsyncSession = Depends(get_db),
):
    """Native Server-Sent Events (SSE) endpoint broadcasting real-time Maker-Checker approvals.

    Allows browser tabs and clients to receive push notifications on approval state changes
    instantly without polling.

    Authentication:
    Accepts JWT access token via query parameter `?token=...` (EventSource standard) or
    `Authorization: Bearer <token>` header.
    """
    raw_token = token
    if not raw_token:
        auth_header = request.headers.get("Authorization")
        if auth_header and auth_header.startswith("Bearer "):
            raw_token = auth_header[7:].strip()

    if not raw_token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing authentication token for SSE stream",
            headers={"WWW-Authenticate": "Bearer"},
        )

    user = await get_user_from_token_string(raw_token, db)
    caps = await get_user_capabilities(db, user.id)
    allowed_caps = {"approval:view_inbox", "inventory:view_requests", "cash:view_requests"}
    if not any(c in caps for c in allowed_caps):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User does not have permission to subscribe to approval stream",
        )

    return StreamingResponse(
        approval_event_generator(request, user),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache, no-transform",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )
