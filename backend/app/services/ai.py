import hashlib
import re
from pathlib import Path

import httpx
from fastapi import HTTPException

from app.config import Settings

SYSTEM_PROMPT = Path(__file__).with_name('ai_system_prompt.txt').read_text().strip()
UNAVAILABLE = 'Trợ lý AI chưa sẵn sàng. Vui lòng thử lại hoặc kiểm tra cấu hình máy chủ.'


def assess_request_heuristic(data: dict) -> dict:
    request_id = str(data.get('request_id', 'REQ-000'))
    kind = str(data.get('kind', 'cash')).lower()
    amount_str = str(data.get('amount_or_qty', '0'))
    maker = str(data.get('maker', 'Maker GDV'))
    reason = str(data.get('reason', '')).strip()

    cleaned = re.sub(r'[\.,]\d{1,2}(?:\s|[a-zA-Z]|$)', '', amount_str)
    digits = re.sub(r'[^\d]', '', cleaned)
    value = int(digits) if digits else 0

    flagged_rules = []
    recommendations = []

    if 'cash' in kind or 'quỹ' in kind:
        if value >= 500_000_000:
            risk_level = 'high'
            risk_score = 88
            flagged_rules.append('Giá trị giao dịch vượt ngưỡng kiểm soát kép đặc biệt (≥ 500.000.000 VND).')
            flagged_rules.append('Bắt buộc xác thực mã PIN Kiểm soát viên và sinh mã Audit Stamp SHA-256.')
            recommendations.append('Kiểm đếm tiền mặt thực tế tại két và đối chiếu phiếu rút/nộp tiền gốc.')
            recommendations.append('Yêu cầu 2 chữ ký Maker và Checker trên biên bản bàn giao tiền mặt.')
        elif value >= 200_000_000:
            risk_level = 'medium'
            risk_score = 58
            flagged_rules.append('Giao dịch giá trị trung bình lớn (200.000.000 - 500.000.000 VND).')
            recommendations.append('Đối chiếu chứng từ ký nhận của khách hàng/GDV trước khi duyệt.')
        else:
            risk_level = 'low'
            risk_score = 20
            recommendations.append('Giao dịch trong hạn mức định mức thường lệ của quầy.')
    else:
        if value >= 50:
            risk_level = 'high'
            risk_score = 85
            flagged_rules.append('Số lượng xuất/nhập ấn chỉ/phôi thẻ vượt hạn mức (≥ 50 đơn vị).')
            flagged_rules.append('Nguy cơ thất thoát phôi bảo mật (thẻ chip EMV, sổ séc trắng).')
            recommendations.append('Kiểm đếm dải số serial và niêm phong hộp phôi trước khi ký nhận.')
        elif value >= 20:
            risk_level = 'medium'
            risk_score = 52
            flagged_rules.append('Số lượng phôi xuất kho trung bình (20 - 50 đơn vị).')
            recommendations.append('Kiểm tra kế hoạch cấp phát ấn chỉ định kỳ của phòng giao dịch.')
        else:
            risk_level = 'low'
            risk_score = 18
            recommendations.append('Lệnh xuất nhập vật tư trong định mức ngày.')

    if not reason or len(reason) < 5:
        flagged_rules.append('Lý do giao dịch quá ngắn hoặc không nêu rõ mục đích (< 5 ký tự).')
        risk_score = min(98, risk_score + 15)
        if risk_level == 'low':
            risk_level = 'medium'
        recommendations.append('Yêu cầu Maker bổ sung diễn giải chi tiết mục đích nghiệp vụ.')

    raw_stamp = f'{request_id}:{maker}:{amount_str}:{risk_score}'
    audit_stamp = hashlib.sha256(raw_stamp.encode('utf-8')).hexdigest()

    summary = (
        f'Đánh giá rủi ro: Mức độ {risk_level.upper()} ({risk_score}/100) cho phiếu {request_id}. '
        f"{'Cần kiểm soát kép và nhập PIN KSV.' if risk_level == 'high' else 'Đủ điều kiện xem xét phê duyệt.'}"
    )

    return {
        'request_id': request_id,
        'risk_level': risk_level,
        'risk_score': risk_score,
        'summary': summary,
        'flagged_rules': flagged_rules,
        'recommendations': recommendations,
        'audit_stamp': audit_stamp,
    }


async def assess_request(data: dict, settings: Settings, client: httpx.AsyncClient) -> dict:
    heuristic = assess_request_heuristic(data)
    # Return structured heuristic with audit stamp
    return heuristic


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

