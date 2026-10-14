#!/usr/bin/env bash
# Upload GGUF fine-tune BankOps (~940 MB) lên Modal Volume cho app `bankops-llm`.
# Đây là bước thay thế cho `upload-model-to-hf.sh` (HF Space Docker hiện cần gói
# PRO nên không tạo được — xem infra/modal/README.md và docs/17-hf-llm-space.md).
#
# Cách dùng:
#   bash infra/scripts/upload-model-to-modal.sh <file.gguf | file.zip>
#
# Yêu cầu: modal CLI đã cài (`uv tool install modal`) và đã login (`modal setup`).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GGUF_NAME="Qwen2.5-1.5B-Instruct.Q4_K_M.gguf"
VOLUME_NAME="bankops-llm"

if [ $# -ne 1 ]; then
  echo "Cách dùng: $0 <file.gguf | file.zip>" >&2
  exit 1
fi

input="$1"
tmp_dir=""
cleanup() { if [ -n "$tmp_dir" ]; then rm -rf "$tmp_dir"; fi; }
trap cleanup EXIT

case "$input" in
  *.zip)
    if [ ! -f "$input" ]; then echo "Lỗi: không tìm thấy $input" >&2; exit 1; fi
    tmp_dir="$(mktemp -d)"
    echo "Giải nén $(basename "$input") ..."
    python3 -m zipfile -e "$input" "$tmp_dir"
    gguf="$tmp_dir/$GGUF_NAME"
    ;;
  *)
    gguf="$input"
    ;;
esac

if [ ! -f "$gguf" ]; then
  echo "Lỗi: không tìm thấy GGUF '$GGUF_NAME' (trong zip hoặc đường dẫn trực tiếp)." >&2
  exit 1
fi

echo "Upload $(basename "$gguf") ($(du -h "$gguf" | cut -f1 | tr -d ' ')) lên Modal Volume '$VOLUME_NAME'..."
modal run "$REPO_DIR/infra/modal/modal_app.py" --gguf "$gguf"
echo "Xong. Kiểm tra: modal volume ls $VOLUME_NAME"
