# BankOps — Thiết kế web/app cho nhân viên

Ngày khảo sát: **14/10/2026**. Nguồn: working tree hiện tại, bao gồm thay đổi chưa commit.

BankOps đã có nền tảng demo kho và quỹ mô phỏng, nhưng chưa đủ cơ sở để tuyên bố sẵn sàng cho nhân viên vận hành dữ liệu thật. Hai API FastAPI và Cloudflare Worker hiện có khác biệt về quyền, transaction, tích hợp và đối soát. Bộ tài liệu này nối hiện trạng mã nguồn với thiết kế sản phẩm và các bước hoàn thiện có thể nghiệm thu.

## Đọc theo nhu cầu

| Tài liệu | Nội dung | Người sử dụng |
|---|---|---|
| [01 — Hiện trạng codebase](01-codebase-assessment.md) | Bản đồ hệ thống, luồng đang chạy trong mã, khác biệt API, phát hiện có vị trí nguồn | Tech lead, developer, QA |
| [02 — Kiến trúc đích](02-target-architecture.md) | Ranh giới module, transaction, dữ liệu, API, quyền, sự kiện, triển khai | Tech lead, backend, frontend |
| [03 — Nghiệp vụ và trải nghiệm nhân viên](03-employee-workflows.md) | Vai trò, quyền, hành trình, state machine, màn hình, trường dữ liệu, ngoại lệ | PO, BA, vận hành, thiết kế, QA |
| [04 — Backlog và nghiệm thu](04-delivery-and-acceptance.md) | Thứ tự triển khai, phụ thuộc, file chịu tác động, test và điều kiện pilot | Nhóm triển khai |
| [05 — Chỉ mục source](05-source-index.md) | Danh sách source toàn repo và liên kết để tiếp tục đọc; không phải chứng nhận độ phủ review | Developer |

## Quy ước đọc

- **Hiện trạng**: hành vi được nhìn thấy trong mã nguồn; không đồng nghĩa đã chạy thành công trên môi trường triển khai.
- **Đề xuất**: thiết kế cần triển khai; không phải tính năng đã có.
- **Cần xác nhận nghiệp vụ**: quyết định của đơn vị vận hành; giả định được ghi rõ để tiếp tục thiết kế.
- **P0**: phải xử lý trước pilot có tài khoản nhân viên; **P1**: hoàn thiện luồng vận hành pilot; **P2**: mở rộng sau khi nền tảng ổn định.

Giữ ranh giới hiện hữu: quỹ là **mô phỏng**, không thêm core banking, thanh toán hay tiền thật. Các ngưỡng 500 triệu/50 đơn vị hiện chỉ là quy tắc demo trong code, không phải hạn mức hay quy định ngân hàng đã được xác nhận.

## Phạm vi bằng chứng

Đã kiểm kê cấu trúc toàn repo và đọc sâu các đường nghiệp vụ chính: model, API kho/quỹ, IAM, approval, idempotency, worker, activity, tích hợp, đối soát, báo cáo, repository HTTP và luồng tạo/duyệt của Flutter. Đã đối chiếu các đường ghi trọng yếu của Worker với FastAPI và đọc tài liệu nền.

Đây **không phải chứng nhận đã đọc từng dòng của mọi source/test/platform runner**. Một số màn Flutter, test và hạ tầng AI mới được khảo sát cấu trúc hoặc theo đoạn liên quan. Chưa chạy app để kiểm tra hình ảnh, chưa kiểm thử thiết bị, chưa chạy toàn bộ E2E/PostgreSQL hay kiểm tra môi trường cloud. Build sinh sẵn trong `frontend/dist`, dependencies, binary/model và secrets không dùng làm nguồn thiết kế nghiệp vụ.

Kiểm chứng thực tế trong phiên khảo sát: `python3 -m pytest backend/tests/test_approval_controls.py -q` → **7 passed**. Metadata ORM xác nhận bảng `reconciliation_runs`, model `Job` chưa có lease/retry columns và `CashJournal.reversal_of` chưa được khai báo unique trong model. Không suy rộng các kiểm tra này thành kết luận toàn hệ thống đã đạt.

## Quyết định đề xuất để bắt đầu

1. Dùng FastAPI làm nơi thực thi nghiệp vụ chuẩn; chuyển Worker về vai trò gateway/proxy khi contract đã kiểm chứng. Không chuyển traffic trong đợt tài liệu này.
2. Sửa danh tính, quyền theo đối tượng, chống ghi trùng và transaction trước khi mở rộng giao diện.
3. Lấy “Việc của tôi”, “Phiếu”, “Duyệt”, “Kho”, “Quỹ mô phỏng”, “Đối soát” làm trục công việc của nhân viên.
4. Pilot một đơn vị, dữ liệu giả, hai người tạo/duyệt độc lập; chỉ mở rộng sau nghiệm thu có bằng chứng.

Tài liệu nền trước đó: [quyết định](../00-decisions.md), [PRD](../01-prd.md), [kiến trúc](../03-architecture.md), [workflow](../05-workflows.md). Khi có khác biệt, dùng **01** để hiểu hiện trạng và **02–04** để hiểu đề xuất; không coi mô tả cũ là bằng chứng tính năng đã hoàn tất.
