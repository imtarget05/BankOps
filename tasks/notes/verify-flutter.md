# Verify Flutter (WP-A)

## Run 1 — 2026-10-13 (WP-A → WP-D)

- SDK: Flutter 3.47.7 / Dart 3.13.5 (brew cask, khớp pubspec `>=3.4.0 <4.0.0`)
- Cuối đợt: `flutter analyze`: **No issues found!** · `flutter test`: **28/28 passed**
  - report_export (5: excel round-trip x3, pdf header, vn-ascii)
  - request_timeline (3: có sự kiện, rỗng, mở sheet từ Requests)
  - + 20 tests cũ (đợt A–C) vẫn xanh.

## Run 2 — 2026-10-14 (re-verify sau khi deploy cloud)

Máy đã có SDK ⇒ WP-A không còn BLOCKED.

- `flutter analyze` → **No issues found!** (2.3s) — 0 error, 0 warning
- `flutter test` → **69/69 passed** (10s), 0 failed, 0 skipped
- Suite đã tăng **28 → 69 test** kể từ 13/10 (thêm IAM admin, security settings, AI dual-control/voucher-audit, ETL studio, stock levels, auto-complete, trust metrics, meeting report, denomination dialog, approvals role visibility).

### Per-file (Run 2)

| test file | passed | failed |
|---|---|---|
| ai_risk_dual_control_test.dart | 2 | 0 |
| ai_voucher_audit_test.dart | 8 | 0 |
| approvals_role_visibility_test.dart | 4 | 0 |
| bulk_approve_test.dart | 2 | 0 |
| dashboard_roles_test.dart | 6 | 0 |
| dashboard_trust_metrics_test.dart | 2 | 0 |
| denomination_dialog_test.dart | 1 | 0 |
| etl_studio_screen_test.dart | 3 | 0 |
| global_search_test.dart | 2 | 0 |
| http_repository_test.dart | 5 | 0 |
| iam_admin_screen_test.dart | 2 | 0 |
| import_preview_test.dart | 1 | 0 |
| meeting_report_test.dart | 3 | 0 |
| report_export_test.dart | 5 | 0 |
| reports_chart_test.dart | 1 | 0 |
| request_timeline_test.dart | 3 | 0 |
| requests_autocomplete_test.dart | 4 | 0 |
| security_settings_test.dart | 10 | 0 |
| stock_levels_and_stocktake_test.dart | 1 | 0 |
| widget_test.dart | 4 | 0 |
| **Tổng** | **69** | **0** |

**Kết luận WP-A (A1/A2/A3): xong** — SDK có, analyze 0 issue, toàn bộ test xanh. Không có test đỏ nào cần sửa (A3 no-op).

## Cổng kiểm tra đầy đủ (2026-10-14)

| Gate | Lệnh | Kết quả |
|---|---|---|
| Backend tests | `pytest -q` (DB QA `:5433`, `APP_ENV=test`) | **232 passed**, 1 skipped, 1 xfailed, 0 failed |
| Backend lint | `ruff check backend/ ai/` | **All checks passed!** |
| Flutter analyze | `flutter analyze` | **No issues found!** |
| Flutter tests | `flutter test` | **69/69 passed** |
| Worker typecheck | `npm run typecheck` | exit **0** |
| Worker lint | `npm run lint` | exit **0** |
| Secrets guard | `python3 scripts/check_no_secrets.py` | **passed** |
| Compose config | `docker compose config` | exit **0** |
