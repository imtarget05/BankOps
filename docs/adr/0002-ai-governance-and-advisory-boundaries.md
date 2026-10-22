# ADR 0002: AI Governance, Advisory Boundaries & MLOps Justification

- **Status:** **ACCEPTED & CODE-VERIFIED** (2026-10-22)
- **Requirement Reference:** Closes **G11** from the Gap Register.
- **Related Documents:** [PORTFOLIO_AUDIT_2026-10-21](../PORTFOLIO_AUDIT_2026-10-21.md), [ADR 0001](0001-canonical-api-fastapi-worker-proxy-deprecation.md).

---

## 1. Context & Business Need

QuanLyKho is a warehouse operations and financial inventory platform. Managing inventory receipts, batch expiration (FEFO), and shift variance reconciliation requires high operational rigor. Two experimental components were introduced:
1. **AI Risk Assessment (`POST /ai/assess-request`)**: Provides anomaly detection and risk scoring when a store manager submits high-variance inventory adjustments or transfers.
2. **Batch ETL & MLflow Tracking (`airflow/`, `mlops/`)**: Offline demand forecasting and seasonal inventory reorder prediction.

**The Risk:** Without strict architectural boundaries, automated AI predictions could mistakenly be granted approval authority, violate banking maker-checker separation, accept client-forged request payloads, or block synchronous transactional paths with high-latency inference calls.

---

## 2. Decision & Architectural Controls

### 2.1 AI is Strictly Advisory (Zero Autonomous Approvals)
- Under no circumstance does an AI model or LLM agent possess write authority or approval permissions.
- The system enforces a **deterministic policy floor**: If the AI service is unreachable, degraded, or returns high latency, the server transparently degrades to `heuristic_fallback`.
- Human approval by an authorized `CHECKER` with verified branch scope is the sole authority required to commit stock adjustments.

### 2.2 Server-Enforced Canonical Data & SHA-256 Provenance
- `POST /ai/assess-request` rejects client-supplied voucher fields. The server takes only the canonical `voucher_id`, loads the entity from PostgreSQL within the authenticated checker's branch scope, computes a **SHA-256 provenance hash**, and binds the assessment result to that immutable state.
- Attempting to assess a voucher from another store branch returns `404 Not Found`, eliminating horizontal privilege escalation.

### 2.3 Offline MLOps Pipeline Decoupling (Airflow / MLflow)
- Airflow DAGs (`airflow/dags/ingest_sales_and_inventory.py`) and MLflow run strictly as **asynchronous offline batch processes**.
- They are physically decoupled from the FastAPI request/response loop and PostgreSQL online transaction processing (OLTP).
- If the MLflow server or Airflow worker crashes, the core warehouse operations (`/inventory/issue`, `/inventory/receive`, `/reconciliations/submit`) remain 100% operational with sub-50ms latency.

---

## 3. Interview Defense Talking Points (Vietnamese)

> **Câu hỏi phỏng vấn**: *"Hệ thống của bạn có tích hợp AI vào quy trình kho và ngân hàng. Làm sao bạn đảm bảo mô hình AI không tự ý duyệt các phiếu xuất nhập kho sai lệch, và làm sao đảm bảo tuân thủ nguyên tắc Maker-Checker?"*
>
> **Cách trả lời (Senior/Staff level)**:
> 1. **Ranh giới thẩm quyền (Authority Boundary)**: Trong kiến trúc của tôi, AI tuyệt đối **không có quyền ghi (write authority)**. AI chỉ đóng vai trò khuyến nghị phân tích rủi ro (Advisory Assistant) với rào chắn chính sách xác định (`deterministic policy floor`).
> 2. **Chống giả mạo dữ liệu (Anti-Tampering & Provenance)**: API đánh giá rủi ro không tin tưởng payload từ client mà tự động load chứng từ gốc từ PostgreSQL theo quyền chi nhánh của người duyệt, băm mã SHA-256 làm tem niêm phong (provenance stamp).
> 3. **Quy tắc Kiểm soát kép (Two-Man Rule)**: Chỉ có Checker (Quản lý) bằng xương bằng thịt mới có quyền ký duyệt. Nếu AI chấm điểm rủi ro cao, hệ thống yêu cầu Checker nhập mã PIN xác thực cấp 2. Nếu model AI gặp sự cố hoặc timeout, hệ thống lập tức fallback về luật kinh doanh tĩnh chứ không bao giờ làm gián đoạn vận hành kho.
