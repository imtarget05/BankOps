# QA_PLAN.md — Kho Trà Sữa (QuanLyKho / MilkTea Ops)

**Vị trí lưu:** `/Users/mainguyenbinhtan/Downloads/QuanLyKho/docs/QA_PLAN.md`  
**Mục tiêu:** Kế hoạch kiểm thử chất lượng (QA) sản xuất cho backend FastAPI + SQLAlchemy 2.x + Alembic + PostgreSQL 16 và frontend Flutter 3.24+ của hệ thống quản lý kho nguyên liệu trà sữa.  
**Người phụ trách:** QA Lead / Test Architect  
**Ngày:** 22/10/2026

---

## 1. Test Strategy (Chiến lược kiểm thử)

### 1.1 Mục tiêu QA
1. **Tính đúng của dữ liệu kho:** tồn kho (Balance/LotBalance) luôn chính xác sau nhập/xuất/chuyển/kho kiểm kê; không bao giờ âm; FEFO đúng thứ tự HSD.
2. **Xử lý lỗi:** 409 INSUFFICIENT_STOCK khi hết hàng, balance giữ nguyên; 422 EXPIRED_LOT khi HSD trước ngày nhập; 403 SELF_APPROVAL_FORBIDDEN khi tự duyệt; 409 SHIFT_ALREADY_OPEN khi ca trùng.
3. **Vận hành chính xác:** luồng maker-checker (4 mắt), chốt ca (shift lock), cổng PIN kiểm soát viên (≥50 phôi), audit events + outbox trong cùng transaction.

### 1.2 Phạm vi kiểm thử
| Phân hệ | Các kịch bản chính |
|---|---|
| Nhập kho (receipt) | multiline lot/HSD, weighted average cost, quy đổi đơn vị, sync ca kiểm kê mở |
| Xuất/Chuyển (issue/transfer) | FEFO deduction + row lock, loại trừ lô hết hạn (trừ spoilage), 409 hết tồn, 2 movement trong 1 transaction, LotBalance lan truyền kho đích |
| Kiểm kê / Chốt ca (stocktake/shift) | 1 ca mở mỗi (location, business_date, shift_code), khung giờ 3 ca, theoretical_qty tính server-side, variance → adjustment request, maker != checker |
| Maker-checker / RBAC | demo_auditor chỉ-read (200), không tạo/duyệt (403), dữ liệu theo chi nhánh, cổng PIN + rate limit 5/15 phút |
| Cảnh báo (alerts) | tồn thấp (≤ min_qty → critical), hạn dùng (days_left ≤ window → watch/warning/critical), đọc từ LotBalance |
| Demo flow | POST /demo/reset (chỉ demo mode, 404 ngoài, 401 không token), luồng đầy đủ nhập→xuất→kiểm kê→chốt ca, data resettable |

### 1.3 Mô hình tháp kiểm thử (Test Pyramid)
```
        E2E (Flutter + demo flow script)      ← ít nhất, chạy sau release
        │
   Integration (PostgreSQL tạm, docker-compose.test.yml)
        │
        Unit (pytest, domain transitions, decimal, locking)
```

- **Unit (pytest):** transition trạng thái phiếu, số lượng ký hiệu (signed quantity), độ chính xác Decimal, policy phân quyền, hàm trợ trợ (inventory.py helpers).
- **Integration (PostgreSQL thật cô lập qua `docker-compose.test.yml`):** transaction rollback, unique constraint, row lock (`with_for_update`), Alembic upgrade head từ DB trống, outbox + audit trong cùng transaction, idempotency replay.
- **API contract:** OpenAPI schema, mã trạng thái/lỗi, keyset pagination (`next_cursor`), object authorization, idempotency-key.
- **E2E (demo flow script):** luồng reclutera: nhập (có lô/HSD) → xuất FEFO → kiểm kê → chốt ca, reset được.
- **Frontend (Flutter test):** widget/golden có chọn lọc, navigation breakpoint, banner DEMO, lỗi form, trạng thái loading, semantics_accessibility.

### 1.4 Chức năng không chức năng (Non-functional)
| Tiêu chí | Cách kiểm tra |
|---|---|
| RBAC enforcement | Mọi route write yêu cầu capability phù hợp; auditor (inventory:review) chỉ đọc; IDOR chặn (S5) |
| Concurrency (deadlock-free) | `_lock_balances` khóa theo thứ tự cố định `(location_id, item_id)`; transfer A→B và B→A không deadlock |
| Idempotency | Cùng Idempotency-Key + cùng payload → cùng kết quả; khác payload → 409; tối đa 1 post mỗi phiếu |
| Performance (keyset pagination) | `/inventory/balances` limit tối đa 100, duyệt theo `next_cursor` (helper `fetch_all_balances`) |

---

## 2. Môi trường kiểm thử

| Thành phần | Cấu hình |
|---|---|
| **Cơ sở dữ liệu kiểm thử** | PostgreSQL 16 (`postgres:16-alpine`) qua `docker-compose.test.yml`, cổng 5433, DB `bankops_test`, user `bankops`/`bankops`, **tmpfs** (`/var/lib/postgresql/data`), **không named volume** → mỗi lần chạy bắt đầu từ DB trống và dọn sạch sau khi tear-down |
| **Backend toolchain** | Python 3.11+, **Poetry** (`backend/poetry.lock` là canonical), FastAPI `TestClient`, pytest |
| **Migration** | `alembic upgrade head` trên DB trống trước mỗi lần chạy suite |
| **Frontend** | Flutter 3.24+, `flutter test --no-pub`, `flutter analyze` |
| **Demo mode** | `APP_ENV=demo` + `DEMO_MODE=true` (opt-in tường minh, conftest.py setdefault). Ngoài demo mode, `/demo/reset` trả 404 và cổng PIN fail-closed |
| **Cohesion guard (conftest.py)** | `pytest_sessionstart` từ chối chạy mutating test nếu tên DB không chứa `_test` (bảo vệ DB dev/UAT/prod) |

Lệnh chuẩn (Makefile):
```
make test-backend   # docker compose -f docker-compose.test.yml up → alembic upgrade head → pytest tests -q
make test-frontend  # cd frontend && flutter test --no-pub
make analyze-backend# ruff check backend/ ai/ (ruff 0.17.0)
make analyze-frontend# flutter analyze
```

---

## 3. Danh sách test case ưu tiên (P0/P1/P2)

Hằng số tham chiếu (từ `sample-data/` và `test_reviewer_readonly.py`):
- `LOCATION_BAR = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1"` (BAR-MAIN)
- `ITEM_TRA_DEN = "cccccccc-cccc-4ccc-8ccc-ccccccccccc1"` (Trà Đen Lộc Phát Số 9)
- `DEMO_PASSWORD = "DemoPass123!"` (tất cả user demo)
- Vai trò seed: `demo_maker` (staff), `demo_checker` (approver/inventory_manager/admin), `demo_auditor` (auditor), `demo_admin` (admin/inventory_manager/approver/system_admin)

### Nhóm Receipt (nhập hàng)

| ID | Độ ưu tiên | Test case | Kết quả mong đợi |
|---|---|---|---|
| R01 | P0 | Multiline receipt với `lot_no` + `expiry_date`, tính **weighted average cost** (giá vốn bình quân gia quyền) sau approve | 201 create, 200 approve; `item.cost_price` = (old_qty×old_cost + inbound_cost)/(old_qty+total_inbound_base) |
| R02 | P0 | `expiry_date` trước ngày nhận (`receipt_day`) → lỗi **EXPIRED_LOT** | 422, không tạo line/lô |
| R03 | P1 | Quy đổi đơn vị trên receipt (`conversion_rate` > 0) | `quantity_signed = qty × conversion_rate`; `conversion_rate ≤ 0` → 422 INVALID_CONVERSION_RATE |
| R04 | P1 | Tự động sync số lượng nhập vào ca kiểm kê đang mở (`received_qty`, `theoretical_qty`) | StocktakeLine.open có `received_qty` cộng dồn; `book_qty = theoretical_qty` nếu có `shift_code` |
| R05 | P2 | Receipt tạo `LotBalance` mới tại kho đích (lot_no + expiry_date) và `LotMovement` sub_kind=receipt | LotBalance.quantity tăng; có LotMovement gắn lot/expiry |

### Nhóm Issue/Transfer (xuất FEFO)

| ID | Độ ưu tiên | Test case | Kết quả mong đợi |
|---|---|---|---|
| F01 | P0 | **FEFO deduction:** lô HSD sớm nhất trừ trước, `LotBalance` khóa bằng `with_for_update()`, NULL HSD xếp cuối (nulls_last) | Số lượng trừ đúng thứ tự expiry_date ASC; row lock tồn tại |
| F02 | P0 | Lô hết hạn bị **loại trừ** cho xuất sale/internal, **cho phép** cho xuất spoilage | sale/internal raises 422 EXPIRED_LOT_CANNOT_BE_USED nếu chỉ còn lô hết hạn; spoilage xuất được lô hết hạn |
| F03 | P0 | Hết tồn → **409 INSUFFICIENT_STOCK**, balance không thay đổi | reserve/approve trả 409; `Balance.quantity` giữ nguyên sau khi rollback |
| F04 | P1 | Sale/internal yêu cầu số lượng lô không hết hạn ≥ nhu cầu | 422 nếu tổng non-expired < need |
| F05 | P0 | Transfer: tạo **2 Movement rows** trong 1 transaction (source −qty, dest +qty), `LotBalance` lan truyền cùng lot/HSD sang kho đích | 2 movement; LotBalance kho đích tăng cùng lot_no/expiry_date; tổng lượng bảo toàn |
| F06 | P1 | Concurrent issue không để tồn âm (deadlock-free, thứ tự khóa ổn định) | Chạy song song 2 issue cùng item → không deadlock, không tồn âm |
| F07 | P2 | Unit conversion trên xuất (conversion_rate áp dụng qty_base) | Movement.quantity_signed = ±qty × conversion_rate |

### Nhóm Stocktake / Shift lock (kiểm kê / chốt ca)

| ID | Độ ưu tiên | Test case | Kết quả mong đợi |
|---|---|---|---|
| S01 | P0 | Một ca mở duy nhất cho mỗi `(location, business_date, shift_code)` → **409 SHIFT_ALREADY_OPEN** | Lần thứ hai mở cùng khóa trả 409 |
| S02 | P1 | Khung giờ 3 ca: Sáng 07:30–15:00, Chiều 15:00–23:00, Lỡ 07:30–18:00 (`_SHIFT_WINDOWS`) | Các ca tạo được với shift_code đúng;Ca Lỡ độc lập, không thay thế Sáng→Chiều |
| S03 | P0 | `theoretical_qty` tính **server-side** (opening + received − used); client-supplied opening/received bị bỏ qua trong tính toán cuối | theoretical_qty khớp công thức server; variance = counted − book |
| S04 | P1 | Variance = counted − book; approve có variance → tự động tạo adjustment request | Stocktake có adjustment_request_id; audit event ghi nhận |
| S05 | P0 | **maker != checker** (người lập không được tự duyệt, kể cả admin) → **403 SELF_APPROVAL_FORBIDDEN** | Approve bằng chính maker trả 403 |
| S06 | P2 | Chốt ca đóng stocktake; không thể thao tác tiếp trên ca đã chốt | Stocktake.status = closed; các write sau bị chặn |

### Nhóm Maker-checker / RBAC (reviewer mode - S4)

| ID | Độ ưu tiên | Test case | Kết quả mong đợi |
|---|---|---|---|
| M01 | P0 | `demo_auditor` (inventory:review) đọc **tất cả** endpoint chỉ-read kho → **200** | GET /inventory/items, locations, balances, movements, requests, stocktakes, assets, stock-levels, low-stock-alerts, expiry-alerts đều 200 |
| M02 | P0 | `demo_auditor` không thể tạo request → **403** | POST /inventory/requests bằng token auditor trả 403 |
| M03 | P0 | `demo_auditor` không thể tạo stocktake → **403** | POST /inventory/stocktakes bằng token auditor trả 403 |
| M04 | P0 | `demo_auditor` không thể approve submitted request → **403** | POST /inventory/requests/{id}/approve bằng auditor trả 403 |
| M05 | P1 | Dữ liệu theo chi nhánh: user chỉ xem được location trong phạm vi scope (branch-scoped) | GET balances/movements/requests lọc theo `get_accessible_location_ids`; admin trả `None` (xem tất cả) |
| M06 | P1 | IDOR (S5): chỉ chủ sở hữu phiếu mới xoá được draft; người khác 403 dù có `inventory:create_request` | DELETE request của người khác trả 403 |
| M07 | P0 | **Supervisor PIN gate:** issue/transfer tổng qty ≥ 50 yêu cầu `supervisor_pin` | Thiếu PIN → 403; PIN sai → 403; PIN đúng `123456` (demo) → duyệt được |
| M08 | P1 | PIN rate limit: 5 lần sai trong 15 phút → khóa tạm 15 phút | Lần thứ 6 trả 403 "quá 5 lần liên tiếp"; reset sau 15 phút |

### Nhóm Alerts (cảnh báo)

| ID | Độ ưu tiên | Test case | Kết quả mong đợi |
|---|---|---|---|
| A01 | P0 | Low stock: `quantity ≤ min_qty` → **critical** | `/inventory/low-stock-alerts` trả item với severity critical |
| A02 | P1 | Expiry: `days_left ≤ window` → watch/warning/critical, đọc từ `inv_lot_balances` (quantity > 0) | SQL chứa `FROM inv_lot_balances` và `quantity > 0`; phân cấp đúng mức |
| A03 | P2 | Cảnh báo theo phạm vi chi nhánh (không được mở rộng scope) | WHERE clause chứa ALLOWED_LOCATION; không chứa OTHER_LOCATION đơn lẻ |

### Nhóm Demo flow (recruiter walkthrough)

| ID | Độ ưu tiên | Test case | Kết quả mong đợi |
|---|---|---|---|
| D01 | P0 | `POST /demo/reset` không có token → **401** | 401 Unauthorized |
| D02 | P0 | `POST /demo/reset` ngoài demo mode (dù auth admin) → **404** | 404 (fail-closed) |
| D03 | P0 | `POST /demo/reset` ở demo mode + admin token → **200**, gọi `reset_demo_database`, body `status == reset_complete` | 200, data về trạng thái seed gốc |
| D04 | P0 | Luồng đầy đủ: nhập (có lô/HSD) → xuất FEFO → kiểm kê → chốt ca, data resettable | Mọi bước 200/201; tồn kho cuối khớp dự kiến; reset lại được |

**Tổng: 28 test case (P0: 13, P1: 9, P2: 6) — vượt mức yêu cầu tối thiểu 25.**

---

## 4. Test data management

| Thành phần | Chi tiết |
|---|---|
| **File mẫu** | `sample-data/{inventory,users,cash-sim}.json` (gốc repo) + `backend/sample-data/` (sao chép) |
| **Hằng số tiêu dùng** | `LOCATION_BAR` (BAR-MAIN), `ITEM_TRA_DEN` (Trà Đen Lộc Phát Số 9) |
| **Seed roles/users** | `demo_maker`, `demo_checker`, `demo_auditor`, `demo_admin` (mật khẩu `DemoPass123!`); PIN demo `123456` chỉ gán khi `is_demo_mode` |
| **Cách nạp** | `backend/app/seed.py` → `seed_demo()` (idempotent, chặn production); `backend/app/reset_demo_db.py` → `reset_demo_database()` (xoá giao dịch + re-seed) |
| **Cô isolates DB** | Mỗi chạy suite dùng `bankops_test` trên tmpfs; `docker compose ... down -v` sau kết thúc (Makefile `test-backend` có trap tear-down); conftest.py từ chối DB không chứa `_test` |
| **Tuần tự dữ liệu** | Seed trước pytest; không chia sẻ trạng thái giữa test (in-memory rate limit reset giữa các test qua autouse fixture) |

---

## 5. Tự động hóa & CI/CD

### 5.1 Pipeline backend
```
make test-backend
  └─ docker compose -p quanlykho-test -f docker-compose.test.yml up -d --wait
     └─ alembic upgrade head (DATABASE_URL → bankops_test:5433)
        └─ pytest tests -q
```
- **Baseline:** 677 passed / 7 skipped / 1 xfailed (trước khi thêm test mới)
- **Test mới đã có sẵn trong repo:** `test_reviewer_readonly.py` (8 test), `test_inventory_alert_scope_unit.py` (9 test)
- **Linter:** `ruff check backend/ ai/` pin `ruff==0.17.0` (CI), mục tiêu 0 cảnh báo
- **Migration guard:** `alembic upgrade head` từ DB trống phải thành công trước khi pytest

### 5.2 Pipeline frontend
```
make test-frontend   # cd frontend && flutter test --no-pub  (80 tests)
make analyze-frontend # flutter analyze → phải sạch (không lỗi nghiêm trọng)
```

### 5.3 Guard tổng hợp
```
make check-all = check-secrets + analyze-backend + analyze-frontend + typecheck-worker + test-all
```

### 5.4 Lưu ý kỹ thuật (không chặn release)
- `mypy` strict xfailed khoảng 481 annotations → công nợ kỹ thuật, **không chặn release**
- Legacy Worker trên `workers.dev` không tái triển khai; không phải API production (docs/03, docs/14-cloudflare-deploy)

---

## 6. Tiêu chí xuất bản (Definition of Done)

- [ ] Tất cả test **P0 pass** (FEFO đúng, balance không âm, 409/403/422 đúng mã)
- [ ] **RBAC không bypass:** auditor chỉ-read, maker không tự duyệt, IDOR chặn
- [ ] **Demo reset hoạt động:** 401 không token, 404 ngoài demo mode, 200 + reseed ở demo mode
- [ ] **Trang bằng chứng (evidence page) đã cập nhật** sau mỗi release (`docs/EVIDENCE.md` + QA_REPORT.md)
- [ ] **Flutter analyze sạch** (không lỗi nghiêm trọng), `flutter test --no-pub` pass
- [ ] `ruff check` 0 cảnh báo; `alembic upgrade head` từ DB trống thành công
- [ ] Báo cáo KQ kiểm thử đính kèm trong PR (số passed/skipped/failed, thời gian chạy)

---

## 7. Rủi ro & khắc phục

| Rủi ro | Mức độ | Khắc phục |
|---|---|---|
| DB dev tích tụ dữ liệu qua nhiều lần chạy → test lettoi/thất bại do phân trang | Cao | Luôn chạy test trên `bankops_test` (tmpfs, `make test-backend`); dùng helper `fetch_all_balances()` duyệt keyset cursor; reset định kỳ DB dev qua `python -m app.reset_demo_db` |
| `mypy` strict xfailed (~481 annotations) | Trung bình | Công nợ kỹ thuật, theo dõi trong backlog, không chặn release |
| Legacy Worker trên `workers.dev` không tái triển khai | Trung bình | Không đưa vào scope QA production; đánh giá riêng nếu cần |
| Flaky test do dữ liệu chia sẻ / rate limit in-memory | Trung bình | Autouse fixture reset `_login_failures` giữa test; mỗi test tự tạo Idempotency-Key ngẫu nhiên; STOCKTAKE dùng ngày ngẫu nhiên (conftest `open_shift`) tránh trùng 409 |
| E2E phụ thuộc stack Docker đang sống | Cao | Chạy E2E sau khi `docker compose up -d`; không-suất vào `make test-backend` (chạy riêng `verify-live-e2e`) |

---

### Tác vụ kiểm tra (verify) — để thực hiện sau khi lưu file

1. `cd /Users/mainguyenbinhtan/Downloads/QuanLyKho && make test-backend` → mong đợi: 677+ passed, 0 failed (baseline 677/7/1 trước khi thêm test mới)
2. `make analyze-backend` → ruff 0 cảnh báo (ruff 0.17.0)
3. `cd backend && DATABASE_URL="postgresql+psycopg2://bankops:bankops@127.0.0.1:5433/bankops_test" .venv/bin/python -m alembic upgrade head` → thành công từ DB trống
4. `cd frontend && flutter test --no-pub` → pass; `flutter analyze` → sạch
5. Xác nhận file tồn tại: `ls -la docs/QA_PLAN.md`

---

### Mục mở (Open questions) — cần xác nhận với team trước khi release
- Có muốn thêm test stress concurrency cho transfer song song (A→B vs B→A) vào CI không?
- Mức ngưỡng `min_qty` cho alert low stock đã khớp với `sample-data/inventory.json` chưa (min_stock vs min_qty)?
- Frontend Flutter có test case nào đối chiếu với backend alerts/RBAC chưa, hay chỉ kiểm thử widget riêng lẻ?