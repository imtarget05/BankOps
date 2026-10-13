# syntax=docker/dockerfile:1
# BankOps LLM backend — llama.cpp server chạy trên Hugging Face Space (CPU free 2 vCPU / 16GB).
# Model GGUF fine-tune BankOps (Qwen2.5-1.5B-Instruct, Q4_K_M, ~940 MB) được nhúng
# vào image theo thứ tự ưu tiên:
#   1. GGUF fine-tune trong thư mục `model/` của repo Space (upload bằng
#      infra/scripts/upload-model-to-hf.sh — xem docs/17-hf-llm-space.md mục 2b).
#   2. Fallback: bản gốc công khai `Qwen/Qwen2.5-1.5B-Instruct-GGUF` tải từ HF Hub
#      lúc build (chỉ chạy khi `model/` chưa có GGUF fine-tune).

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
    BANKOPS_MODEL_FILE=Qwen2.5-1.5B-Instruct.Q4_K_M.gguf \
    PORT=7860

# Nhúng toàn bộ thư mục model/ của repo Space vào image: tokenizer/config/
# chat-template của bản fine-tune (file nhỏ, luôn có) + GGUF fine-tune khi đã
# được upload bằng script (940 MB — vượt giới hạn 100 MB/file của GitHub nên
# KHÔNG nằm trong repo BankOps, xem docs/17 mục 2b).
COPY model/ /app/models/bankops/

# Fallback: chưa có GGUF fine-tune trong model/ thì tải bản gốc công khai từ
# HF Hub (~1.12 GB, cache trong image — Space restart không tải lại; không cần
# token). -L: URL "resolve" của HF redirect sang CDN, bắt buộc phải follow.
RUN if [ ! -s "/app/models/bankops/${BANKOPS_MODEL_FILE}" ]; then \
      echo "[build] fine-tuned GGUF not found, downloading base model from HF Hub..." \
      && curl -fL --retry 3 --retry-delay 5 \
           "https://huggingface.co/${MODEL_REPO}/resolve/main/${MODEL_FILE}" \
           -o "/app/models/bankops/${MODEL_FILE}"; \
    fi

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Space chạy container bằng user ngẫu nhiên (uid 1000); /data là volume do HF mount.
EXPOSE 7860
ENTRYPOINT ["/entrypoint.sh"]
