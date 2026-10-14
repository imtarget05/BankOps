"""Modal App: GGUF fine-tune BankOps chạy 24/7 như serverless.

Thay thế HF Space (bị chặn bởi chính sách mới: Docker Space cần gói PRO) —
giữ nguyên API OpenAI-compatible nên Worker chỉ cần đổi `HF_LLM_BASE_URL`.
Container CPU 2 vCPU / 2 GiB, tự ngủ sau 15 phút không traffic và dậy lại
trong ~1 phút khi có request (scale-to-zero — nằm trong $30 credit/tháng
miễn phí của gói Starter).

Lệnh chính (chi tiết trong README.md cùng thư mục):
    modal deploy infra/modal/modal_app.py                    # deploy URL tĩnh
    modal run infra/modal/modal_app.py --gguf <file.gguf>    # upload model
"""

from __future__ import annotations

import os
import subprocess

import modal

# ─── Hằng số cấu hình (khớp entrypoint.sh của HF Space) ──────────────────────
GGUF_NAME = "Qwen2.5-1.5B-Instruct.Q4_K_M.gguf"
VOLUME_NAME = "bankops-llm"
VOLUME_DIR = "/data/bankops-llm"
PORT = 8000

WEB_TIMEOUT_SECONDS = 15 * 60  # thời lượng request tối đa (cold start + inference)
SCALE_DOWN_SECONDS = 15 * 60  # ngủ sau 15 phút không traffic (tiết kiệm credit)

CPU_CORES = 2
# 3 GiB: model ~1.1 GB + KV cache (ctx 4096) + logits buffer (~300 MB — vocab
# 151k của Qwen) + Python runtime. Đủ dư để không OOM khi prompt dài.
MEMORY_MIB = 3072

# Wheel CPU prebuilt của llama-cpp-python (PyPI chỉ có sdist → phải compile).
# Wheel `py3-none-manylinux` không phụ thuộc version Python.
image = (
    modal.Image.debian_slim(python_version="3.12")
    .pip_install(
        "fastapi==0.143.0",
        "uvicorn==0.54.0",
        "pydantic==2.14.1",
        "llama-cpp-python==0.3.36",
        extra_index_url="https://abetlen.github.io/llama-cpp-python/whl/cpu/",
    )
    .add_local_python_source("bankops_llm_server")
)

app = modal.App("bankops-llm", image=image)
volume = modal.Volume.from_name(VOLUME_NAME, create_if_missing=True)


@app.function(
    cpu=CPU_CORES,
    memory=MEMORY_MIB,
    timeout=WEB_TIMEOUT_SECONDS,
    scaledown_window=SCALE_DOWN_SECONDS,
    volumes={VOLUME_DIR: volume},
)
@modal.concurrent(max_inputs=4)  # dồn request về 1 container ấm, không nhân bản
@modal.web_server(PORT, startup_timeout=120)
def serve():
    # Model KHÔNG nằm trong image — được đọc từ volume lúc runtime, nên image
    # nhỏ, cold start nhanh, và đổi model không phải build lại image.
    subprocess.Popen(
        [
            "python",
            "-m",
            "uvicorn",
            "bankops_llm_server:app",
            "--host",
            "0.0.0.0",
            "--port",
            str(PORT),
        ]
    )


@app.local_entrypoint()
def main(gguf: str) -> None:
    """Upload GGUF vào volume: modal run modal_app.py --gguf /path/model.gguf

    Upload chạy CLIENT-SIDE (batch_upload đọc file trên máy local và đẩy thẳng
    lên volume) — file local không tồn tại bên trong container remote.
    """
    if not os.path.isfile(gguf):
        raise SystemExit(f"Không tìm thấy file GGUF: {gguf}")
    # batch_upload dùng đường dẫn THEO ROOT CỦA VOLUME (không phải mount point):
    # volume mount tại VOLUME_DIR nên file ở root sẽ hiện là VOLUME_DIR/<file>.
    dest = GGUF_NAME
    size_mb = os.path.getsize(gguf) / (1024 * 1024)
    print(f"upload {gguf} ({size_mb:.0f} MB) -> volume:{dest} (mount {VOLUME_DIR})")
    with volume.batch_upload(force=True) as batch:
        batch.put_file(gguf, dest)
    print("done")
