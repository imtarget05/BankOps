from app.services.ai_retrieval import grounded_prompt, retrieve
from app.api.routes.ai import ChatRequest, chat_stream
import pytest


def test_retrieval_cites_relevant_operational_document():
    sources = retrieve("maker checker duyệt phiếu trạng thái")
    assert sources
    assert any(source["source"] == "docs/05-workflows.md" for source in sources)
    prompt = grounded_prompt("Ai được duyệt?", sources)
    assert "[1]" in prompt
    assert "docs/" in prompt


def test_retrieval_abstains_without_matching_evidence():
    assert retrieve("xyzzy quux blorb") == []


@pytest.mark.asyncio
async def test_chat_stream_returns_sse_without_inventing_an_answer():
    user = type('UserStub', (), {'id': 'retrieval-test-user', 'status': 'active'})()
    response = await chat_stream(ChatRequest(message='xyzzy quux blorb'), user)
    frames = [frame async for frame in response.body_iterator]
    assert response.media_type == 'text/event-stream'
    assert 'event: sources' in frames[0]
    assert 'Chưa tìm thấy thông tin' in ''.join(frames)
    assert 'event: done' in frames[-1]
