# syntax=docker/dockerfile:1
# BankOps LLM backend — llama.cpp server chạy trên Hugging Face Space (CPU free 2 vCPU / 16GB).
# Model GGUF tải lúc build từ HF Hub (công khai, không cần token).
# Chi tiết: docs/17-hf-llm-space.md trong repo BankOps.

# Pin theo digest (tag `server-b4740` của llama.cpp) để build tái lập được —
# tag trôi (mỗi lần CI của llama.cpp chạy xong lại đẩy tag mới) sẽ làm image
# đổi dưới chân. Ảnh này là Ubuntu 24.04, đã có sẵn curl; binary nằm ở
# /app/llama-server (ENTRYPOINT gốc của image — ta ghi đè bằng entrypoint.sh).
FROM ghcr.io/ggml-org/llama.cpp:server-b4740@sha256:6a9cb57e7f1c892ccf5aeac61d6641bdc3a628b809dd127bcea8dfde69a131ba

# app_port của Space là 7860 — llama-server phải lắng nghe trên cổng này.
# Model cài vào /app/models trong image (KHÔNG tải thẳng vào /data lúc build:
# /data là persistent volume do HF mount lúc runtime, sẽ che nội dung đã có).
ENV MODEL_REPO=Qwen/Qwen2.5-1.5B-Instruct-GGUF \
    MODEL_FILE=qwen2.5-1.5b-instruct-q4_k_m.gguf \
    PORT=7860

# Tải model lúc build: 1.12 GB, được cache trong image — Space restart không tải lại.
# -L: URL "resolve" của HF redirect sang CDN, bắt buộc phải follow; không cần token.
RUN curl -fL --retry 3 --retry-delay 5 \
      "https://huggingface.co/${MODEL_REPO}/resolve/main/${MODEL_FILE}" \
      -o /tmp/model.gguf \
 && mkdir -p /app/models \
 && mv /tmp/model.gguf "/app/models/${MODEL_FILE}"

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Space chạy container bằng user ngẫu nhiên (uid 1000); /data là volume do HF mount.
EXPOSE 7860
ENTRYPOINT ["/entrypoint.sh"]