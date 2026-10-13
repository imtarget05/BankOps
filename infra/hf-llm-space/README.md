---
title: BankOps LLM
emoji: 🏦
colorFrom: blue
colorTo: green
sdk: docker
app_port: 7860
pinned: false
---

# BankOps LLM backend (llama.cpp trên HF Space)

Backend LLM tự host cho trợ lý AI của BankOps — chạy llama.cpp server với
Qwen2.5-1.5B-Instruct (Q4_K_M, ~1.1 GB) trên CPU free tier của Hugging Face
(2 vCPU / 16 GB RAM). API tương thích OpenAI (`/v1/chat/completions`).

Cloudflare Worker của BankOps gọi backend này qua biến `HF_LLM_BASE_URL`;
nếu backend lỗi hoặc đang ngủ, Worker tự rơi về Cloudflare Workers AI.
Hướng dẫn đầy đủ: `docs/17-hf-llm-space.md` trong repo BankOps.

## Endpoints

- `GET /health` — llama.cpp health probe
- `POST /v1/chat/completions` — OpenAI-compatible chat completions

## Cấu hình (biến môi trường, có mặc định)

| Biến | Mặc định | Ghi chú |
|------|----------|---------|
| `MODEL_REPO` | `Qwen/Qwen2.5-1.5B-Instruct-GGUF` | repo GGUF gốc trên HF Hub (fallback) |
| `MODEL_FILE` | `qwen2.5-1.5b-instruct-q4_k_m.gguf` | file GGUF gốc (1.12 GB, tải lúc build khi thiếu bản fine-tune) |
| `BANKOPS_MODEL_FILE` | `Qwen2.5-1.5B-Instruct.Q4_K_M.gguf` | GGUF fine-tune BankOps trong `model/` (ưu tiên dùng nếu có) |
| `PORT` | `7860` | phải khớp `app_port` trong README |

## Model

- **Ưu tiên:** `model/Qwen2.5-1.5B-Instruct.Q4_K_M.gguf` — bản fine-tune BankOps
  (~940 MB), upload bằng `infra/scripts/upload-model-to-hf.sh` từ repo BankOps
  (xem `docs/17-hf-llm-space.md` mục 2b). Kèm `model/chat_template.jinja`.
- **Fallback:** bản gốc `Qwen/Qwen2.5-1.5B-Instruct-GGUF` tải từ HF Hub lúc build
  khi `model/` chưa có GGUF fine-tune.

## Lưu ý

- Space free **ngủ sau 48 giờ không có request**; request đầu tiên sau khi ngủ
  sẽ mất vài phút để khởi động lại (Worker có fallback Workers AI nên người dùng
  vẫn nhận được câu trả lời).
- Model được nhúng vào image lúc **build** — restart không tải lại.
- Không đặt secret nào trong repo này; nếu cần, dùng Settings → Variables and
  secrets của Space.