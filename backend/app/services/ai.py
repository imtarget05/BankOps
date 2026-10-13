"""Bounded text-only inference; no tools, database writes or implicit fallback."""
from pathlib import Path

import httpx
from fastapi import HTTPException

from app.config import Settings

SYSTEM_PROMPT = Path(__file__).with_name('ai_system_prompt.txt').read_text().strip()
UNAVAILABLE = 'Trợ lý AI chưa sẵn sàng. Vui lòng thử lại hoặc kiểm tra cấu hình máy chủ.'


async def generate(message: str, settings: Settings, client: httpx.AsyncClient) -> dict:
    provider = settings.ai_provider
    messages = [{'role': 'system', 'content': SYSTEM_PROMPT}, {'role': 'user', 'content': message}]
    headers = {}
    if provider == 'cloudflare':
        if not settings.cloudflare_account_id or not settings.cloudflare_api_token.get_secret_value():
            raise HTTPException(503, UNAVAILABLE)
        model = settings.cloudflare_model
        url = f'https://api.cloudflare.com/client/v4/accounts/{settings.cloudflare_account_id}/ai/run/{model}'
        headers['Authorization'] = f'Bearer {settings.cloudflare_api_token.get_secret_value()}'
        payload = {'messages': messages, 'max_tokens': 512, 'temperature': 0.2, 'stream': False}
    elif provider == 'ollama':
        model = settings.ollama_model
        url = f'{settings.ollama_base_url.rstrip("/")}/api/chat'
        payload = {
            'model': model,
            'messages': messages,
            'stream': False,
            'options': {'temperature': 0.2, 'num_predict': 512, 'num_ctx': 2048, 'num_gpu': 0},
        }
    else:
        raise HTTPException(503, UNAVAILABLE)
    try:
        response = await client.post(url, headers=headers, json=payload, timeout=settings.ai_timeout_seconds)
        response.raise_for_status()
        body = response.json()
        if provider == 'cloudflare':
            if body.get('success') is not True:
                raise ValueError('Provider rejected request')
            answer = body['result']['response']
        else:
            answer = body['message']['content']
        if not isinstance(answer, str) or not answer.strip():
            raise ValueError('Empty response')
    except (httpx.HTTPError, ValueError, KeyError, TypeError, AttributeError):
        # Never expose upstream bodies, credentials or prompts in logs/errors.
        raise HTTPException(503, UNAVAILABLE) from None
    return {'answer': answer.strip(), 'provider': provider, 'model': model, 'simulation': True}
