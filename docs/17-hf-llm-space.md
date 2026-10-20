# 17 — Backend LLM trên Modal (llama.cpp)

> **⚠️ ARKIVED / KHÔNG DÙNG.** Tài liệu này chỉ là lịch sử tham khảo.
> Theo ADR 0001 (quyết định năm 2026-10-14), phương án **Hugging Face Space đã bị
> khử** — HF yêu cầu gói PRO cho Space Docker/Gradio, không còu đủ điều kiện.
> Lộ trình hiện tại: chạy GGUF trên **Modal** (miễn phí $30 credit/tháng,
> scale-to-zero). Xem `infra/modal/README.md` và
> `infra/scripts/upload-model-to-modal.sh`.
>
> **Hành động bắt buộc**: bất kỳ tài liệu nào còn hướng dẫn `set HF_LLM_BASE_URL`
> hoặc deploy Worker với backend HF Space đều **PHẢI được cập nhật lại** — chúng
> mâu thuẫn với ADR 0001 và hợp đồng test `assert "HF_LLM_BASE_URL" not in env`.
> Chỉ có `MODAL_LLM_BASE_URL` mới là hợp lệ.

## 0. Lịch sử (KHÔNG thực thi)

| Tiêu chí | HF Space (llama.cpp) | Workers AI (fallback) | Colab |
|---|---|---|---|
| Chi phí | Miễn phí | Miễn phí (có quota/ngày) | Miễn phí nhưng chết sau ~90 phút |
| Chạy 24/7 | ✅ (ngủ sau 48h không dùng) | ✅ | ❌ |
| Kiểm soát model | ✅ tự chọn GGUF | ❌ chỉ model của CF | ✅ |
| Bảo mật | Token HF trong Secrets của Space | binding nội bộ | — |
| Tích hợp | 1 biến `HF_LLM_BASE_URL` trên Worker | đã chạy sẵn | cần proxy |

Không cần GPU: model 1.5B Q4_K_M (~1.1 GB) chạy tốt trên CPU.

## Trạng thái hiện tại: Modal (theo ADR 0001)

Lưu trữ backend LLM riêng — Qwen2.5-1.5B-Instruct, GGUF Q4_K_M — trên **Modal**
(miễn phí $30 credit/tháng, scale-to-zero). Worker ưu tiên backend này;
Cloudflare Workers AI giữ vai trò fallback nên API không bao giờ chết khi
Modal lỗi hoặc đang ngủ.

- Code: `infra/modal/`
- Upload model: `infra/scripts/upload-model-to-modal.sh`
- Biến Worker: `MODAL_LLM_BASE_URL` (KHÔNG phải `HF_LLM_BASE_URL`)
- Test contract: `assert "HF_LLM_BASE_URL" not in os.environ` (xem
  `backend/tests/conftest.py` — fail nếu biến này xuất hiện)

## Checklist năm 2026-10-14 đã ngưng lưu động

- [x] Chọn Modal thay thế HF Space
- [x] Xóa `ai.ts` (Worker AI module — không còn dùng Workers AI làm primary)
- [x] `wrangler.toml` chỉ còn health-check (không có OTEL LLM endpoint)
- [x] Test cấm `HF_LLM_BASE_URL`

## 0. Vì sao phương án này

| Tiêu chí | HF Space (llama.cpp) | Workers AI (hiện tại) | Colab |
|---|---|---|---|
| Chi phí | Miễn phí | Miễn phí (có quota/ngày) | Miễn phí nhưng chết sau ~90 phút |
| Chạy 24/7 | ✅ (ngủ sau 48h không dùng, tự dậy khi có request) | ✅ | ❌ |
| Kiểm soát model | ✅ tự chọn GGUF, tự fine-tune được | ❌ chỉ model của CF | ✅ |
| Bảo mật | Token HF (nếu có) nằm trong Secrets của Space | binding nội bộ | — |
| Tích hợp | 1 biến env `HF_LLM_BASE_URL` trên Worker | đã chạy sẵn | cần proxy |

Không cần GPU: model 1.5B lượng tử hóa Q4_K_M (~1.1 GB) chạy tốt trên CPU,
tốc độ chấp nhận được cho trợ lý hội thoại nội bộ.

## 1. Tạo Space (thao tác tay trên web, ~5 phút)

1. Đăng nhập https://huggingface.co → **New Space**.
2. Space name: `bankops-llm` (URL sẽ là `https://<user>-bankops-llm.hf.space`).
3. SDK: **Docker** → Blank.
4. License: apache-2.0 (khớp license của Qwen2.5).
5. Hardware: **CPU basic — FREE (2 vCPU, 16 GB RAM)**.
6. Visibility: **Public** (bắt buộc để Worker gọi được; endpoint chat vẫn an toàn
   vì Worker chỉ gọi từ server-side, và có thể bật API key — xem mục 5).

## 2. Đưa code vào Space

Push thư mục `infra/hf-llm-space/` của repo này lên Space (Space là một git repo).
Dùng script có sẵn (tự xác định username từ `HF_TOKEN`, tự fallback `--force`
khi HF từ chối non-fast-forward):

```bash
export HF_TOKEN=hf_xxx   # token quyền write — KHÔNG commit vào repo
bash infra/scripts/upload-model-to-hf.sh --code-only
```

(Hoặc làm tay: `git subtree push --prefix=infra/hf-llm-space \
https://<user>:<HF_TOKEN>@huggingface.co/spaces/<user>/bankops-llm main`.
Lưu ý: `git subtree push` không có cờ `--force`; nếu bị từ chối
non-fast-forward, dùng `git subtree split --prefix=infra/hf-llm-space -b tmp`
rồi `git push --force <url> tmp:main`.)

Nội dung thư mục:

| File | Vai trò |
|---|---|
| `Dockerfile` | Image `ghcr.io/ggml-org/llama.cpp:server` (pin theo digest `server-b4740`) + nhúng model lúc build |
| `entrypoint.sh` | Khởi động `llama-server` trên cổng 7860 (khớp `app_port`) |
| `README.md` | Metadata của Space (`sdk: docker`, `app_port: 7860`) — bắt buộc |
| `.gitattributes` | Quy tắc LFS (phòng khi commit model vào repo) |
| `model/` | Tokenizer/config/chat-template của bản fine-tune + GGUF fine-tune (upload bằng script — mục 2b) |

Model mặc định (fallback) là bản gốc công khai `Qwen/Qwen2.5-1.5B-Instruct-GGUF`,
file `qwen2.5-1.5b-instruct-q4_k_m.gguf`, ~1.12 GB, tải lúc build từ HF Hub
(không cần token) và nhúng vào image, nên restart Space không tải lại.
Build lần đầu mất ~5–10 phút.

## 2b. Model fine-tune BankOps (GGUF riêng — bắt buộc để dùng bản đã train)

Bản fine-tune BankOps của Qwen2.5-1.5B-Instruct (Q4_K_M, ~940 MB — nhỏ hơn bản
gốc vì quantize riêng, metadata GGUF `general.name = Bankops_Qwen2.5_1.5B_Gguf`)
được train từ notebook `ai/colab_finetune_bankops_t4.ipynb`. File này **không
thể** nằm trong repo BankOps trên GitHub (giới hạn 100 MB/file) — nó được upload
trực tiếp vào repo của Space, vào thư mục `model/`:

```bash
export HF_TOKEN=hf_xxx   # token quyền write
pip install -U huggingface_hub   # nếu chưa có

# Truyền file .gguf hoặc cả file .zip chứa model (script tự giải nén):
bash infra/scripts/upload-model-to-hf.sh ~/Downloads/bankops_integration_files.zip
```

Script làm 2 việc: (1) đẩy code Space, (2) upload GGUF vào `model/` của repo
Space bằng `huggingface_hub`. **Lưu ý quan trọng:** sau mỗi lần đẩy code lại
(bước 1 dùng `--force` khi cần, ghi đè lịch sử repo Space) phải chạy lại bước
upload model, vì lịch sử mới của repo Space không còn file GGUF cũ.

Khi `model/Qwen2.5-1.5B-Instruct.Q4_K_M.gguf` tồn tại trong repo Space:
- Image build sẽ **không tải** bản gốc từ Hub nữa (tiết kiệm ~1.12 GB),
- `entrypoint.sh` chạy GGUF fine-tune kèm `--chat-template model/chat_template.jinja`,
- alias model hiển thị là `Qwen2.5-1.5B-Instruct.Q4_K_M`.

Chưa upload GGUF? Space vẫn build và chạy được với bản gốc Qwen (fallback) —
chất lượng trả lời theo persona BankOps sẽ kém hơn cho đến khi upload xong.

## 3. Kiểm tra Space

```bash
curl https://<user>-bankops-llm.hf.space/health
# → {"status":"ok"} (hoặc "ok" tùy phiên bản llama-server)

curl https://<user>-bankops-llm.hf.space/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Xin chào"}],"max_tokens":64,"stream":false}'
```

Giao diện web chat của llama-server cũng có sẵn tại URL gốc của Space.

## 4. Cắm vào Worker (đã hỗ trợ sẵn trong code)

`infra/cloudflare-worker/src/routes/ai.ts` đã có logic: nếu `HF_LLM_BASE_URL`
được cấu hình thì gọi `${HF_LLM_BASE_URL}/v1/chat/completions` (chuẩn OpenAI)
trước; lỗi (timeout/5xx/mạng) thì tự rơi về Workers AI binding như cũ.

Bật backend trên Worker:

```bash
cd infra/cloudflare-worker

# Production — sửa HF_LLM_BASE_URL trong wrangler.toml [vars] rồi:
npx wrangler deploy

# Staging
npx wrangler deploy --env staging
```

Hoặc set như secret (không cần sửa wrangler.toml):

```bash
npx wrangler secret put HF_LLM_BASE_URL            # prod
npx wrangler secret put HF_LLM_BASE_URL --env staging
```

Biến liên quan (tất cả optional, có mặc định an toàn):

| Biến | Mặc định | Ý nghĩa |
|---|---|---|
| `HF_LLM_BASE_URL` | `""` (tắt) | URL gốc của Space, ví dụ `https://<user>-bankops-llm.hf.space`. Rỗng = dùng Workers AI. Chỉ chấp nhận `https://`. |
| `HF_LLM_API_KEY` | không set | Bearer token nếu bật API key ở mục 5. Không cần khi Space public không khóa. |
| `HF_LLM_MODEL` | `self-hosted-llama-cpp` | Tên model trả về trong response (chỉ để hiển thị). |
| `HF_LLM_TIMEOUT_MS` | `30000` | Timeout mỗi lần gọi Space (ms). |
| `HF_LLM_MAX_TOKENS` | `512` | Giới hạn token sinh ra. |

Không cần thêm rate limit mới: `/api/v1/ai/*` vẫn đi qua `AI_CHAT_LIMIT` /
`AI_ASSESSMENT_LIMIT` (10 req/phút/người dùng) như trước.

## 5. (Khuyến nghị) Bật API key cho Space

Space public ai cũng gọi được. Để chặn người lạ:

1. Trong Space → **Settings → Variables and secrets** → thêm secret `API_KEY`
   với giá trị ngẫu nhiên (ví dụ `openssl rand -hex 32`).
2. Sửa `entrypoint.sh` thêm `--api-key "${API_KEY}"` vào lệnh `llama-server`
   (llama.cpp hỗ trợ flag này; biến được inject lúc runtime).
3. Trên Cloudflare: `npx wrangler secret put HF_LLM_API_KEY` (hoặc thêm qua
   dashboard) với cùng giá trị.

Worker tự gửi `Authorization: Bearer <key>` khi `HF_LLM_API_KEY` được set.

## 6. Hành vi khi Space ngủ / lỗi

- Space free ngủ sau **48 giờ** không có request. Request đầu tiên sau khi ngủ
  mất vài phút để dựng container → Worker đợi tối đa `HF_LLM_TIMEOUT_MS` (30s)
  rồi fallback sang Workers AI, người dùng vẫn nhận được câu trả lời.
- Muốn Space luôn tỉnh: dùng cron ngoài (ví dụ cron-job.org) ping `/health`
  mỗi 24h, hoặc nâng hardware trả phí.
- Kiểm tra backend nào đang phục vụ: response của `/api/v1/ai/chat` có
  `provider` = `hf-space` | `cloudflare-workers-ai`; response của
  `/api/v1/ai/assess-request` có `assessment_source` = `hf-space` |
  `cloudflare` | `heuristic_fallback`.

## 7. Nâng cấp model (khi muốn)

Sửa `MODEL_REPO` / `MODEL_FILE` trong `Dockerfile` rồi push lại — Space build
lại với model mới. Các lựa chọn GGUF cùng cỡ: `Qwen2.5-1.5B-Instruct` (mặc
định), `Llama-3.2-1B-Instruct-GGUF` (bản của bartowski), hoặc bản fine-tune
BankOps của bạn (xem `ai/README.md` và mục 2b — upload bằng
`infra/scripts/upload-model-to-hf.sh`).

Muốn train lại bản fine-tune: chạy notebook `ai/colab_finetune_bankops_t4.ipynb`
(Colab T4, QLoRA 4-bit, ~10–15 phút), xuất GGUF Q4_K_M rồi upload lại bằng
script ở mục 2b. Đổi tên file GGUF mới thì cập nhật luôn `BANKOPS_MODEL_FILE`
trong `Dockerfile` (và xóa GGUF cũ trong `model/` của repo Space để image
không phình ra).

## 8. Checklist nghiệm thu

- [ ] Space build thành công, `/health` trả 200
- [ ] `/v1/chat/completions` trả JSON chuẩn OpenAI
- [ ] GGUF fine-tune đã upload vào `model/` (mục 2b) — log build KHÔNG có dòng
      `[build] fine-tuned GGUF not found...` (có dòng đó nghĩa là đang dùng fallback bản gốc)
- [ ] Worker deploy xong, `/api/v1/ai/chat` trả `provider: "hf-space"`
- [ ] Pause Space → `/api/v1/ai/chat` vẫn 200 với `provider: "cloudflare-workers-ai"`
- [ ] Không có token/secret nào nằm trong git (token HF chỉ ở Secrets của Space)

## 9. Rủi ro & lưu ý

- **Ngủ 48h**: chấp nhận được vì có fallback; ping định kỳ nếu cần luôn tỉnh.
- **Free CPU chậm**: ~5–15 token/giây với 1.5B Q4_K_M — đủ cho chat ngắn,
  không đủ cho batch. Giới hạn `max_tokens` đã có sẵn (512).
- **Public Space**: ai biết URL cũng dùng được băng thông của bạn → bật API key (mục 5).
- **LLM tự host có thể trả JSON sai**: route `/assess-request` đã có
  `parseAssessment` + merge với policy deterministic — kết quả xấu sẽ bị bỏ,
  không bao giờ chặn nghiệp vụ.
