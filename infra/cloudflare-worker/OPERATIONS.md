# Cloudflare vận hành: Quản Lý Kho Trà Sữa

## Thành phần

| Thành phần | Tên | Vai trò |
|---|---|---|
| Public asset Worker | `quan-ly-kho-tra-sua` | Phục vụ Flutter web; Logs 25%, Traces 5%. |
| Background Worker | `quan-ly-kho-tra-sua-background` | Consumer không public, ghi nhận event nền đã được allow-list. |
| Queue | `quan-ly-kho-tra-sua-events` | Event đồng bộ, cảnh báo tồn, yêu cầu xuất báo cáo. |
| Dead-letter queue | `quan-ly-kho-tra-sua-events-dlq` | Giữ message sai schema hoặc lỗi sau 5 lần thử để kiểm tra. |
| Cache | CDN cache | `assets/*` và CanvasKit immutable 1 năm; HTML/bootstrap luôn revalidate. |

## Triển khai

1. Trong Cloudflare Dashboard → **Workers & Pages → Queues**, tạo hai queue đúng tên ở bảng trên.
2. Deploy consumer:

   ```bash
   cd infra/cloudflare-worker
   npx wrangler deploy --config wrangler.background.toml
   ```

3. Deploy lại public asset Worker để áp dụng Logs/Traces:

   ```bash
   npx wrangler deploy --config wrangler.tea-inventory.toml
   ```

## Vận hành an toàn

- Không gửi JWT, mật khẩu, OTP, email, hoặc chi tiết phiếu kho vào Queue/log/trace.
- Queue chỉ nhận metadata `event_type`, `event_id`, `occurred_at`, `correlation_id`.
- FastAPI vẫn là API nghiệp vụ duy nhất; Queue không được dùng để ghi trực tiếp tồn kho.
- Xem Workers Logs để lọc theo `event=queue.processed`; dùng Traces để xác định request/binding chậm.
- Nếu có lỗi hàng loạt, tạm dừng producer trước; kiểm tra DLQ và phát lại bằng một quy trình có idempotency.
