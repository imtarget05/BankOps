# QuanLyKho — kế hoạch chứng minh Senior Software và Software Architect

**Trạng thái:** đề xuất, chưa triển khai. **Baseline:** `main@ecfd799` ngày 23/10/2026. Đọc lại HEAD và CI trước mỗi đợt vì repo vẫn thay đổi. Đây là kế hoạch của **workload QuanLyKho**, không phải kế hoạch tạo AKS hoặc viết Terraform.

## Sản phẩm và ranh giới

Sản phẩm chính là quản lý nguyên liệu trà sữa: nhập theo lô/HSD, xuất FEFO, kiểm kê ca, cảnh báo và maker–checker cho điều chỉnh. Quỹ, journal và đối soát là mô phỏng phụ trợ. FastAPI + PostgreSQL là nguồn ghi chuẩn; Flutter là client; `infra/cloudflare-worker` là legacy/compatibility, không sở hữu nghiệp vụ. AI chỉ tư vấn; người có quyền mới duyệt. Bám `docs/03-architecture.md`, `docs/adr/0001-canonical-api-fastapi-worker-proxy-deprecation.md` và `docs/adr/0002-ai-governance-and-advisory-boundaries.md`.

## R0 — Chốt baseline và sửa lỗi đúng contract

**Bằng chứng hiện tại:** [S10 pass](https://github.com/imtarget05/QuanLyKho/actions/runs/39898588721); [CI chính fail](https://github.com/imtarget05/QuanLyKho/actions/runs/39898588877) ở lint và test; [S11 fail](https://github.com/imtarget05/QuanLyKho/actions/runs/39898588642) vì DAG thêm `detect_drift` nhưng test vẫn coi `promote_demand_model` là task cuối. [GitOps CI fail](https://github.com/imtarget05/QuanLyKho/actions/runs/39898588656) ở Ruff; [deploy fail](https://github.com/imtarget05/QuanLyKho/actions/runs/39898588715) ở Azure Login. `README.md` và `tasks/current.md` còn số liệu lịch sử, nên không được dùng chúng để gọi HEAD hiện tại là xanh.

1. **P0: branch/location authorization.** Kiểm tra `backend/app/api/routes/inventory.py` tại các route low-stock, expiry, stock-level và threshold; đối chiếu `backend/tests/test_inventory_alert_scope_unit.py`. Chạy negative test với hai branch và hai location trên DB cô lập; endpoint đọc không được trả dữ liệu ngoài branch, endpoint ghi không được đổi threshold ngoài branch. Sửa code/policy theo yêu cầu nghiệp vụ, không xóa hoặc nới test để lấy màu xanh.
2. **P0: reviewer và demo contract.** Đối chiếu `backend/tests/test_reviewer_readonly.py` với capability matrix và route `backend/app/api/routes/demo.py`: reviewer chỉ đọc trong phạm vi được cấp, `demo_reset` chỉ tồn tại ở demo profile và trả lỗi đúng contract khi không được phép. Test AI phải tạo phiếu canonical trước khi đánh giá, vì assessment giờ tra DB thay vì tin request ID giả. Xác minh E2E maker–checker dựa trên phân trang/scope thực tế, không phụ thuộc dữ liệu seed tình cờ.
3. **P1: lint và secret templates.** Chạy đúng Ruff 0.17.0 của `.github/workflows/ci.yml`; sửa import/rule vi phạm. Đồng bộ `.env.example`, `scripts/sync_github_secrets.sh` và test của chúng theo một bộ tên biến; không đưa giá trị secret vào repo.
4. **P1: S11.** Xác nhận `detect_drift` thuộc DAG canonical trong `infra/airflow/` rồi sửa `backend/tests/test_airflow_dags.py` để kiểm tra đúng task/dependency. Sau structural test, workflow `.github/workflows/s11-e2e-cloud-ci.yml` phải chạy được migration → ingestion → train → registry/promotion → `/predict` → drift → rollback → inference bằng model rollback trên DB/MLflow cô lập. Không coi syntax-only pass là E2E.

**Gate R0:** `CI`, `S10`, `S11` và GitOps validation pass trên cùng SHA; mọi lỗi branch-scope, reviewer và AI canonical binding có regression test. Deploy cloud là gate riêng; nếu chưa cấu hình OIDC thì ghi `NOT_VERIFIED`, không làm workflow đỏ trông như deployment đã có.

## R1 — Một hành trình nghiệp vụ có tính đúng

1. Dùng `scripts/demo_ai_checker.sh` và `backend/tests/verify_live_e2e.py` làm điểm bắt đầu, nâng thành journey Flutter → FastAPI → PostgreSQL: nhận lô có HSD, xuất FEFO, kiểm kê ca, submit, checker approve/reject. Sau từng bước kiểm tra movement, balance, audit và outbox trong DB; không chỉ assert HTTP 200.
2. Thêm các ca cạnh tranh: hai checker cùng duyệt, cùng `Idempotency-Key` replay, key khác sau trạng thái cuối, worker lỗi sau business commit, trang alert chỉ thấy dữ liệu branch hiện hành. Kết quả phải chứng minh không double-post và không lộ dữ liệu chéo branch.
3. Với thay đổi schema, chạy Alembic lên DB mới và DB từ phiên bản trước; ghi preflight, thời gian migration, rollback/forward fix. Diễn tập backup/restore vào DB tách biệt và đo RTO/RPO thực. `docs/20-backup-disaster-recovery-runbook.md` hiện ghi mục tiêu 5/15/30 phút; gắn rõ **mục tiêu chưa được đo** cho tới khi drill đủ đại diện.
4. Đặt một load profile vừa với nghiệp vụ: số ca/người dùng, tỷ lệ đọc/ghi và ngưỡng p95/error rate **sau khi đo baseline**. Kiểm thử correctness dưới tải trước tối ưu hiệu năng.

**Gate R1:** demo 10 phút chạy trên release SHA và DB synthetic sạch; có raw test/log/evidence, ma trận quyền âm tính, migration/restore drill, số đo load và giới hạn môi trường.

## R2 — Kiến trúc có thể bảo vệ trong phỏng vấn

1. Cập nhật `docs/03-architecture.md` theo mã hiện tại: context/boundary, transaction DB, outbox/worker, Flutter/API, Cloudflare Pages/Worker legacy; C4 container/component và sequence của một approval. ADR phải ghi bài toán, phương án đơn giản hơn, trade-off và phép đo. Lý do giữ modular monolith: một transaction bảo vệ approval, movement, audit và outbox; chỉ tách service khi có ranh giới sở hữu hoặc tải được đo.
2. Viết threat model cho quyền branch, demo identity, AI input, audit stamp, secrets và các điểm public. `POST /ai/assess-request` chỉ là tư vấn trên phiếu canonical; không có quyền tự approve.
3. Giữ MLOps nếu dự báo nhu cầu có mục tiêu và metric chất lượng rõ. Không thêm multi-agent, RAG hoặc offline sync trong đợt này. Nếu thêm Inventory Ops Agent sau R0/R1, phiên bản đầu chỉ đọc và soạn **bản nháp**, có eval so với rule cảnh báo; mọi lệnh ghi vẫn qua maker–checker.

**Gate R2:** mỗi claim kiến trúc chỉ tới một test/measurement hoặc được ghi `DESIGN_ONLY`; README có luồng demo, commit/CI link, giới hạn và claim được phép dùng trên CV.

## Hợp đồng với AKS-SRE-Platform

QuanLyKho sở hữu image/Dockerfile, probes, resource requests, Kustomize overlay ở `infra/k8s/`, migration Job/contract và metric của ứng dụng. AKS repo sở hữu Argo Application, AppProject, namespace/platform policy, Gateway và shared observability. Chưa có Argo Application QuanLyKho được kiểm chứng trong AKS repo; thêm sau R0, render source thật bằng repo-map và pin release SHA/digest. Frontend có thể ở Cloudflare Pages; không quảng cáo Cloudflare Worker legacy là backend. Chỉ claim Azure runtime khi có bằng chứng deployment thật, với state/cost gate của AKS repo.

## Thứ tự và điểm dừng

R0 trước R1, R1 trước R2. Nếu R0 kéo dài, cắt AI/ML/UI mới trước; không cắt kiểm thử branch-scope hoặc CI. Chỉ có tối đa hai repo active cùng lúc. Kế hoạch này không tự động cấp quyền cloud apply hay thay đổi secret.
