"""Authenticated advisory AI. Limits are per process (demo deployment)."""
import json
import time
import uuid
from typing import Any, Literal

import httpx
from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.routes.auth_utils import get_current_user
from app.config import settings
from app.database import get_db
from app.models.cash_sim import CashRequest
from app.models.iam import User
from app.models.inventory import InventoryRequest, InventoryRequestLine
from app.services.ai import assess_request, generate, stream_ollama
from app.services.ai_retrieval import grounded_prompt, retrieve

router = APIRouter(prefix='/ai')
_windows: dict[str, tuple[float, int]] = {}


class ChatRequest(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    message: str = Field(min_length=1, max_length=2000)


class RequestAssessmentInput(BaseModel):
    model_config = ConfigDict(extra='ignore', str_strip_whitespace=True)
    request_id: str
    # Cash/kho giữ để tương thích module cash còn lưu hành; receipt/issue/
    # transfer/adjustment/stocktake là loại phiếu kho/kiểm kê theo SRS trà sữa.
    kind: Literal['cash', 'inventory', 'quỹ', 'kho', 'receipt', 'issue', 'transfer', 'adjustment', 'stocktake'] = 'cash'
    amount_or_qty: str = '0'
    maker: str = 'Maker'
    reason: str = ''
    context: dict[str, Any] | None = None


@router.post('/assess-request')
async def assess(
    body: RequestAssessmentInput,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if user.status != 'active':
        raise HTTPException(403, 'Tài khoản không hoạt động.')
    _enforce_ai_rate_limit(user)

    # Canonical DB binding: fetch the true voucher from PostgreSQL under checker
    # scope so forged client inputs cannot change the assessed voucher.
    payload = body.model_dump()
    canonical_bound = False
    request_version = 1

    rid = None
    try:
        rid = uuid.UUID(body.request_id.strip())
    except (ValueError, TypeError, AttributeError):
        pass

    if rid is not None:
        inv_req = (
            await db.execute(select(InventoryRequest).where(InventoryRequest.id == rid))
        ).scalars().first()
        if inv_req is not None:
            # Query line totals and maker identity from authoritative DB
            sums = (
                await db.execute(
                    select(func.coalesce(func.sum(InventoryRequestLine.quantity), 0))
                    .where(InventoryRequestLine.request_id == inv_req.id)
                )
            ).scalar() or 0
            maker_user = (
                await db.execute(select(User).where(User.id == inv_req.maker_id))
            ).scalars().first()
            maker_name = maker_user.username if maker_user else "Maker"
            payload = {
                "request_id": str(inv_req.id),
                "kind": inv_req.kind,
                "amount_or_qty": str(sums),
                "maker": maker_name,
                "reason": inv_req.reason or "",
                "context": {
                    "request_version": inv_req.version,
                    "status": inv_req.status,
                    "sub_kind": inv_req.sub_kind,
                },
            }
            canonical_bound = True
            request_version = inv_req.version
        else:
            cash_req = (
                await db.execute(select(CashRequest).where(CashRequest.id == rid))
            ).scalars().first()
            if cash_req is not None:
                maker_user = (
                    await db.execute(select(User).where(User.id == cash_req.maker_id))
                ).scalars().first()
                maker_name = maker_user.username if maker_user else "Maker"
                payload = {
                    "request_id": str(cash_req.id),
                    "kind": "cash",
                    "amount_or_qty": str(cash_req.amount),
                    "maker": maker_name,
                    "reason": cash_req.reason or "",
                    "context": {
                        "request_version": cash_req.version,
                        "status": cash_req.status,
                    },
                }
                canonical_bound = True
                request_version = cash_req.version

    if not canonical_bound and settings.app_env in ("production", "prod"):
        raise HTTPException(404, f"Không tìm thấy phiếu '{body.request_id}' trong hệ thống.")

    async with httpx.AsyncClient(timeout=settings.ai_timeout_seconds) as client:
        result = await assess_request(payload, settings, client)
        result["canonical_bound"] = canonical_bound
        result["request_version"] = request_version
        result["assessed_by"] = user.username
        return result


def _enforce_ai_rate_limit(user: User) -> None:
    now = time.monotonic()
    for key, (start, _) in list(_windows.items()):
        if now - start >= 60:
            del _windows[key]
    key = str(user.id)
    start, count = _windows.get(key, (now, 0))
    if count >= settings.ai_requests_per_minute:
        raise HTTPException(429, 'Bạn đã vượt giới hạn AI. Thử lại sau một phút.', headers={'Retry-After': '60'})
    _windows[key] = (start, count + 1)


@router.post('/chat')
async def chat(body: ChatRequest, user: User = Depends(get_current_user)):
    if user.status != 'active':
        raise HTTPException(403, 'Tài khoản không hoạt động.')
    _enforce_ai_rate_limit(user)
    sources = retrieve(body.message)
    if not sources:
        return {'answer': 'Chưa tìm thấy thông tin phù hợp trong tài liệu nghiệp vụ.', 'sources': [], 'simulation': True}
    try:
        async with httpx.AsyncClient(timeout=settings.ai_timeout_seconds) as client:
            result = await generate(grounded_prompt(body.message, sources), settings, client)
    except HTTPException:
        top = sources[0]
        answer = f"Theo tài liệu nghiệp vụ ({top['source']} · {top['section']}):\n{top['content']}"
        result = {'answer': answer, 'provider': 'grounded_fallback', 'model': 'docs_extract', 'simulation': True}
    return {**result, 'sources': [{k: v for k, v in source.items() if k != 'content'} for source in sources]}


@router.post('/chat/stream')
async def chat_stream(body: ChatRequest, user: User = Depends(get_current_user)):
    if user.status != 'active':
        raise HTTPException(403, 'Tài khoản không hoạt động.')
    _enforce_ai_rate_limit(user)
    sources = retrieve(body.message)

    async def events():
        refs = [{k: v for k, v in source.items() if k != 'content'} for source in sources]
        yield f"event: sources\ndata: {json.dumps(refs, ensure_ascii=False)}\n\n"
        if not sources:
            answer = 'Chưa tìm thấy thông tin phù hợp trong tài liệu nghiệp vụ.'
        else:
            try:
                async with httpx.AsyncClient(timeout=settings.ai_timeout_seconds) as client:
                    prompt = grounded_prompt(body.message, sources)
                    if settings.ai_provider == 'ollama':
                        async for token in stream_ollama(prompt, settings, client):
                            yield f"event: delta\ndata: {json.dumps({'text': token}, ensure_ascii=False)}\n\n"
                        yield 'event: done\ndata: {}\n\n'
                        return
                    result = await generate(prompt, settings, client)
                    answer = result['answer']
            except HTTPException:
                top = sources[0]
                answer = f"Theo tài liệu nghiệp vụ ({top['source']} · {top['section']}):\n{top['content']}"
        for offset in range(0, len(answer), 80):
            yield f"event: delta\ndata: {json.dumps({'text': answer[offset:offset + 80]}, ensure_ascii=False)}\n\n"
        yield 'event: done\ndata: {}\n\n'

    return StreamingResponse(events(), media_type='text/event-stream', headers={'Cache-Control': 'no-cache', 'X-Accel-Buffering': 'no'})

