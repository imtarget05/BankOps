"""OpenAI-compatible LLM server cho bản fine-tune BankOps (GGUF Q4_K_M).

Chạy `llama-cpp-python` (uvicorn) trên Modal với GGUF fine-tune
Qwen2.5-1.5B-Instruct (Q4_K_M, ~940 MB) lưu trên Modal Volume. API tương thích
OpenAI (`/v1/chat/completions`) nên Cloudflare Worker gọi được y như llama.cpp
server trên HF Space (docs/17) — chỉ khác giá trị `HF_LLM_BASE_URL`.

File này KHÔNG import `modal` — nó được chạy như một subprocess uvicorn bên
trong container (xem modal_app.py), nên có thể kiểm tra tĩnh bằng `ast.parse`
mà không cần cài Modal.
"""

from __future__ import annotations

import os
import threading
from pathlib import Path

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

# ─── Cấu hình qua biến môi trường (đặt trong modal_app.py) ───────────────────
GGUF_DIR = Path(os.environ.get("BANKOPS_GGUF_DIR", "/data/bankops-llm"))
GGUF_NAME = os.environ.get("BANKOPS_GGUF_NAME", "Qwen2.5-1.5B-Instruct.Q4_K_M.gguf")
N_CTX = int(os.environ.get("BANKOPS_N_CTX", "4096"))
N_THREADS = int(os.environ.get("BANKOPS_N_THREADS", "2"))
# None → llama-cpp-python tự đọc chat template từ metadata GGUF
# (`tokenizer.chat_template` của bản fine-tune) — cùng hành vi với
# llama.cpp server trên HF Space. Chỉ đặt khi cần ép format khác.
CHAT_FORMAT = os.environ.get("BANKOPS_CHAT_FORMAT") or None

MODEL_ALIAS = GGUF_NAME.removesuffix(".gguf")

app = FastAPI(
    title="BankOps Small LLM Server (Modal)",
    version="1.0.0",
    description="OpenAI-compatible API cho GGUF fine-tune BankOps chạy trên Modal.",
)

_llm = None
_llm_lock = threading.Lock()


def _load_llm():
    """Load GGUF đúng 1 lần trong process (lazy để /health không phải chờ model)."""
    global _llm
    with _llm_lock:
        if _llm is None:
            from llama_cpp import Llama  # import nặng — chỉ khi cần sinh text

            model_path = GGUF_DIR / GGUF_NAME
            if not model_path.is_file():
                raise HTTPException(
                    status_code=503,
                    detail=(
                        f"Model GGUF chưa có trên volume: {model_path}. "
                        "Chạy bash infra/scripts/upload-model-to-modal.sh trước."
                    ),
                )
            _llm = Llama(
                model_path=str(model_path),
                n_ctx=N_CTX,
                n_threads=N_THREADS,
                n_batch=512,
                n_gpu_layers=0,  # container CPU — không có GPU
                chat_format=CHAT_FORMAT,
                verbose=False,
            )
    return _llm


class ChatMessage(BaseModel):
    role: str
    content: str


class ChatCompletionRequest(BaseModel):
    model: str | None = None
    messages: list[ChatMessage] = Field(min_length=1)
    max_tokens: int = Field(default=512, ge=1, le=2048)
    temperature: float = Field(default=0.2, ge=0, le=2)
    top_p: float = Field(default=1.0, ge=0, le=1)
    stream: bool = False


@app.get("/")
def root() -> dict:
    model_path = GGUF_DIR / GGUF_NAME
    return {
        "service": "BankOps Small LLM Server (Modal)",
        "status": "online",
        "model_file": GGUF_NAME,
        "model_present": model_path.is_file(),
        "model_loaded": _llm is not None,
        "health": "/health",
        "docs": "/docs",
        "chat_completions": "/v1/chat/completions",
    }


@app.get("/health")
def health() -> dict:
    model_path = GGUF_DIR / GGUF_NAME
    return {
        "status": "ok",
        "mode": "modal-cpu",
        "model_file": GGUF_NAME,
        "model_present": model_path.is_file(),
        "model_loaded": _llm is not None,
    }


@app.post("/v1/chat/completions")
def chat_completions(req: ChatCompletionRequest) -> dict:
    if req.stream:
        raise HTTPException(status_code=400, detail="stream=true chưa được hỗ trợ")
    llm = _load_llm()
    try:
        out = llm.create_chat_completion(
            messages=[m.model_dump() for m in req.messages],
            max_tokens=req.max_tokens,
            temperature=req.temperature,
            top_p=req.top_p,
            stream=False,
        )
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"LLM inference lỗi: {exc}") from exc
    choice = (out.get("choices") or [{}])[0]
    content = (choice.get("message") or {}).get("content")
    if not isinstance(content, str) or not content.strip():
        raise HTTPException(status_code=502, detail="LLM trả về nội dung rỗng")
    return {
        "id": out.get("id") or "chatcmpl-bankops-modal",
        "object": "chat.completion",
        "created": out.get("created") or 0,
        "model": req.model or MODEL_ALIAS,
        "choices": [
            {
                "index": 0,
                "message": {"role": "assistant", "content": content.strip()},
                "finish_reason": choice.get("finish_reason") or "stop",
            }
        ],
        "usage": out.get("usage"),
    }
