# BankOps AI: Hướng dẫn Tích hợp & Triển khai Mô hình LLM

Tài liệu hướng dẫn triển khai giải pháp AI cho hệ thống Quản lý Vận hành Ngân hàng BankOps, bao gồm:
1. **Cloudflare Workers AI (Serverless Cloud)**
2. **Small LLM (Qwen2.5-1.5B) - Fine-tune trên Google Colab T4 & Chạy trên CPU không cần GPU**

---

## 1. Cloudflare Workers AI

Cloudflare Workers AI is called server-side through the FastAPI assessment endpoint (or the Worker's `AI` binding when deployed). Configure credentials only in the deployment secret manager or a local ignored `.env` file:

- `AI_PROVIDER=cloudflare`
- `CLOUDFLARE_ACCOUNT_ID=<your Cloudflare account id>`
- `CLOUDFLARE_API_TOKEN=<Workers AI token>`
- `CLOUDFLARE_MODEL=@cf/meta/llama-3.1-8b-instruct`

Create a scoped API token from Cloudflare Dashboard → Workers AI → Use REST API, granting only the Workers AI permissions required by the account. Never commit API tokens or account credentials. Any token previously placed in source, documentation, environment files, or git history must be revoked and replaced.

---

## 2. Small LLM: Qwen2.5-1.5B (Tối ưu cho Máy không GPU & Fine-tune Colab T4)

### Tại sao chọn Qwen2.5-1.5B-Instruct?
1. **Khả năng tiếng Việt vượt trội**: Hiểu ngữ cảnh tiếng Việt và thuật ngữ ngân hàng tốt nhất trong nhóm mô hình dưới 3B tham số.
2. **Siêu nhẹ trên CPU (Không cần GPU)**: Khi lượng tử hóa sang GGUF `Q4_K_M`, mô hình chỉ chiếm **~1.1 GB dung lượng** và tiêu tốn **< 1.5 GB RAM** khi chạy. Đạt tốc độ 30–50 tokens/giây trên chip Intel / AMD / Apple Silicon.
3. **Fine-tune siêu nhanh trên Colab T4 (Miễn phí)**: Sử dụng QLoRA 4-bit với thư viện `unsloth`, chỉ tốn ~3.5 GB VRAM và hoàn thành 60 bước huấn luyện trong **10–15 phút**.

---

### Hướng dẫn Fine-tune trên Google Colab T4 (3 bước):

1. Mở [Google Colab](https://colab.research.google.com/) và tải file `ai/colab_finetune_bankops_t4.ipynb` lên.
2. Trong menu Colab: chọn **Runtime** -> **Change runtime type** -> Chọn phần cứng **T4 GPU** (miễn phí).
3. Tải kèm file `ai/dataset/train.jsonl` lên thư mục làm việc của Colab và bấm **Run All**.
4. Sau khi huấn luyện xong, notebook sẽ tự động xuất file `qwen2.5-1.5b-q4_k_m.gguf`. Bạn có thể tải file này về máy để chạy cục bộ.

---

### Hướng dẫn Chạy mô hình trên máy KHÔNG CÓ GPU:

#### Cách 1: Chạy qua Ollama (Khuyến nghị)
1. Cài đặt Ollama (nếu chưa có): [https://ollama.com/download](https://ollama.com/download)
2. Đặt file `qwen2.5-1.5b-q4_k_m.gguf` vào cùng thư mục với `ai/Modelfile`.
3. Chạy lệnh:
   ```bash
   ollama create bankops-ai -f ai/Modelfile
   ollama run bankops-ai
   ```
4. Hệ thống FastAPI của BankOps sẽ tự động kết nối qua endpoint `http://localhost:11434/api/chat`.

#### Cách 2: Chạy qua Standalone Python Server (`ai/serve_cpu.py`)
Chạy máy chủ suy luận CPU độc lập bằng lệnh:
```bash
python3 ai/serve_cpu.py
```
Máy chủ sẽ lắng nghe tại cổng `11434` (tương thích hoàn toàn với API Ollama và OpenAI).

---

## 3. Cấu trúc Thư mục `ai/`

```
ai/
├── README.md                      # Hướng dẫn chi tiết
├── Modelfile                      # Cấu hình Ollama cho CPU
├── colab_finetune_bankops_t4.ipynb# Notebook Colab T4 fine-tuning
├── serve_cpu.py                   # Máy chủ suy luận CPU độc lập
└── dataset/
    ├── train.jsonl                # 120+ mẫu hội thoại nghiệp vụ ngân hàng
    └── val.jsonl                  # Dữ liệu đánh giá benchmark
```
