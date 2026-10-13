#!/bin/sh
set -eu

MODEL_FILE="${MODEL_FILE:?MODEL_FILE must be set}"
IMAGE_MODEL="/app/models/${MODEL_FILE}"
MODEL_PATH="${IMAGE_MODEL}"

# /data là persistent volume (nếu Space cấu hình). Lần chạy đầu: copy model
# từ image sang volume để các lần restart sau đọc từ volume (nhanh, nhất quán).
# Copy qua file tạm rồi mv để không bao giờ để lại file dở dang nếu bị ngắt;
# toàn bộ khối này best-effort — /data không ghi được thì dùng bản trong image.
if [ -d /data ]; then
  VOL_MODEL="/data/models/${MODEL_FILE}"
  if [ ! -f "${VOL_MODEL}" ]; then
    echo "[entrypoint] copying model into persistent volume..."
    if mkdir -p /data/models 2>/dev/null \
       && cp "${IMAGE_MODEL}" "/data/models/.upload.tmp" 2>/dev/null \
       && mv "/data/models/.upload.tmp" "${VOL_MODEL}"; then
      echo "[entrypoint] model copied to persistent volume"
    else
      echo "[entrypoint] WARNING: /data is not writable, using model from image"
      rm -f "/data/models/.upload.tmp" 2>/dev/null || true
    fi
  fi
  if [ -f "${VOL_MODEL}" ]; then
    MODEL_PATH="${VOL_MODEL}"
  fi
fi

echo "[entrypoint] model: ${MODEL_PATH}"
echo "[entrypoint] starting llama-server on port ${PORT}..."

# Ghi chú flag theo llama.cpp (đã kiểm chứng ở bản b4740/v0.6.0):
# - --mlock KHÔNG còn — thay bằng --load-mode; ở đây dùng mặc định (auto/mmap)
#   vì mlock có thể hard-fail trong container giới hạn locked memory của HF.
# - --parallel 1 = đúng 1 slot. KHÔNG dùng --slots: flag này bật/tắt endpoint
#   giám sát slots, không phải số slot.
exec /app/llama-server \
  --host 0.0.0.0 \
  --port "${PORT}" \
  --model "${MODEL_PATH}" \
  --alias "${MODEL_FILE%.gguf}" \
  --ctx-size 4096 \
  --threads 2 \
  --parallel 1 \
  --flash-attn off \
  --metrics