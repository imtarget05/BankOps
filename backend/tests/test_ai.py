"""AI provider contract: no database or paid inference required."""
import httpx
import pytest
from fastapi import HTTPException

from app.config import Settings
from app.services.ai import generate


def config(**kwargs):
    return Settings(database_url='sqlite://', ai_provider='cloudflare',
                    cloudflare_account_id='a' * 32, cloudflare_api_token='test-secret', **kwargs)


@pytest.mark.asyncio
async def test_cloudflare_contract():
    def respond(request):
        assert request.url.host == 'api.cloudflare.com'
        assert request.headers['authorization'] == 'Bearer test-secret'
        import json
        body = json.loads(request.content)
        assert body['messages'][0]['role'] == 'system'
        assert body['messages'][-1]['content'] == 'Maker là gì?'
        assert 'tools' not in body
        return httpx.Response(200, json={'success': True, 'result': {'response': 'Người tạo phiếu.'}})
    async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
        result = await generate('Maker là gì?', config(), client)
    assert result['answer'] == 'Người tạo phiếu.'
    assert result['provider'] == 'cloudflare'
    assert result['simulation'] is True


@pytest.mark.asyncio
@pytest.mark.parametrize('status,payload', [(401, {'error':'secret'}), (429, {}),
    (200, {'success': False}), (200, {'success': True, 'result': {}}),
    (200, {'success': True, 'result': {'response': ''}})])
async def test_provider_errors_are_sanitized(status, payload):
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(status, json=payload))) as client:
        with pytest.raises(HTTPException) as error:
            await generate('test', config(), client)
    assert error.value.status_code == 503
    assert 'secret' not in error.value.detail


@pytest.mark.asyncio
async def test_local_cpu_contract():
    def respond(request):
        import json
        body = json.loads(request.content)
        assert request.url.path == '/api/chat'
        assert body['model'] == 'qwen2.5:1.5b'
        assert body['options']['num_gpu'] == 0
        assert 'authorization' not in request.headers
        return httpx.Response(200, json={'message': {'content': 'Local answer'}})
    settings = Settings(database_url='sqlite://', ai_provider='ollama')
    async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
        assert (await generate('test', settings, client))['provider'] == 'ollama'


@pytest.mark.asyncio
async def test_timeout():
    def respond(request):
        raise httpx.ReadTimeout('upstream secret', request=request)
    async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
        with pytest.raises(HTTPException) as error:
            await generate('test', config(), client)
    assert error.value.status_code == 503


@pytest.mark.asyncio
async def test_disabled_does_not_call_provider():
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda r: pytest.fail('unexpected network'))) as client:
        with pytest.raises(HTTPException) as error:
            await generate('test', Settings(database_url='sqlite://', ai_provider='disabled'), client)
    assert error.value.status_code == 503


@pytest.mark.asyncio
async def test_assess_request_high_cash():
    from app.services.ai import assess_request
    data = {
        'request_id': 'cr-9999',
        'kind': 'cash',
        'amount_or_qty': '600.000.000',
        'maker': 'GDV Nguyen Van A',
        'reason': 'Chi tiền mặt tiếp quỹ ATM khẩn cấp',
    }
    async with httpx.AsyncClient() as client:
        result = await assess_request(data, config(), client)
    assert result['risk_level'] == 'high'
    assert result['risk_score'] >= 80
    assert len(result['flagged_rules']) >= 2
    assert len(result['audit_stamp']) == 64  # SHA-256 hex length
    assert 'cr-9999' in result['summary']


@pytest.mark.asyncio
async def test_assess_request_low_cash_and_inventory():
    from app.services.ai import assess_request
    data = {
        'request_id': 'cr-1000',
        'kind': 'cash',
        'amount_or_qty': '35.000.000',
        'maker': 'GDV Nguyen Van B',
        'reason': 'Nạp tiền mặt đầu ngày',
    }
    async with httpx.AsyncClient() as client:
        result = await assess_request(data, config(), client)
    assert result['risk_level'] == 'low'
    assert result['risk_score'] < 50

    inv_high = {
        'request_id': 'sr-5000',
        'kind': 'inventory',
        'amount_or_qty': '100',
        'maker': 'Thu kho',
        'reason': 'Xuất phôi thẻ Visa Debit',
    }
    async with httpx.AsyncClient() as client:
        result_inv = await assess_request(inv_high, config(), client)
    assert result_inv['risk_level'] == 'high'
    assert result_inv['risk_score'] >= 80


@pytest.mark.asyncio
async def test_assess_request_short_reason_penalty():
    from app.services.ai import assess_request
    data = {
        'request_id': 'cr-2000',
        'kind': 'cash',
        'amount_or_qty': '50.000.000',
        'maker': 'GDV Nguyen Van C',
        'reason': '',  # empty reason
    }
    async with httpx.AsyncClient() as client:
        result = await assess_request(data, config(), client)
    assert any('quá ngắn' in rule for rule in result['flagged_rules'])
    assert result['risk_score'] > 20

