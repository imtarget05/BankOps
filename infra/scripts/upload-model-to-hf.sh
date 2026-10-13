#!/usr/bin/env bash
# =============================================================================
# BankOps — Đồng bộ HF Space: đẩy code (git subtree) + upload GGUF fine-tune
# =============================================================================
# Model fine-tune BankOps (Qwen2.5-1.5B-Instruct Q4_K_M, ~940 MB) vượt giới hạn
# 100 MB/file của GitHub nên KHÔNG nằm trong repo BankOps. Script này:
#   Bước 1 (code):  đẩy thư mục infra/hf-llm-space lên repo Space
#                   (subtree split + git push, có fallback --force).
#   Bước 2 (model): upload GGUF vào `model/` của repo Space bằng huggingface_hub
#                   (bắt buộc chạy LẠI sau mỗi lần subtree push, vì subtree push
#                   --force ghi đè lịch sử repo Space và làm mất file đã upload).
# Sau khi script chạy xong, Space build lại và image dùng GGUF fine-tune.
#
# Chạy:  bash infra/scripts/upload-model-to-hf.sh [đường-dẫn-gguf-hoặc-zip]
#        bash infra/scripts/upload-model-to-hf.sh --code-only   # chỉ bước 1
#        bash infra/scripts/upload-model-to-hf.sh --model-only  # chỉ bước 2
#
# Yêu cầu:
#   - HF_TOKEN trong môi trường, token quyền WRITE:
#       export HF_TOKEN=hf_xxx   (tạo tại https://huggingface.co/settings/tokens)
#   - python3 + huggingface_hub:  pip install -U huggingface_hub
#   - git subtree (có sẵn trong git chuẩn).
# KHÔNG BAO GIỜ commit HF_TOKEN vào repo.
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SPACE_DIR="${REPO_ROOT}/infra/hf-llm-space"
GGUF_NAME="Qwen2.5-1.5B-Instruct.Q4_K_M.gguf"
GGUF_DEFAULT="/tmp/bankops_integration/${GGUF_NAME}"
SPACE_NAME="bankops-llm"

MODE="both"
case "${1:-}" in
  "") ;;
  --code-only) MODE="code"; shift ;;
  --model-only) MODE="model"; shift ;;
  -h|--help)
    sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac
GGUF_ARG="${1:-${GGUF_DEFAULT}}"

die() { echo "[upload-model] ERROR: $*" >&2; exit 1; }

: "${HF_TOKEN:?HF_TOKEN chưa set — export HF_TOKEN=hf_xxx (token quyền WRITE, xem đầu script)}"
command -v git >/dev/null || die "cần git"
command -v python3 >/dev/null || die "cần python3"
python3 -c "import huggingface_hub" 2>/dev/null \
  || die "thiếu huggingface_hub — chạy: pip install -U huggingface_hub"

# Zip đầu vào: giải nén ra thư mục tạm rồi dùng GGUF bên trong.
if [[ "${GGUF_ARG}" == *.zip ]]; then
  TMP_DIR="$(mktemp -d)"
  unzip -q "${GGUF_ARG}" -d "${TMP_DIR}"
  GGUF_ARG="${TMP_DIR}/${GGUF_NAME}"
fi
[[ -f "${GGUF_ARG}" ]] || die "không thấy GGUF tại ${GGUF_ARG} (có thể truyền đường dẫn .gguf hoặc file .zip)"

# Xác định username HF từ token (whoami-v2) — không cần nhập tay.
HF_USER="$(python3 - <<'PY'
import os
from huggingface_hub import HfApi
print(HfApi(token=os.environ["HF_TOKEN"]).whoami()["name"])
PY
)"
REPO_ID="${HF_USER}/${SPACE_NAME}"
echo "[upload-model] Space: ${REPO_ID} | GGUF: ${GGUF_ARG} ($(du -h "${GGUF_ARG}" | cut -f1))"

# --- Bước 1: đẩy code Space (Dockerfile, entrypoint.sh, README, model/ nhỏ) ---
if [[ "${MODE}" != "model" ]]; then
  [[ -f "${SPACE_DIR}/Dockerfile" && -f "${SPACE_DIR}/entrypoint.sh" && -f "${SPACE_DIR}/README.md" ]] \
    || die "thiếu file Space trong ${SPACE_DIR}"
  SPACE_URL="https://user:${HF_TOKEN}@huggingface.co/spaces/${REPO_ID}"
  echo "[upload-model] Bước 1: đẩy infra/hf-llm-space -> ${REPO_ID}"
  # git subtree push KHÔNG hỗ trợ --force (đã kiểm chứng với git-subtree cài
  # Homebrew), mà HF đôi khi từ chối non-fast-forward. Dùng subtree split +
  # git push trực tiếp: commit cây con infra/hf-llm-space thành cây gốc tạm
  # (giữ lịch sử), rồi push nhánh đó lên main của Space.
  TMP_BRANCH="bankops-space-sync-$$"
  git -C "${REPO_ROOT}" subtree split --prefix=infra/hf-llm-space -b "${TMP_BRANCH}" >/dev/null
  if ! git -C "${REPO_ROOT}" push "${SPACE_URL}" "${TMP_BRANCH}:main"; then
    echo "[upload-model] bị từ chối — thử lại với --force (HF đôi khi từ chối do backend git bận)"
    git -C "${REPO_ROOT}" push --force "${SPACE_URL}" "${TMP_BRANCH}:main"
  fi
  git -C "${REPO_ROOT}" branch -D "${TMP_BRANCH}"
fi

# --- Bước 2: upload GGUF fine-tune vào model/ của repo Space ---
if [[ "${MODE}" != "code" ]]; then
  echo "[upload-model] Bước 2: upload ${GGUF_NAME} -> ${REPO_ID} (model/${GGUF_NAME})"
  HF_TOKEN="${HF_TOKEN}" HF_REPO_ID="${REPO_ID}" python3 - "${GGUF_ARG}" <<'PY'
import os
import sys

from huggingface_hub import HfApi

gguf_path = sys.argv[1]
repo_id = os.environ["HF_REPO_ID"]
api = HfApi(token=os.environ["HF_TOKEN"])
api.upload_file(
    path_or_fileobj=gguf_path,
    path_in_repo=f"model/{os.path.basename(gguf_path)}",
    repo_id=repo_id,
    repo_type="space",
)
print(f"[upload-model] uploaded model/{os.path.basename(gguf_path)} -> {repo_id}")
PY
  echo "[upload-model] XONG. Space sẽ build lại và nhúng GGUF fine-tune vào image."
fi

if [[ -n "${TMP_DIR:-}" ]]; then
  rm -rf "${TMP_DIR}"
fi
