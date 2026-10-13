"""Standalone CPU Inference Server for BankOps AI.

Runs on machines without GPU (Intel / Apple Silicon / AMD CPU).
Supports both GGUF (via llama-cpp-python) and lightweight rule-based banking assistant fallback.
Exposes standard OpenAI and Ollama compatible endpoints.
"""
import os
from pathlib import Path
from typing import Any

from fastapi import FastAPI
from pydantic import BaseModel

SYSTEM_PROMPT = """Bạn là trợ lý BankOps, trả lời bằng tiếng Việt, ngắn gọn và có bước thực hiện theo đúng chuẩn mực nghiệp vụ ngân hàng.
Quy trình: Maker tạo nháp -> gửi duyệt -> Checker khác người tạo duyệt hoặc từ chối.
Chỉ phiếu đã duyệt mới thay đổi tồn kho/số dư. Kho và cash_sim tách biệt.
Đối soát kiểm tra sổ cái bút toán kép và số dư. Audit có hash-chain.
Bạn không có quyền thực hiện thao tác, duyệt phiếu, sửa số dư hay chuyển tiền."""

KNOWLEDGE_BASE = {
    "maker": "Quy trình Maker - Checker: Maker lập phiếu ở trạng thái Nháp (Draft) -> bấm Gửi duyệt (Pending). Phiếu chuyển sang Hộp thư của Kiểm soát viên (Checker). Checker kiểm tra và Phê duyệt (Posted) hoặc Từ chối (Rejected). Số dư chỉ thay đổi khi phiếu đã được duyệt.",
    "duyệt": "Nguyên tắc Bốn mắt (Four-Eyes Principle): Người tạo phiếu (Maker) tuyệt đối không được tự duyệt phiếu của mình. Chỉ tài khoản Checker/Kiểm soát viên mới có quyền phê duyệt.",
    "két": "Hệ thống quản lý các két sắt: Két Đại quỹ Hội sở (CB-MAIN-01), Két quầy giao dịch viên (CB-TELLER-01/02), Két ATM (CB-ATM-01). Mỗi két có hạn mức tồn quỹ riêng và được kiểm soát số dư chặt chẽ.",
    "đối soát": "Đối soát cuối ngày (End-of-day Reconciliation) kiểm tra: 1. Cân đối sổ cái bút toán kép (Nợ = Có); 2. Khớp số dư thực tế tại két với số dư hệ thống; 3. Khớp giao dịch trung gian qua cổng thanh toán.",
    "import": "Quy trình Import dữ liệu: Tải file lên Staging -> Kiểm tra lỗi tại màn hình Preview -> Chỉ Xác nhận (Confirm) khi không có lỗi nghiêm trọng. Tuyệt đối không bỏ qua bước validation.",
    "vật tư": "Vật tư quan trọng (Phôi thẻ Visa Debit EMV Chip, Sổ séc bảo chi, Sổ tiết kiệm QR) được quản lý theo số Serial định danh từng chiếc (Tracked by Serial) và kiểm kê định kỳ.",
    "audit": "Nhật ký kiểm toán (Audit Trail) sử dụng cấu trúc Hash-Chain mã hóa SHA-256 liên kết bản ghi trước và sau, đảm bảo tính toàn vẹn và chống chỉnh sửa dữ liệu.",
}

app = FastAPI(title="BankOps Small LLM CPU Server", version="1.0.0")

# Check if llama-cpp-python is installed and GGUF file exists
llm = None
model_path = os.environ.get("BANKOPS_GGUF_PATH", "qwen2.5-1.5b-q4_k_m.gguf")

if Path(model_path).exists():
    try:
        from llama_cpp import Llama
        print(f"Loading GGUF model on CPU: {model_path} (n_gpu_layers=0)")
        llm = Llama(
            model_path=model_path,
            n_ctx=2048,
            n_threads=int(os.environ.get("CPU_THREADS", "4")),
            n_gpu_layers=0,  # Strict CPU execution
            verbose=False,
        )
        print("Model loaded successfully on CPU!")
    except ImportError:
        print("llama-cpp-python not installed. Running in rule-grounded fallback mode.")
else:
    print(f"GGUF model not found at {model_path}. Running in rule-grounded fallback mode.")


class ChatMessage(BaseModel):
    role: str
    content: str


class ChatRequest(BaseModel):
    model: str = "bankops-qwen2.5:1.5b"
    messages: list[ChatMessage]
    temperature: float = 0.2
    stream: bool = False


def answer_query(user_message: str) -> str:
    if llm is not None:
        prompt = f"<|im_start|>system\n{SYSTEM_PROMPT}<|im_end|>\n<|im_start|>user\n{user_message}<|im_end|>\n<|im_start|>assistant\n"
        output = llm(prompt, max_tokens=512, stop=["<|im_end|>"], temperature=0.2)
        return output["choices"][0]["text"].strip()
    
    # Grounded fallback
    lowered = user_message.lower()
    for key, text in KNOWLEDGE_BASE.items():
        if key in lowered:
            return f"{text}\n\n(Lưu ý: Mọi giao dịch tài chính phải tuân thủ nghiêm ngặt quy định kiểm soát nội bộ)."
    return (
        "Chào bạn, tôi là Trợ lý Nghiệp vụ BankOps. Tôi có thể hỗ trợ bạn giải đáp về:\n"
        "- Quy trình Maker - Checker và luồng phê duyệt chứng từ\n"
        "- Nghiệp vụ quản lý hạn mức tồn quỹ và két sắt\n"
        "- Quản lý kho ấn chỉ, phôi thẻ chip EMV và sổ séc theo serial\n"
        "- Quy trình đối soát cuối ngày và xử lý lỗi import staging.\n"
        "Vui lòng đặt câu hỏi cụ thể để tôi hướng dẫn chi tiết."
    )


@app.post("/api/chat")
async def ollama_chat(req: ChatRequest) -> dict[str, Any]:
    """Ollama compatible chat endpoint."""
    user_msg = next((m.content for m in reversed(req.messages) if m.role == "user"), "")
    reply = answer_query(user_msg)
    return {
        "model": req.model,
        "message": {"role": "assistant", "content": reply},
        "done": True,
    }


@app.post("/v1/chat/completions")
async def openai_chat(req: ChatRequest) -> dict[str, Any]:
    """OpenAI compatible chat completions endpoint."""
    user_msg = next((m.content for m in reversed(req.messages) if m.role == "user"), "")
    reply = answer_query(user_msg)
    return {
        "id": "chatcmpl-cpu-001",
        "object": "chat.completion",
        "model": req.model,
        "choices": [
            {
                "index": 0,
                "message": {"role": "assistant", "content": reply},
                "finish_reason": "stop",
            }
        ],
    }


@app.get("/health")
def health():
    return {"status": "ok", "mode": "cpu", "model_loaded": llm is not None}


if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", "11434"))
    print(f"Starting BankOps Small LLM Server on port {port} (CPU mode)...")
    uvicorn.run(app, host="0.0.0.0", port=port)
