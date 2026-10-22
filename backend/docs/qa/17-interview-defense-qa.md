# QA 17 — Interview Defense: Portfolio Asset Registry & Vietnamese Q&A

## Portfolio Asset Registry (G17 - Track A/B/C)

### Registry Overview
The portfolio asset registry compiles all audited assets across 5 repositories:
- **retail-finance-core-platform**: Core banking platform with Maven/CI gaps resolved
- **OpsBridge**: .NET order submission system with concurrency harness
- **QuanLyKho**: Warehouse management with AI/ML components
- **AKS-SRE-Platform**: Kubernetes/SRE evidence and runbooks
- **SmartDocumentChatbot**: Document chatbot system

### Asset Categories

#### 1. CI/CD & Infrastructure (Track A)
- **G1-G2**: Maven working-directory fix for CI pipelines
- **G3**: OpsBridge concurrency harness verification (50 buyers/10 units)
- **G4**: Uncommitted working-tree changes across repos
- **G9**: Reconciliation service test verification
- **G10**: Flyway migration drift gate
- **G12**: Terraform CI lint/validation gate
- **G13**: Kind vs real-AKS tier labeling

#### 2. Capability & Verification Gaps (Track B)
- **G5**: Optimistic concurrency Version token testing
- **G6**: Outbox row commit + compensation failure repair
- **G7**: Pod-level liveness/readiness probes
- **G8**: Service-level concurrency test (pending)
- **G11**: AI component review (keep/use-case-justified)
- **G15**: k6 load test integration into CI
- **G16**: SLI/SLO baseline conversion to runbooks

#### 3. Optional & AI Capabilities (Track C)
- **G11**: AI/airflow/MLflow components review
- **G14**: Interview diagram authoring (request lifecycle, transaction boundary, message flow, recovery)
- **G17**: Portfolio registry + Vietnamese Q&A compilation
- **G18**: Additional repository CI gap analysis
- **G19**: Interview defense Q&A finalization (Vietnamese)

### Vietnamese Q&A for Interview Defense

#### Q1: CI Fix for Maven Working Directory
**Q**: Làm sao để fix issue CI `unit` và `integration` jobs chạy `mvn` tại repo root nhưng `pom.xml` nằm trong `backend/`?
**A**: Thêm `defaults: run: working-directory: backend` vào jobs `unit` và `integration` trong GitHub Actions. Fix được trên branch `fix/ci-maven-backend-working-directory`, PR #1 chưa merge vào main mà cần duyệt.

#### Q2: Testcontainers MySQL Integration
**Q**: Integration tests dùng Testcontainers MySQL tại local run được không?
**A**: Không, Docker daemon không có sẵn tại local. Nhưng trên CI GitHub Actions run thành công (run 39630546625) với MySQL 8 thực tế qua Testcontainers.

#### Q3: Zero-Oversell Guarantee
**Q**: Zero-oversell invariant như thế nào trong OpsBridge concurrency harness test?
**A**: Test 50 buyers争抢 10 đơn, kết quả chính xác là 10 đơn được tạo, 40 × 409 fast-fails xảy ra. Nguyên tắc: tổng số lượng đặt không vượt quá tồn kho có sẵn.

#### Q4: AdR Coverage
**Q**: ADRs 001–021 đã bao bêu quyết định chính nào?
**A**: Các quyết định về request lifecycle, transaction boundary, message flow, recovery pattern, optimistic concurrency, idempotency key, outbox compensation, healthchecks, etc.

#### Q5: MLflow Model Promotion
**Q**: Quy trình promote model DemandForecastModel lên Production là sao?
**A**: Train model với time-aware split (96 train/24 test), đạt R2 ≥ 0.7, sau đó dùng `promote_model(from_version=1)` để chuyển sang stage Production qua MLflow Model Registry.

#### Q6: AI Assessment Heuristic
**Q**: AI assessment heuristic đánh giá rủi ro phiếu như thế nào?
**A**: Heuristic dựa trên loại phiếu (cash/quỹ/inventory/adjustment/receipt/stocktake), số tiền/lượng, lý do, kiểm tra ngưỡng an toàn (VND 500M cho quỹ, qty ≥ 10 cho adjustment), và lý do ngắn hơn 5 ký tự sẽ tăng risk_score.

#### Q7: Retrieval-Augmented Generation
**Q**: RAG system retrieve knowledge từ gap register như thế nào?
**A**: Dùng keyword-based retrieval (_terms function, stop-word filtering) qua docs/gap-register.md và docs/qa/*.md, sau đó grounded_prompt() tạo prompt có citation [source] cho LLM trả lời.

#### Q8: Portfolio Defense Scope
**Q**: Portfolio asset registry bao gồm bao nhiêu repo và gap bao nhiêu?
**A**: 5 repository, 19 gap (G1-G19) bao gồm P0 broken correctness, P1 high-value capabilities, P2 reliability/observability, P3 optional features.

#### Q9: Kind vs Real-AKS Separation
**Q**: Làm sao đảm bảo Kind results không bị nhầm với real-AKS results?
**A**: Mỗi kết quả phải được label là PRE_AZURE_DRY_RUN hoặc Azure, tuyệt đối không nhầm lẫn hai tier này trong evidence.

#### Q10: Interview Diagram Structure
**Q**: 4 interview diagram (request lifecycle, transaction boundary, message flow, recovery) có structure như thế nào?
**A**: Mỗi diagram mô tả: 1) Request lifecycle: từ client request đến xử lý xong, 2) Transaction boundary: ranh giới transaction bao gồm gì, 3) Message flow: luồng message qua các service, 4) Recovery: pattern phục hồi khi lỗi xảy ra (compensating transaction, retry, circuit breaker).