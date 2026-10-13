#!/bin/sh
set -eu

MODEL_FILE="${MODEL_FILE:?MODEL_FILE must be set}"
BANKOPS_MODEL_FILE="${BANKOPS_MODEL_FILE:-Qwen2.5-1.5B-Instruct.Q4_K_M.gguf}"
BAKED_DIR="/app/models/bankops"
IMAGE_MODEL="${BAKED_DIR}/${BANKOPS_MODEL_FILE}"
MODEL_PATH="${IMAGE_MODEL}"

# Ưu tiên 1: GGUF fine-tune BankOps được bake vào image lúc build (upload vào
# repo Space bằng infra/scripts/upload-model-to-hf.sh — docs/17 mục 2b).
# Ưu tiên 2: fallback — bản gốc tải từ HF Hub lúc build vào cùng thư mục.
if [ ! -s "${IMAGE_MODEL}" ] && [ -s "${BAKED_DIR}/${MODEL_FILE}" ]; then
  MODEL_PATH="${BAKED_DIR}/${MODEL_FILE}"
fi
if [ ! -s "${MODEL_PATH}" ]; then
  echo "[entrypoint] ERROR: no model GGUF found in ${BAKED_DIR}" >&2
  exit 1
fi

# /data là persistent volume (nếu Space cấu hình). Lần chạy đầu: copy model
# đang dùng sang volume để các lần restart sau đọc từ volume (nhanh, nhất quán).
# Copy qua file tạm rồi mv để không bao giờ để lại file dở dang nếu bị ngắt;
# toàn bộ khối này best-effort — /data không ghi được thì dùng bản trong image.
# So sánh kích thước: volume còn bản GGUF CŨ (đã đổi model rồi rebuild) thì
# copy đè bằng bản mới trong image, không phục vụ model stale.
if [ -d /data ]; then
  VOL_MODEL="/data/models/${BANKOPS_MODEL_FILE}"
  if [ ! -s "${VOL_MODEL}" ] \
     || [ "$(wc -c < "${VOL_MODEL}" 2>/dev/null || echo 0)" != "$(wc -c < "${MODEL_PATH}")" ]; then
    echo "[entrypoint] copying model into persistent volume..."
    if mkdir -p /data/models 2>/dev/null \
       && cp "${MODEL_PATH}" "/data/models/.upload.tmp" 2>/dev/null \
       && mv "/data/models/.upload.tmp" "${VOL_MODEL}"; then
      echo "[entrypoint] model copied to persistent volume"
    else
      echo "[entrypoint] WARNING: /data is not writable, using model from image"
      rm -f "/data/models/.upload.tmp" 2>/dev/null || true
    fi
  fi
  if [ -s "${VOL_MODEL}" ] \
     && [ "$(wc -c < "${VOL_MODEL}" 2>/dev/null || echo 0)" = "$(wc -c < "${MODEL_PATH}")" ]; then
    MODEL_PATH="${VOL_MODEL}"
  fi
fi

# Chat template đi kèm artifact fine-tune (model/chat_template.jinja trong
# image). Chỉ truyền flag khi file thật sự tồn tại để không chết lúc khởi động.
CHAT_TEMPLATE="${BAKED_DIR}/chat_template.jinja"

echo "[entrypoint] model: ${MODEL_PATH}"
echo "[entrypoint] starting llama-server on port ${PORT}..."

# Ghi chú flag theo llama.cpp (đã kiểm chứng ở bản b4740/v0.6.0):
# - --mlock KHÔNG còn — thay bằng --load-mode; ở đây dùng mặc định (auto/mmap)
#   vì mlock có thể hard-fail trong container giới hạn locked memory của HF.
# - --parallel 1 = đúng 1 slot. KHÔNG dùng --slots: flag này bật/tắt endpoint
#   giám sát slots, không phải số slot.
set -- \
  --host 0.0.0.0 \
  --port "${PORT}" \
  --model "${MODEL_PATH}" \
  --alias "${BANKOPS_MODEL_FILE%.gguf}" \
  --ctx-size 4096 \
  --threads 2 \
  --parallel 1 \
  --flash-attn off \
  --metrics
if [ -f "${CHAT_TEMPLATE}" ]; then
  set -- "$@" --chat-template "${CHAT_TEMPLATE}"
fi
exec /app/llama-server "$@"
