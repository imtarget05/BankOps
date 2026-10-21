# 06 — REST contracts / OpenAPI outline

Base `/api/v1`; JSON UTF-8; UTC ISO-8601; UUID string; money decimal as string (`"150000.00"`), quantity decimal as string. FastAPI sinh `/openapi.json` từ schema được test snapshot. Auth Bearer token demo; cookie secure/httpOnly có thể chọn cho web theo threat model. Mọi write có `X-Request-ID`; create/submit/approve/post-like commands cần `Idempotency-Key` UUID, state transitions cần `If-Match: <version>`.

## Endpoints

| Method/path | Permission | Nội dung |
|---|---|---|
| POST `/auth/login`, POST `/auth/refresh`, POST `/auth/logout`, GET `/me` | public/session | phiên demo, roles, capabilities |
| POST `/auth/google` `{"id_token": "..."}` | public | Google Sign-In: verify ID token (aud = client ID), upsert user theo email (lần đầu = signup role `staff`), trả access/refresh JWT + `is_new_user`; lỗi theo envelope |
| GET `/inventory/items`, `/inventory/locations`, `/inventory/balances`, `/inventory/assets` | inventory.read | filter/paginate |
| POST `/inventory/requests`, GET `/inventory/requests/{id}` | inventory.write/read | draft |
| POST `/inventory/requests/{id}/submit` | owner | pending |
| POST `/inventory/requests/{id}/approve`, `/reject` | inventory.approve | decision; checker khác maker |
| GET `/inventory/movements` | inventory.read | ledger kho |
| GET `/cash-sim/boxes`, `/cash-sim/balances`, `/cash-sim/journals` | cash.read | luôn DEMO |
| POST `/cash-sim/requests`, GET `/cash-sim/requests/{id}` | cash.write/read | draft |
| POST `/cash-sim/requests/{id}/submit`, `/approve`, `/reject` | owner/cash.approve | state transition |
| GET `/approvals/inbox` | *.approve | pending, loại, maker |
| GET `/activity`, GET `/events/stream?cursor=` | session | feed + SSE |
| POST `/integrations/connections`, POST `/integrations/connections/{id}/test`, POST `/integrations/connections/{id}/schema`, GET `/integrations/connections/{id}` | integration.admin | sandbox connector |
| GET `/integrations/connections`, GET `/integrations/runs`, GET `/integrations/runs/{id}`, GET `/integrations/runs/{id}/preview`, POST `/integrations/{id}/runs` | integration.admin | job/preview + connection list |
| POST `/integrations/uploads`, POST `/integrations/google-sheets/fetch`, POST `/integrations/webhooks/{id}` | integration.admin | ingest CSV/JSON/Sheets/webhook -> staging |
| POST `/integration-runs/{id}/confirm` | integration.admin | tạo draft từ staging, không post |
| POST `/reconciliations`, GET `/reconciliations/{id}` | operator/auditor | chạy/xem |
| GET `/audit-events` | audit.read | lọc; không edit |
| GET `/health/live`, `/health/ready` | infra | readiness DB/worker tùy ngữ cảnh |
| POST `/ai/reorder-point`, POST `/ai/anomaly` | inventory.read | tối ưu điểm đặt hàng + phát hiện bất thường nhu cầu (Phase 2) |

Pagination `limit` 1..100 + opaque `cursor`; filter có whitelist; sort ổn định `created_at,id`. Không trả raw secret, password hash hoặc raw exception.

## Request/response mẫu

```http
POST /api/v1/cash-sim/requests
Idempotency-Key: 59c39c65-b6a9-4b47-afb9-70404f4b6c64
Content-Type: application/json

{"cashbox_id":"11111111-1111-4111-8111-111111111111","kind":"payment","amount":"250000.00","reason":"Chi phí demo"}
```

```json
{"id":"22222222-2222-4222-8222-222222222222","status":"draft","version":1,"simulation":true,"currency":"VND"}
```

```json
{"error":{"code":"SELF_APPROVAL_FORBIDDEN","message":"Người tạo không được tự duyệt","request_id":"...","details":{}}}
```

Response mẫu integrations (staging preview, không còn `simulation: true`):

```json
{"run_id":"uuid","status":"staged","deduplicated":false,"fingerprint":"sha256...","valid_count":1,"invalid_count":0,"rows":[...],"mapping_version":1}
```

Response mẫu AI forecasting (Phase 2):

```http
POST /api/v1/ai/reorder-point
Authorization: Bearer <token>
Content-Type: application/json

{"forecast_values":[40,50,60,50,45,55,50,45,55,50],"lead_time_days":7,"service_level":0.95,"current_stock":100}
```

```json
{"reorder_point":373.84,"safety_stock":23.84,"avg_daily_demand":50.0,"std_demand":5.4772,"z_score":1.6449,"lead_time_days":7.0,"service_level":0.95,"needs_order":true,"suggested_order_quantity":273.84,"current_stock":100.0,"risk_level":"critical"}
```

```http
POST /api/v1/ai/anomaly
Authorization: Bearer <token>
Content-Type: application/json

{"actual_demand":200,"expected_demand":100,"std_demand":10}
```

```json
{"is_anomaly":true,"z_score":10.0,"direction":"spike","severity":"high","expected_demand":100.0,"actual_demand":200.0,"threshold_z":2.5,"reason":"Demand 10.00σ above expected (spike)"}
```

Connection detail trả về schema, last_tested_at, last_error:

```json
{"id":"conn-uuid","type":"google_sheets","name":"My Sheet","status":"pending_test","schema":[...],"last_tested_at":null,"last_error":null}
```

`POST /connections/{id}/test`: kiểm tra kết nối thời gian thực, cập nhật status/last_tested_at:

```json
{"connection_id":"uuid","ok":true,"tested_at":"2025-01-01T00:00:00Z","status":"connected","error":null}
```

`POST /connections/{id}/schema`: quét cột từ Google Sheets/CSV, lưu schema_json:

```json
{"connection_id":"uuid","schema":[{"name":"sku","index":0},...],"tested_at":"2025-01-01T00:00:00Z"}
```

Status: 200 read/transition, 201 create, 202 queued job, 400 validation syntax, 401 unauthenticated, 403 forbidden, 404 not found, 409 state/version/idempotency conflict, 422 schema validation, 429 rate limit, 503 dependency unavailable. `POST /approve` trả 200 với trạng thái `posted`, không trả 202 khi DB chưa post.

## SSE contract

`GET /events/stream?cursor=<last_event_id>`; `text/event-stream`, `id`, `event: job.updated|activity.created|heartbeat`, `data` JSON `{event_id, occurred_at, subject_id, status, processed, total, message_key}`. Server replay theo cursor trong cửa sổ retention, client dùng `Last-Event-ID` khi reconnect rồi GET REST để đồng bộ. Không gửi token trong URL; xác thực header/cookie. Nếu cursor quá cũ, gửi `resync_required` và client tải lại REST.

## Nghiệp vụ ca trà sữa (pilot — bao phủ bởi test_tea_shift_regression)

| Method/path | Permission | Nội dung |
|---|---|---|
| POST `/inventory/stocktakes` | inventory.write | mở ca theo `location_id` + `shift_code` (morning/afternoon/split) + `business_date`; 1 ca/kho/ngày, chống trùng 409 `SHIFT_ALREADY_OPEN`; tự seed dòng + `opening_qty` kế thừa từ ca bàn giao trước |
| GET `/inventory/stocktakes`, `/inventory/stocktakes/{id}` | inventory.read | danh sách/chi tiết ca kèm `opening_qty, received_qty, used_qty, theoretical_qty, counted_qty, variance` |
| PUT `/inventory/stocktakes/{id}/lines` | inventory.write (maker) | chỉ nhập `used_qty` + `counted_qty`; hệ thống tính `theoretical = opening + received - used`, `variance = counted - theoretical`; ca đã chốt trả 409 `STOCKTAKE_LOCKED` |
| POST `/inventory/stocktakes/{id}/submit`, `/approve` | owner / inventory.approve (+`Idempotency-Key`) | chốt ca; approve tạo Phiếu điều chỉnh tự động khi lệch ≠ 0; maker ≠ checker |
| POST `/inventory/requests` `kind=receipt` | inventory.write | thêm `supplier`, `received_at`; dòng `unit_price` (thành tiền tự tính), `lot_no`, `expiry_date`; HSD < ngày nhận → 422 `EXPIRED_LOT` |
| GET `/inventory/low-stock-alerts` | inventory.read | tồn cuối ≤ Min → đỏ, cần đặt hàng (`rule: quantity <= min_qty`) |
| GET `/inventory/expiry-alerts?days=7` | inventory.read | cảnh báo HSD theo lô: critical ≤ 0 ngày, warning 1–3, watch 4–7 |
| GET `/reports/consumption-top?date_from=&date_to=&limit=10` | inventory.read/audit | Top nguyên liệu tiêu hao (tổng `used_qty` ca + movement xuất) |
| GET `/reports/shift-history?date_from=&date_to=&shift_code=` | inventory.read/audit | lịch sử chốt ca: ngày, ca, kho, người chốt, số dòng lệch, tổng lệch tuyệt đối |

