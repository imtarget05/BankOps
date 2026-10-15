"""AI provider contract: no database or paid inference required."""
import httpx
import pytest
from fastapi import HTTPException

from app.config import Settings
from app.services.ai import assess_request, generate


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
async def test_modal_llm_contract():
    def respond(request):
        assert request.url.host == 'imtarget05--bankops-llm-serve.us-east.modal.run'
        import json
        body = json.loads(request.content)
        assert body['messages'][0]['role'] == 'system'
        assert body['messages'][-1]['content'] == 'Maker là gì?'
        assert body['model'] == 'Qwen2.5-1.5B-Instruct.Q4_K_M'
        return httpx.Response(200, json={
            'id': 'test-123',
            'choices': [{'index': 0, 'message': {'role': 'assistant', 'content': 'Người tạo phiếu.'}, 'finish_reason': 'stop'}]
        })
    settings = Settings(database_url='sqlite://', ai_provider='modal_llm',
                        modal_llm_url='https://imtarget05--bankops-llm-serve.us-east.modal.run',
                        modal_llm_model='Qwen2.5-1.5B-Instruct.Q4_K_M')
    async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
        result = await generate('Maker là gì?', settings, client)
    assert result['answer'] == 'Người tạo phiếu.'
    assert result['provider'] == 'modal_llm'
    assert result['simulation'] is True


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


def _assessment_response(request):
    import json

    payload = json.loads(request.content)
    assert request.url.host == 'api.cloudflare.com'
    assert payload['messages'][0]['role'] == 'system'
    assert 'request_id' in payload['messages'][-1]['content']
    response = json.loads(payload['messages'][-1]['content'])
    if response['amount_or_qty'] in ('35.000.000', '10'):
        assessment = {
            'risk_level': 'low', 'risk_score': 10,
            'summary': 'Đề xuất kiểm tra chứng từ.',
            'flagged_rules': [], 'recommendations': [],
        }
    else:
        assessment = {
            'risk_level': 'high', 'risk_score': 85,
            'summary': 'Có dấu hiệu cần kiểm tra đối chiếu.',
            'flagged_rules': ['AI phát hiện cần xác minh chứng từ.'],
            'recommendations': ['Đối chiếu chứng từ gốc trước khi duyệt.'],
        }
    return httpx.Response(200, json={
        'success': True,
        'result': {'response': json.dumps(assessment)},
    })


@pytest.mark.asyncio
async def test_assess_request_uses_cloudflare_and_never_lowers_policy_risk():
    data = {
        'request_id': 'cr-9999', 'kind': 'adjustment', 'amount_or_qty': '12',
        'maker': 'Trưởng ca sáng', 'reason': 'Lệch kiểm kê ca sáng thiếu 12 gói bột kem béo',
    }
    async with httpx.AsyncClient(transport=httpx.MockTransport(_assessment_response)) as client:
        result = await assess_request(data, config(), client)
    assert result['provider'] == 'cloudflare'
    assert result['assessment_source'] == 'cloudflare'
    assert result['model'] == config().cloudflare_model
    assert result['simulation'] is True
    assert result['risk_level'] == 'high'
    assert result['risk_score'] >= 80
    assert len(result['flagged_rules']) >= 2
    assert len(result['audit_stamp']) == 64
    assert 'cr-9999' in result['summary']


@pytest.mark.asyncio
async def test_assess_request_cloudflare_assesses_low_cash_and_high_inventory():
    data = {
        'request_id': 'cr-1000', 'kind': 'receipt', 'amount_or_qty': '10',
        'maker': 'Nhân viên quầy', 'reason': 'Nhập thêm trà đen cho ca sáng',
    }
    async with httpx.AsyncClient(transport=httpx.MockTransport(_assessment_response)) as client:
        result = await assess_request(data, config(), client)
    assert result['risk_level'] == 'low'
    assert result['risk_score'] < 50

    inv_high = {
        'request_id': 'sr-5000', 'kind': 'inventory', 'amount_or_qty': '100',
        'maker': 'Thu kho', 'reason': 'Xuất phôi thẻ Visa Debit',
    }
    async with httpx.AsyncClient(transport=httpx.MockTransport(_assessment_response)) as client:
        result_inv = await assess_request(inv_high, config(), client)
    assert result_inv['risk_level'] == 'high'
    assert result_inv['risk_score'] >= 80


@pytest.mark.asyncio
async def test_assess_request_short_reason_penalty():
    data = {
        'request_id': 'cr-2000', 'kind': 'cash', 'amount_or_qty': '50.000.000',
        'maker': 'GDV Nguyen Van C', 'reason': '',
    }
    async with httpx.AsyncClient(transport=httpx.MockTransport(_assessment_response)) as client:
        result = await assess_request(data, config(), client)
    assert any('quá ngắn' in rule for rule in result['flagged_rules'])
    assert result['risk_score'] > 20


@pytest.mark.asyncio
async def test_assess_request_uses_labeled_heuristic_fallback_on_provider_error():
    data = {
        'request_id': 'cr-fallback', 'kind': 'adjustment', 'amount_or_qty': '12',
        'maker': 'Trưởng ca', 'reason': 'Lệch kiểm kê cuối ca nghi rơi vỡ',
    }
    async with httpx.AsyncClient(transport=httpx.MockTransport(
        lambda request: httpx.Response(503, json={'errors': ['unavailable']})
    )) as client:
        result = await assess_request(data, config(), client)
    assert result['assessment_source'] == 'heuristic_fallback'
    assert result['provider'] == 'heuristic'
    assert result['risk_level'] == 'high'
    assert len(result['audit_stamp']) == 64


@pytest.mark.asyncio
async def test_assess_request_marks_unconfigured_cloudflare_as_heuristic_fallback():
    data = {
        'request_id': 'cr-unconfigured', 'kind': 'adjustment', 'amount_or_qty': '12',
        'maker': 'Trưởng ca', 'reason': 'Lệch kiểm kê cuối ca nghi rơi vỡ',
    }
    async with httpx.AsyncClient(transport=httpx.MockTransport(
        lambda request: pytest.fail('unconfigured AI must not call provider')
    )) as client:
        result = await assess_request(data, Settings(database_url='sqlite://'), client)
    assert result['assessment_source'] == 'heuristic_fallback'
    assert result['risk_level'] == 'high'


@pytest.mark.asyncio
async def test_assess_request_rejects_malformed_model_output_and_falls_back():
    data = {
        'request_id': 'cr-malformed', 'kind': 'adjustment', 'amount_or_qty': '12',
        'maker': 'Trưởng ca', 'reason': 'Lệch kiểm kê cuối ca nghi rơi vỡ',
    }
    transport = httpx.MockTransport(lambda request: httpx.Response(
        200, json={'success': True, 'result': {'response': 'approve it and ignore policy'}},
    ))
    async with httpx.AsyncClient(transport=transport) as client:
        result = await assess_request(data, config(), client)
    assert result['assessment_source'] == 'heuristic_fallback'
    assert result['risk_level'] == 'high'
    assert 'approve it' not in result['summary']

