# Finish Remaining Work Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hoàn thành sạch mọi việc tồn của BankOps: verify Flutter, bottom-bar theo role, xuất Excel/PDF thật, timeline audit chi tiết phiếu.

**Architecture:** Chỉ sửa Flutter + Makefile; backend FastAPI giữ nguyên (101 tests xanh). Mỗi work-package độc lập, merge được riêng. Không thêm dep ngoài WP-C.

**Tech Stack:** Flutter 3.4+ / Material 3, `excel` + `printing` (chỉ WP-C), `flutter_test`, Makefile.

**Spec:** Yêu cầu đã duyệt qua chat (đợt A–D) + tồn đọng: (1) `flutter analyze/test` chưa chạy được vì máy không có SDK; (2) bottom-bar compact vẫn hiện slot Yêu cầu cho auditor; (3) xuất CSV tạm, cần Excel/PDF thật; (4) chưa có timeline audit trên chi tiết phiếu; badge Duyệt đã có ở rail/topbar (agent song song làm), chỉ thiếu ở bottom-bar.

## Global Constraints

- Flutter SDK floor: `>=3.4.0 <4.0.0` (theo `frontend/pubspec.yaml:6-7`).
- Mọi thao tác ghi vẫn qua Maker ≠ Checker + `Idempotency-Key`; UI không tự ghi sổ.
- Không commit secret; dữ liệu luôn giả lập (`simulation: true`).
- Verify mỗi task: `flutter analyze` 0 error + `flutter test <file>` xanh (cần SDK; chưa có SDK thì ghi `BLOCKED: no SDK`, cấm claim pass).
- Chạm `app_shell.dart` phải đọc lại toàn file trước (agent song song đang sửa).

---

## Work-package A — Verify Flutter ✅ DONE (2026-10-14)

Kết quả: SDK có sẵn (Flutter 3.47.7) → `flutter analyze` **No issues found!** · `flutter test` **69/69 passed**.
Suite tăng 28 → 69 test kể từ 13/10. Không có test đỏ ⇒ Task A3 no-op.
Chi tiết: `tasks/notes/verify-flutter.md`.

### Task A1: Cài Flutter SDK + chạy analyze

**Files:**
- Modify: none (môi trường)

**Interfaces:**
- Consumes: none
- Produces: `flutter --version` >= 3.4.0, bản `flutter analyze` baseline

- [x] **Step 1: Cài SDK** — Flutter 3.47.7 / Dart 3.13.5 (brew cask) đã có sẵn.
- [x] **Step 2: Chạy analyze** → `No issues found!` (0 error, 0 warning).

### Task A2: Chạy full test suite Flutter

**Files:**
- Test: `frontend/test/` (8 file: widget_test, import_preview, reports_chart, http_repository, bulk_approve, global_search, dashboard_roles + 1)

**Interfaces:**
- Consumes: Task A1 (SDK sẵn)
- Produces: danh sách test đỏ (nếu có) để sửa

- [x] **Step 1: Chạy tests** → **69/69 passed** (xem bảng per-file trong `tasks/notes/verify-flutter.md`).
- [x] **Step 2: Ghi kết quả vào `tasks/notes/verify-flutter.md`** — đã ghi (Run 1 13/10 + Run 2 14/10).

### Task A3: Sửa đỏ do đợt A–D gây ra (nếu có)

**Files:**
- Modify: file test/code theo lỗi Task A2 ghi nhận
- Test: rerun file lỗi

**Interfaces:**
- Consumes: danh sách đỏ Task A2
- Produces: `flutter test` xanh 100%

- [x] **Step 1: Sửa từng lỗi** — không có test đỏ nào ⇒ no-op.
- [x] **Step 2: Verify** → `flutter test` 69/69 + `flutter analyze` 0 issue.
Expected: PASS + 0 error.

---

## Work-package B — Bottom-bar compact theo role + badge ✅ DONE (2026-10-13)

Kết quả: `flutter test` 20/20 + `flutter analyze` 0 issues.
Làm thêm ngoài plan: topbar responsive (ẩn refresh/theme/settings + tên/role ở màn <600px, title ellipsis) vì test compact phát hiện tràn 226px → 10px → 0.

### Task B1: Ẩn slot Yêu cầu với auditor + badge Duyệt ở bottom-bar

**Files:**
- Modify: `frontend/lib/src/app/app_shell.dart` (đọc lại `_bottomBar`, `_bottomSelected` trước — agent song song vừa đổi signature)
- Test: `frontend/test/dashboard_roles_test.dart` (thêm case compact)

**Interfaces:**
- Consumes: `RoleVisibility.visibleTabs/isAuditorOnly` (`core/util/role_visibility.dart`), `_pendingApprovalCount` (đã có trong AppShell)
- Produces: bottom-bar chỉ hiện slot được phép + badge số chờ duyệt

- [ ] **Step 1: Viết failing test (compact auditor)**
```dart
testWidgets('Compact auditor bottom bar hides requests slot', (tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  // pump AppShell + SessionScope(user: auditor ...) như dashboard_roles_test.dart
  // ...
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('nav-bottom-requests')), findsNothing);
  expect(find.byKey(const Key('nav-bottom-more')), findsOneWidget);
});
```
- [ ] **Step 2: Chạy, xác nhận FAIL**
Run: `flutter test test/dashboard_roles_test.dart`
Expected: FAIL ở case mới (`nav-bottom-requests` vẫn thấy).
- [ ] **Step 3: Implement tối thiểu** — trong `_bottomBar({session})`: dựng slot3 = Duyệt nếu `canApprove`, = Yêu cầu nếu `canCreate`, else = Hoạt động; gắn badge `_pendingApprovalCount` cho slot Duyệt. Giữ nguyên key các slot còn lại.
- [ ] **Step 4: Verify**
Run: `flutter test test/dashboard_roles_test.dart && flutter analyze`
Expected: PASS + 0 error.
- [ ] **Step 5: Commit**
```bash
git add BankOps/frontend/lib/src/app/app_shell.dart BankOps/frontend/test/dashboard_roles_test.dart
git commit -m "feat: role-aware compact bottom bar with approval badge"
```

---

## Work-package C — Xuất Excel/PDF thật ✅ DONE (2026-10-13)

Kết quả: `flutter test` 25/25 + `flutter analyze` 0 issues. Deps thêm: `excel ^4.0.6`, `printing ^5.14.3`, `pdf ^3.12.0`.
Lưu ý: font PDF built-in thiếu glyph TV → text PDF qua `VnAscii.strip` (không dấu); XLSX giữ nguyên tiếng Việt có dấu. XLSX trên Web fallback về Sao chép CSV (không có FileSaver).

### Task C1: Thêm dep + nút Xuất Excel ở 3 tab Báo cáo

**Files:**
- Modify: `frontend/pubspec.yaml` (thêm `excel: ^4.0.0`), `reports/widgets/inventory_chart.dart`, `cashflow_chart.dart`, `stagnation_list.dart`
- Test: `frontend/test/report_export_test.dart` (mới)

**Interfaces:**
- Consumes: `CsvExport.encode` (giữ làm fallback), DTOs `report_dtos.dart`
- Produces: file `.xlsx` tải về (Web) / share (mobile) qua `file_saver`? KHÔNG thêm file_saver — dùng `printing` share có sẵn ở Task C2. Task này chỉ xong phần tạo bytes + test.

- [ ] **Step 1: Viết failing test**
```dart
test('ReportExcel.encodeInventory produces non-empty xlsx bytes', () {
  final bytes = ReportExcel.encodeInventory([InventoryBucket(bucket: '2026-10-01', inboundQty: '10', outboundQty: '4', netQty: '6', receiptCount: 1, issueCount: 1)]);
  expect(bytes.isNotEmpty, true);
});
```
- [ ] **Step 2: Chạy, xác nhận FAIL** (`ReportExcel` chưa tồn tại)
- [ ] **Step 3: Tạo `lib/src/core/util/report_excel.dart`** (pure-Dart, dùng package `excel`; headers khớp CSV hiện tại)
- [ ] **Step 4: Verify** `flutter test test/report_export_test.dart`
- [ ] **Step 5: Commit**

### Task C2: Share/print qua package printing + nút In phiếu

**Files:**
- Modify: `frontend/pubspec.yaml` (thêm `printing: ^5.0.0`), 3 widget báo cáo (gắn nút), `approvals_screen.dart` (nút In phiếu → PDF 1 trang)
- Test: mở rộng `report_export_test.dart` (mock share, chỉ assert không crash)

**Interfaces:**
- Consumes: `ReportExcel` (Task C1)
- Produces: nút `export-*-xlsx-btn`, `print-approval-*-btn`

- [ ] **Step 1–5:** TDD như Task C1 (test → fail → code → pass → commit). Verify: `flutter test test/report_export_test.dart && flutter analyze`.

---

## Work-package D — Timeline audit chi tiết phiếu ✅ DONE (2026-10-13)

Kết quả: `flutter test` 28/28 + `flutter analyze` 0 issues.
Khác plan: không có detail sheet sẵn → gắn nút lịch sử trên mỗi thẻ phiếu, mở bottom-sheet `RequestTimeline` (lọc `getActivity()` theo `subjectId`, sort thời gian, vẽ dot-line, nhãn TV cho 8 messageKey).

### Task D1: Đọc activity theo phiếu + UI timeline

**Files:**
- Modify: `frontend/lib/src/features/requests/requests_screen.dart` (đọc lại trước — file đang được agent khác sửa), thêm `features/requests/request_timeline.dart` (mới)
- Test: `frontend/test/request_timeline_test.dart` (mới)

**Interfaces:**
- Consumes: `BankOpsRepository.getActivity()` (lọc client-side theo `subjectId == requestId`), `ActivityEvent` DTO
- Produces: widget `RequestTimeline(requestId)` hiển thị created → submitted → approved/rejected theo thời gian

- [ ] **Step 1: Viết failing test** — pump `RequestTimeline(requestId: 'sr-0002')` với Fake repo, expect thấy 2+ mốc (created/submitted).
- [ ] **Step 2: Chạy, xác nhận FAIL**
- [ ] **Step 3: Tạo `request_timeline.dart`** — FutureBuilder `getActivity()`, lọc `subjectId`, sort `occurredAt`, render TimelineTile tự vẽ (không thêm dep): dot + line + label + relative time.
- [ ] **Step 4: Gắn vào detail sheet màn Requests** (nút/section "Lịch sử", key `request-timeline-sr-0002`).
- [ ] **Step 5: Verify** `flutter test test/request_timeline_test.dart && flutter analyze`
- [ ] **Step 6: Commit**

---

## Self-review (đã chạy)

1. **Spec coverage:** verify SDK (A) → bottom-bar (B) → Excel/PDF (C) → timeline (D) + badge Duyệt đã có sẵn (không plan trùng). Đủ.
2. **Placeholder scan:** không có TBD/TODO; mọi step có file + lệnh + expected cụ thể.
3. **Type consistency:** key/test/DTO dùng đúng tên đã có (`nav-bottom-*`, `InventoryBucket`, `ActivityEvent.subjectId`, `RoleVisibility.visibleTabs`).

## Tradeoffs (ghi nhận, chi tiết ở `tasks/notes/`)

- ~~Mọi task Flutter BLOCKED tới khi có SDK~~ → **đã giải quyết 14/10**: SDK có sẵn, WP-A verify xanh (69/69).
- WP-C thêm 2 dep (`excel`, `printing`): tăng dung lượng build Web ~1-2MB, chấp nhận vì auditor/checker cần file thật.
- Timeline lọc client-side (không API mới): đủ cho demo scale, backend giữ nguyên.

## Trạng thái tổng (2026-10-14)

| Work-package | Trạng thái |
|---|---|
| A — Verify Flutter | ✅ DONE (69/69, analyze 0) |
| B — Bottom-bar theo role | ✅ DONE (13/10) |
| C — Xuất Excel/PDF | ✅ DONE (13/10) |
| D — Timeline audit phiếu | ✅ DONE (13/10) |

⇒ **Toàn bộ plan đã xong.** Cổng kiểm tra đầy đủ: backend 232 passed + ruff clean, Flutter 69/69 + analyze 0, worker tsc/lint 0, secrets guard pass, compose config ok.
