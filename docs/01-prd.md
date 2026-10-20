# 01 — PRD và phạm vi

> **Domain hiện tại (pilot 10/2026):** Ứng dụng quản lý Nhập–Xuất–Tồn cho quán trà sữa
> theo [SRS_QUAN_LY_KHO_TRA_SUA.md](SRS_QUAN_LY_KHO_TRA_SUA.md). Module Quỹ/Tích hợp/Đối soát
> (thuật ngữ/luồng legacy từ giai đoạn BankOps) được **ẩn khỏi UI** nhưng giữ
> nguyên backend để rollback. Chúng chỉ là financial-operations simulation,
> không phải core-banking hay tích hợp ngân hàng.

## Mục tiêu

Nhân viên pha chế/trưởng ca và quản lý theo dõi nguyên liệu theo từng ca làm việc trên mobile/tablet và web; mở ca, ghi nhận nhập hàng, nhập tiêu hao, chốt tồn cuối ca, nhận cảnh báo tồn thấp/cận date; quản lý duyệt Phiếu nhập và Phiếu điều chỉnh kiểm kê. Không có giao dịch tiền thật.

## Vai trò và nhu cầu

| Vai trò | Nhu cầu |
|---|---|
| Nhân viên/Trưởng ca (staff) | đăng nhập quầy, mở ca theo kho/ngày, ghi nhận hàng nhập trong ca, nhập `Sử dụng` + `Kiểm kê thực tế`, chốt ca, báo cáo hư hỏng, tạo Phiếu điều chỉnh kiểm kê |
| Quản lý (admin/manager) | danh mục nguyên liệu 5 nhóm + Min/Max, duyệt Phiếu nhập/điều chỉnh, cảnh báo tồn thấp & cận date, báo cáo xuất–nhập–tồn, Top tiêu hao, lịch sử chốt ca theo nhân viên |
| Auditor | xem audit, báo cáo chỉ đọc |

## Luồng chính

1. Trưởng ca sáng mở Ca Sáng (07:30–15:00) → tồn đầu tự lấy từ tồn cuối ngày trước.
2. Trong ca: ghi nhận hàng nhập (lô + HSD + đơn giá) → cộng vào cột Nhập hàng.
3. Kết thúc ca: nhập `Sử dụng` → hệ thống tính `Còn lại = (Tồn đầu + Nhập) − Sử dụng` → nhập `Kiểm thực tế` → hệ thống tính `Độ lệch`.
4. Chốt ca → ca bị khóa; bàn giao Ca Chiều (15:00–23:00) tự mang tồn đầu từ thực tế ca sáng; Ca Lỡ (07:30–18:00) ghi nhận độc lập.
5. Tồn cuối ≤ Min → đỏ + cảnh báo; HSD ≤ 7 ngày → vàng/đỏ; lệch ≠ 0 → báo động ngay trên màn hình.
6. Sửa số liệu đã chốt chỉ qua Phiếu điều chỉnh kiểm kê do Quản lý duyệt.

## Yêu cầu chức năng MVP

- Danh mục 5 nhóm nguyên liệu (Trà, Bột & Sữa, Topping, Syrup & Mứt, Bao bì); SKU, đơn vị, quy cách; Min/Max theo từng kho.
- Phiếu nhập: NCC, thời điểm nhận, đơn giá + thành tiền, số lô, HSD (validate HSD ≥ ngày nhận).
- Kiểm kê 3 ca: 1 ca/kho/ngày; chống mở trùng (409 `SHIFT_ALREADY_OPEN`); khóa sau chốt (409 `STOCKTAKE_LOCKED`).
- Cảnh báo: tồn thấp `qty <= Min`, cận date theo lô, chênh lệch ca; sự kiện outbox + SSE cho màn quản lý.
- Báo cáo: xuất–nhập–tồn ngày/tuần/tháng, Top tiêu hao, lịch sử chốt ca theo nhân viên.
- RBAC 2 nhóm vai trò, audit append-only, idempotency cho approve, maker ≠ checker.
- Offline: nhập liệu/chốt ca lưu cục bộ + outbox đồng bộ (kế hoạch Phase 6).

## Chất lượng và giới hạn

- Responsive 360 / 768 / 1280 px; nút chạm ≥ 48dp tại quầy.
- API p95 < 500 ms cho đọc thông thường trên dữ liệu demo.
- Mọi thay đổi có trace ID; mọi write có audit + outbox cùng transaction.
- Không secret ra client/log; dữ liệu demo là mô phỏng.

## Chỉ số chấp nhận

100% thay đổi tồn được duyệt khác người và ghi đúng một movement; ca chốt không sửa được ngoài phiếu điều chỉnh; mở trùng ca bị chặn; retry không nhân đôi; tồn thấp/cận date hiển thị đúng ngưỡng; luồng chính chạy trên iOS simulator và web.

