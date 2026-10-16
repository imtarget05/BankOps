# TDD evidence — Quầy kiểm kê theo ca

## Nguồn yêu cầu

Yêu cầu nội bộ: dựng khung màn quầy kiểm kê riêng, có các ca Sáng, Chiều và
Lỡ; hiển thị tồn đầu, nhập, sử dụng, tồn lý thuyết, kiểm thực tế, độ lệch và
trạng thái đối soát mà không thay thế luồng kiểm kê hiện hữu.

## User journeys

- Nhân viên quầy chọn một ca để xem khung thời gian và số tồn cần chốt.
- Nhân viên thấy công thức tồn lý thuyết và chênh lệch giữa số thực tế với số
  phần mềm trước khi gửi duyệt.
- Quản lý vẫn có thể dùng danh sách/chi tiết kiểm kê cũ và mở phiên mới.

## RED → GREEN

| Hạng mục | RED | GREEN | Bảo đảm |
|---|---|---|---|
| Widget quầy kiểm kê | `flutter test test/shift_stocktake_desk_test.dart` lỗi vì chưa có `shift_stocktake_desk.dart` | cùng lệnh đạt 1/1 | Có 3 ca, bảng 10 cột và trạng thái chênh lệch |
| Gắn màn kho | `flutter test test/stock_levels_and_stocktake_test.dart` không tìm thấy `Quầy kiểm kê theo ca` | lệnh test hai tệp đạt 2/2 | Khung mới xuất hiện trong InventoryScreen, không phá luồng tạo/duyệt cũ |

## Coverage và giới hạn

Hai widget test kiểm tra các hành vi mới trực tiếp. Chưa có số phần trăm
coverage toàn dự án; các cảnh báo lint còn lại thuộc mã cũ và không có lỗi
analyze.

## Commit checkpoints

Không tạo commit TDD riêng vì worktree đã có thay đổi chưa commit từ các hạng
mục khác; tránh gom hoặc ghi đè thay đổi của người dùng/agent khác.
