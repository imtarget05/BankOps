# BankOps LLM trên Modal (thay HF Space — Docker Space hiện cần gói PRO)

Backend LLM tự host cho trợ lý AI của BankOps: **GGUF fine-tune
Qwen2.5-1.5B-Instruct (Q4_K_M, ~940 MB)** chạy bằng `llama-cpp-python` trên
**Modal** (container CPU 2 vCPU / 2 GiB), API tương thích OpenAI
(`/v1/chat/completions`).

> Vì sao không phải HF Space nữa: từ 2026 HF yêu cầu gói **PRO ($9/tháng)** để
> tạo Space Docker/Gradio trên hardware free (chỉ Static Space miễn phí, không
> chạy được llama.cpp). Modal Starter miễn phí **$30 credit/tháng** — với
> scale-to-zero (container tự ngủ sau 15 phút không traffic), traffic demo của
> BankOps nằm trọn trong hạn mức này. API và cách nối Worker **không đổi** so
> với docs/17 — chỉ khác `HF_LLM_BASE_URL`.

## Cấu trúc thư mục

| File | Vai trò |
|---|---|
| `modal_app.py` | Định nghĩa Modal App: image (pin version), volume, web server, hàm upload model |
| `bankops_llm_server.py` | FastAPI OpenAI-compatible — chạy bằng uvicorn trong container |
| `../scripts/upload-model-to-modal.sh` | Upload GGUF (file `.gguf` hoặc `.zip`) lên Modal Volume |

## Thiết lập lần đầu (~5 phút)

```bash
# 1. Cài CLI + đăng nhập (mở browser để xác thực)
uv tool install modal
modal setup

# 2. Upload model fine-tune (chấp nhận cả .zip — script tự giải nén)
bash infra/scripts/upload-model-to-modal.sh ~/Downloads/bankops_integration_files.zip

# 3. Deploy — in ra URL tĩnh dạng https://<workspace>--bankops-llm-serve.modal.run
modal deploy infra/modal/modal_app.py
```

## Nối vào Cloudflare Worker

URL hiện tại (workspace `imtarget05`):
`https://imtarget05--bankops-llm-serve.us-east.modal.run`

Đặt URL ở trên vào `HF_LLM_BASE_URL` trong `infra/cloudflare-worker/wrangler.toml`
(production + staging — đã cấu hình sẵn) rồi deploy lại Worker. Workers AI
(`@cf/meta/llama-3.1-8b-instruct`) tự thành fallback khi backend lỗi/đang ngủ —
API không bao giờ chết. `HF_LLM_TIMEOUT_MS = "90000"` để request đầu tiên sau
cold start vẫn kịp chờ backend dậy thay vì rơi xuống fallback sớm.

## Cold start & chi phí

- Container **ngủ sau 15 phút** không traffic (`scaledown_window=900`); request
  đầu tiên sau khi ngủ mất **~60–90s** (kéo container + load model ~20–40s).
  Request đó có thể bị Worker timeout 30s và rơi xuống fallback Workers AI;
  các request sau đi vào bản fine-tune. Muốn chờ hết cold start, nâng
  `HF_LLM_TIMEOUT_MS` (ví dụ `120000`) qua `wrangler secret/var`.
- **Không** nên thêm cron ping giữ ấm: container sẽ chạy 24/7 thật và tốn
  ~$45/tháng — vượt $30 credit miễn phí. Scale-to-zero là điểm cân bằng.
- Model nằm trên **Modal Volume** (`bankops-llm`), KHÔNG nhúng vào image:
  image nhỏ, cold start nhanh, đổi model không phải build lại image.

## Cập nhật model / code

```bash
# Model mới (fine-tune lại):
bash infra/scripts/upload-model-to-modal.sh <gguf-moi.zip|gguf>

# Đổi code server (bankops_llm_server.py / modal_app.py):
modal deploy infra/modal/modal_app.py
```

Không như HF Space (force-push xoá file upload), Modal Volume **giữ nguyên
model giữa các lần deploy** — không cần upload lại sau mỗi lần sửa code.
