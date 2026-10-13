"""Authenticated advisory AI. Limits are per process (demo deployment)."""
import time
from typing import Literal

import httpx
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field

from app.api.routes.auth_utils import get_current_user
from app.config import settings
from app.models.iam import User
from app.services.ai import assess_request, generate

router = APIRouter(prefix='/ai')
_windows: dict[str, tuple[float, int]] = {}


class ChatRequest(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    message: str = Field(min_length=1, max_length=2000)


class RequestAssessmentInput(BaseModel):
    model_config = ConfigDict(extra='ignore', str_strip_whitespace=True)
    request_id: str
    kind: Literal['cash', 'inventory', 'quỹ', 'kho'] = 'cash'
    amount_or_qty: str = '0'
    maker: str = 'Maker'
    reason: str = ''
    context: dict | None = None


@router.post('/assess-request')
async def assess(body: RequestAssessmentInput, user: User = Depends(get_current_user)):
    if user.status != 'active':
        raise HTTPException(403, 'Tài khoản không hoạt động.')
    async with httpx.AsyncClient() as client:
        return await assess_request(body.model_dump(), settings, client)


@router.post('/chat')
async def chat(body: ChatRequest, user: User = Depends(get_current_user)):
    if user.status != 'active':
        raise HTTPException(403, 'Tài khoản không hoạt động.')
    now = time.monotonic()
    for key, (start, _) in list(_windows.items()):
        if now - start >= 60:
            del _windows[key]
    key = str(user.id)
    start, count = _windows.get(key, (now, 0))
    if count >= settings.ai_requests_per_minute:
        raise HTTPException(429, 'Bạn đã vượt giới hạn AI. Thử lại sau một phút.', headers={'Retry-After': '60'})
    _windows[key] = (start, count + 1)
    async with httpx.AsyncClient() as client:
        return await generate(body.message, settings, client)

