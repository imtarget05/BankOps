# 05 — Chỉ mục source toàn repo

Chỉ mục tự động từ các file hiện diện ngày 14/10/2026, gồm source chưa commit. Số dòng là số dòng vật lý, không phải độ phủ review. Notebook tính theo JSON nguồn. Không đọc `.env`, secrets, binary/model weights, dependencies hay output build để tạo bảng này.

**Có mặt trong chỉ mục không có nghĩa đã đọc toàn bộ hoặc đã kiểm thử file.** Xem phạm vi đọc sâu tại [mục lục](README.md).

## root — 2 file, 63 dòng

| File | Dòng |
|---|---:|
| [Dockerfile](../../Dockerfile) | 16 |
| [Makefile](../../Makefile) | 47 |

## ai — 2 file, 315 dòng

| File | Dòng |
|---|---:|
| [ai/colab_finetune_bankops_t4.ipynb](../../ai/colab_finetune_bankops_t4.ipynb) | 188 |
| [ai/serve_cpu.py](../../ai/serve_cpu.py) | 127 |

## backend — 66 file, 12,245 dòng

| File | Dòng |
|---|---:|
| [backend/Dockerfile](../../backend/Dockerfile) | 21 |
| [backend/alembic/env.py](../../backend/alembic/env.py) | 76 |
| [backend/alembic/versions/001_initial.py](../../backend/alembic/versions/001_initial.py) | 280 |
| [backend/alembic/versions/002_idempotency_and_balances.py](../../backend/alembic/versions/002_idempotency_and_balances.py) | 48 |
| [backend/alembic/versions/003_integrations_reconciliation.py](../../backend/alembic/versions/003_integrations_reconciliation.py) | 81 |
| [backend/alembic/versions/004_timestamptz_cleanup.py](../../backend/alembic/versions/004_timestamptz_cleanup.py) | 41 |
| [backend/alembic/versions/005_integration_fields.py](../../backend/alembic/versions/005_integration_fields.py) | 73 |
| [backend/alembic/versions/006_user_pin_hash.py](../../backend/alembic/versions/006_user_pin_hash.py) | 25 |
| [backend/alembic/versions/007_user_profile_columns.py](../../backend/alembic/versions/007_user_profile_columns.py) | 26 |
| [backend/app/__init__.py](../../backend/app/__init__.py) | 1 |
| [backend/app/api/__init__.py](../../backend/app/api/__init__.py) | 1 |
| [backend/app/api/errors.py](../../backend/app/api/errors.py) | 119 |
| [backend/app/api/middleware/__init__.py](../../backend/app/api/middleware/__init__.py) | 1 |
| [backend/app/api/middleware/correlation.py](../../backend/app/api/middleware/correlation.py) | 48 |
| [backend/app/api/openapi.py](../../backend/app/api/openapi.py) | 50 |
| [backend/app/api/routes/__init__.py](../../backend/app/api/routes/__init__.py) | 1 |
| [backend/app/api/routes/activity.py](../../backend/app/api/routes/activity.py) | 227 |
| [backend/app/api/routes/ai.py](../../backend/app/api/routes/ai.py) | 61 |
| [backend/app/api/routes/approvals.py](../../backend/app/api/routes/approvals.py) | 155 |
| [backend/app/api/routes/auth.py](../../backend/app/api/routes/auth.py) | 610 |
| [backend/app/api/routes/auth_google.py](../../backend/app/api/routes/auth_google.py) | 161 |
| [backend/app/api/routes/auth_utils.py](../../backend/app/api/routes/auth_utils.py) | 243 |
| [backend/app/api/routes/cash_sim.py](../../backend/app/api/routes/cash_sim.py) | 755 |
| [backend/app/api/routes/events.py](../../backend/app/api/routes/events.py) | 4 |
| [backend/app/api/routes/health.py](../../backend/app/api/routes/health.py) | 59 |
| [backend/app/api/routes/integrations.py](../../backend/app/api/routes/integrations.py) | 1003 |
| [backend/app/api/routes/inventory.py](../../backend/app/api/routes/inventory.py) | 934 |
| [backend/app/api/routes/reconciliations.py](../../backend/app/api/routes/reconciliations.py) | 162 |
| [backend/app/api/routes/reports.py](../../backend/app/api/routes/reports.py) | 311 |
| [backend/app/config.py](../../backend/app/config.py) | 126 |
| [backend/app/database.py](../../backend/app/database.py) | 68 |
| [backend/app/db/__init__.py](../../backend/app/db/__init__.py) | 1 |
| [backend/app/db/base.py](../../backend/app/db/base.py) | 42 |
| [backend/app/main.py](../../backend/app/main.py) | 196 |
| [backend/app/models/__init__.py](../../backend/app/models/__init__.py) | 1 |
| [backend/app/models/activity.py](../../backend/app/models/activity.py) | 99 |
| [backend/app/models/approval.py](../../backend/app/models/approval.py) | 25 |
| [backend/app/models/cash_sim.py](../../backend/app/models/cash_sim.py) | 107 |
| [backend/app/models/iam.py](../../backend/app/models/iam.py) | 69 |
| [backend/app/models/integration.py](../../backend/app/models/integration.py) | 72 |
| [backend/app/models/inventory.py](../../backend/app/models/inventory.py) | 127 |
| [backend/app/models/reconciliation.py](../../backend/app/models/reconciliation.py) | 32 |
| [backend/app/reset_demo_db.py](../../backend/app/reset_demo_db.py) | 123 |
| [backend/app/seed.py](../../backend/app/seed.py) | 295 |
| [backend/app/services/__init__.py](../../backend/app/services/__init__.py) | 0 |
| [backend/app/services/ai.py](../../backend/app/services/ai.py) | 230 |
| [backend/app/services/approval_controls.py](../../backend/app/services/approval_controls.py) | 69 |
| [backend/app/services/approval_events.py](../../backend/app/services/approval_events.py) | 84 |
| [backend/app/services/email_service.py](../../backend/app/services/email_service.py) | 161 |
| [backend/app/services/idempotency.py](../../backend/app/services/idempotency.py) | 60 |
| [backend/app/worker.py](../../backend/app/worker.py) | 142 |
| [backend/tests/conftest.py](../../backend/tests/conftest.py) | 100 |
| [backend/tests/test_acceptance_qa.py](../../backend/tests/test_acceptance_qa.py) | 609 |
| [backend/tests/test_ai.py](../../backend/tests/test_ai.py) | 201 |
| [backend/tests/test_api_v1_web_e2e.py](../../backend/tests/test_api_v1_web_e2e.py) | 281 |
| [backend/tests/test_approval_controls.py](../../backend/tests/test_approval_controls.py) | 86 |
| [backend/tests/test_b01_foundation.py](../../backend/tests/test_b01_foundation.py) | 456 |
| [backend/tests/test_change_security.py](../../backend/tests/test_change_security.py) | 247 |
| [backend/tests/test_contract_vs_docs.py](../../backend/tests/test_contract_vs_docs.py) | 1058 |
| [backend/tests/test_dev_contracts.py](../../backend/tests/test_dev_contracts.py) | 63 |
| [backend/tests/test_hf_llm_space.py](../../backend/tests/test_hf_llm_space.py) | 171 |
| [backend/tests/test_integrations.py](../../backend/tests/test_integrations.py) | 575 |
| [backend/tests/test_modal_llm.py](../../backend/tests/test_modal_llm.py) | 195 |
| [backend/tests/test_reports.py](../../backend/tests/test_reports.py) | 156 |
| [backend/tests/test_sse_approvals.py](../../backend/tests/test_sse_approvals.py) | 91 |
| [backend/tests/verify_live_e2e.py](../../backend/tests/verify_live_e2e.py) | 250 |

## frontend — 104 file, 21,249 dòng

| File | Dòng |
|---|---:|
| [frontend/android/app/build.gradle.kts](../../frontend/android/app/build.gradle.kts) | 49 |
| [frontend/android/app/src/main/kotlin/com/example/bankops/MainActivity.kt](../../frontend/android/app/src/main/kotlin/com/example/bankops/MainActivity.kt) | 5 |
| [frontend/android/build.gradle.kts](../../frontend/android/build.gradle.kts) | 24 |
| [frontend/android/settings.gradle.kts](../../frontend/android/settings.gradle.kts) | 26 |
| [frontend/ios/Runner/AppDelegate.swift](../../frontend/ios/Runner/AppDelegate.swift) | 16 |
| [frontend/ios/Runner/Runner-Bridging-Header.h](../../frontend/ios/Runner/Runner-Bridging-Header.h) | 1 |
| [frontend/ios/Runner/SceneDelegate.swift](../../frontend/ios/Runner/SceneDelegate.swift) | 6 |
| [frontend/ios/RunnerTests/RunnerTests.swift](../../frontend/ios/RunnerTests/RunnerTests.swift) | 12 |
| [frontend/lib/main.dart](../../frontend/lib/main.dart) | 75 |
| [frontend/lib/src/app/app_shell.dart](../../frontend/lib/src/app/app_shell.dart) | 949 |
| [frontend/lib/src/app/theme_mode_controller.dart](../../frontend/lib/src/app/theme_mode_controller.dart) | 18 |
| [frontend/lib/src/core/theme/app_theme.dart](../../frontend/lib/src/core/theme/app_theme.dart) | 316 |
| [frontend/lib/src/core/theme/app_tokens.dart](../../frontend/lib/src/core/theme/app_tokens.dart) | 65 |
| [frontend/lib/src/core/util/approval_pdf.dart](../../frontend/lib/src/core/util/approval_pdf.dart) | 175 |
| [frontend/lib/src/core/util/csv_export.dart](../../frontend/lib/src/core/util/csv_export.dart) | 53 |
| [frontend/lib/src/core/util/formatting.dart](../../frontend/lib/src/core/util/formatting.dart) | 165 |
| [frontend/lib/src/core/util/report_excel.dart](../../frontend/lib/src/core/util/report_excel.dart) | 118 |
| [frontend/lib/src/core/util/report_share.dart](../../frontend/lib/src/core/util/report_share.dart) | 56 |
| [frontend/lib/src/core/util/responsive.dart](../../frontend/lib/src/core/util/responsive.dart) | 60 |
| [frontend/lib/src/core/util/role_visibility.dart](../../frontend/lib/src/core/util/role_visibility.dart) | 59 |
| [frontend/lib/src/core/widgets/app_screen.dart](../../frontend/lib/src/core/widgets/app_screen.dart) | 42 |
| [frontend/lib/src/core/widgets/app_toast.dart](../../frontend/lib/src/core/widgets/app_toast.dart) | 66 |
| [frontend/lib/src/core/widgets/async_view.dart](../../frontend/lib/src/core/widgets/async_view.dart) | 76 |
| [frontend/lib/src/core/widgets/confirm_dialog.dart](../../frontend/lib/src/core/widgets/confirm_dialog.dart) | 80 |
| [frontend/lib/src/core/widgets/demo_banner.dart](../../frontend/lib/src/core/widgets/demo_banner.dart) | 41 |
| [frontend/lib/src/core/widgets/detail_sheet.dart](../../frontend/lib/src/core/widgets/detail_sheet.dart) | 86 |
| [frontend/lib/src/core/widgets/global_search.dart](../../frontend/lib/src/core/widgets/global_search.dart) | 291 |
| [frontend/lib/src/core/widgets/google_logo.dart](../../frontend/lib/src/core/widgets/google_logo.dart) | 112 |
| [frontend/lib/src/core/widgets/info_row.dart](../../frontend/lib/src/core/widgets/info_row.dart) | 50 |
| [frontend/lib/src/core/widgets/metric_tile.dart](../../frontend/lib/src/core/widgets/metric_tile.dart) | 78 |
| [frontend/lib/src/core/widgets/section_header.dart](../../frontend/lib/src/core/widgets/section_header.dart) | 85 |
| [frontend/lib/src/core/widgets/state_views.dart](../../frontend/lib/src/core/widgets/state_views.dart) | 130 |
| [frontend/lib/src/core/widgets/status_chip.dart](../../frontend/lib/src/core/widgets/status_chip.dart) | 138 |
| [frontend/lib/src/core/widgets/user_avatar.dart](../../frontend/lib/src/core/widgets/user_avatar.dart) | 57 |
| [frontend/lib/src/data/models/domain_models.dart](../../frontend/lib/src/data/models/domain_models.dart) | 32 |
| [frontend/lib/src/data/models/dtos.dart](../../frontend/lib/src/data/models/dtos.dart) | 423 |
| [frontend/lib/src/data/models/report_dtos.dart](../../frontend/lib/src/data/models/report_dtos.dart) | 109 |
| [frontend/lib/src/data/repositories/bankops_repository.dart](../../frontend/lib/src/data/repositories/bankops_repository.dart) | 217 |
| [frontend/lib/src/data/repositories/fake_repository.dart](../../frontend/lib/src/data/repositories/fake_repository.dart) | 964 |
| [frontend/lib/src/data/repositories/http_bankops_repository.dart](../../frontend/lib/src/data/repositories/http_bankops_repository.dart) | 1291 |
| [frontend/lib/src/data/repositories/seed_data.dart](../../frontend/lib/src/data/repositories/seed_data.dart) | 132 |
| [frontend/lib/src/features/activity/activity_center.dart](../../frontend/lib/src/features/activity/activity_center.dart) | 247 |
| [frontend/lib/src/features/activity/activity_screen.dart](../../frontend/lib/src/features/activity/activity_screen.dart) | 176 |
| [frontend/lib/src/features/ai/ai_assistant_dialog.dart](../../frontend/lib/src/features/ai/ai_assistant_dialog.dart) | 356 |
| [frontend/lib/src/features/approvals/approvals_screen.dart](../../frontend/lib/src/features/approvals/approvals_screen.dart) | 1206 |
| [frontend/lib/src/features/auth/auth_service.dart](../../frontend/lib/src/features/auth/auth_service.dart) | 422 |
| [frontend/lib/src/features/auth/login_screen.dart](../../frontend/lib/src/features/auth/login_screen.dart) | 606 |
| [frontend/lib/src/features/auth/widgets/forgot_password_dialog.dart](../../frontend/lib/src/features/auth/widgets/forgot_password_dialog.dart) | 468 |
| [frontend/lib/src/features/cash/cash_screen.dart](../../frontend/lib/src/features/cash/cash_screen.dart) | 737 |
| [frontend/lib/src/features/dashboard/dashboard_screen.dart](../../frontend/lib/src/features/dashboard/dashboard_screen.dart) | 1208 |
| [frontend/lib/src/features/integrations/import_screen.dart](../../frontend/lib/src/features/integrations/import_screen.dart) | 497 |
| [frontend/lib/src/features/integrations/integrations_screen.dart](../../frontend/lib/src/features/integrations/integrations_screen.dart) | 836 |
| [frontend/lib/src/features/inventory/inventory_screen.dart](../../frontend/lib/src/features/inventory/inventory_screen.dart) | 729 |
| [frontend/lib/src/features/reports/reports_filter.dart](../../frontend/lib/src/features/reports/reports_filter.dart) | 75 |
| [frontend/lib/src/features/reports/reports_screen.dart](../../frontend/lib/src/features/reports/reports_screen.dart) | 201 |
| [frontend/lib/src/features/reports/widgets/cashflow_chart.dart](../../frontend/lib/src/features/reports/widgets/cashflow_chart.dart) | 190 |
| [frontend/lib/src/features/reports/widgets/inventory_chart.dart](../../frontend/lib/src/features/reports/widgets/inventory_chart.dart) | 199 |
| [frontend/lib/src/features/reports/widgets/stagnation_list.dart](../../frontend/lib/src/features/reports/widgets/stagnation_list.dart) | 135 |
| [frontend/lib/src/features/requests/request_timeline.dart](../../frontend/lib/src/features/requests/request_timeline.dart) | 176 |
| [frontend/lib/src/features/requests/requests_screen.dart](../../frontend/lib/src/features/requests/requests_screen.dart) | 896 |
| [frontend/lib/src/features/requests/widgets/denomination_breakdown_dialog.dart](../../frontend/lib/src/features/requests/widgets/denomination_breakdown_dialog.dart) | 262 |
| [frontend/lib/src/features/settings/settings_screen.dart](../../frontend/lib/src/features/settings/settings_screen.dart) | 600 |
| [frontend/lib/src/features/settings/widgets/change_password_dialog.dart](../../frontend/lib/src/features/settings/widgets/change_password_dialog.dart) | 278 |
| [frontend/lib/src/features/settings/widgets/change_pin_dialog.dart](../../frontend/lib/src/features/settings/widgets/change_pin_dialog.dart) | 289 |
| [frontend/lib/src/features/settings/widgets/edit_profile_dialog.dart](../../frontend/lib/src/features/settings/widgets/edit_profile_dialog.dart) | 374 |
| [frontend/linux/CMakeLists.txt](../../frontend/linux/CMakeLists.txt) | 128 |
| [frontend/linux/flutter/CMakeLists.txt](../../frontend/linux/flutter/CMakeLists.txt) | 88 |
| [frontend/linux/flutter/generated_plugin_registrant.cc](../../frontend/linux/flutter/generated_plugin_registrant.cc) | 19 |
| [frontend/linux/flutter/generated_plugin_registrant.h](../../frontend/linux/flutter/generated_plugin_registrant.h) | 15 |
| [frontend/linux/flutter/generated_plugins.cmake](../../frontend/linux/flutter/generated_plugins.cmake) | 26 |
| [frontend/linux/runner/CMakeLists.txt](../../frontend/linux/runner/CMakeLists.txt) | 26 |
| [frontend/linux/runner/main.cc](../../frontend/linux/runner/main.cc) | 6 |
| [frontend/linux/runner/my_application.cc](../../frontend/linux/runner/my_application.cc) | 148 |
| [frontend/linux/runner/my_application.h](../../frontend/linux/runner/my_application.h) | 21 |
| [frontend/macos/Flutter/GeneratedPluginRegistrant.swift](../../frontend/macos/Flutter/GeneratedPluginRegistrant.swift) | 18 |
| [frontend/macos/Runner/AppDelegate.swift](../../frontend/macos/Runner/AppDelegate.swift) | 13 |
| [frontend/macos/Runner/MainFlutterWindow.swift](../../frontend/macos/Runner/MainFlutterWindow.swift) | 15 |
| [frontend/macos/RunnerTests/RunnerTests.swift](../../frontend/macos/RunnerTests/RunnerTests.swift) | 12 |
| [frontend/test/ai_risk_dual_control_test.dart](../../frontend/test/ai_risk_dual_control_test.dart) | 117 |
| [frontend/test/bulk_approve_test.dart](../../frontend/test/bulk_approve_test.dart) | 84 |
| [frontend/test/dashboard_roles_test.dart](../../frontend/test/dashboard_roles_test.dart) | 154 |
| [frontend/test/denomination_dialog_test.dart](../../frontend/test/denomination_dialog_test.dart) | 60 |
| [frontend/test/global_search_test.dart](../../frontend/test/global_search_test.dart) | 95 |
| [frontend/test/http_repository_test.dart](../../frontend/test/http_repository_test.dart) | 322 |
| [frontend/test/import_preview_test.dart](../../frontend/test/import_preview_test.dart) | 68 |
| [frontend/test/report_export_test.dart](../../frontend/test/report_export_test.dart) | 79 |
| [frontend/test/reports_chart_test.dart](../../frontend/test/reports_chart_test.dart) | 54 |
| [frontend/test/request_timeline_test.dart](../../frontend/test/request_timeline_test.dart) | 77 |
| [frontend/test/security_settings_test.dart](../../frontend/test/security_settings_test.dart) | 654 |
| [frontend/test/widget_test.dart](../../frontend/test/widget_test.dart) | 83 |
| [frontend/windows/CMakeLists.txt](../../frontend/windows/CMakeLists.txt) | 108 |
| [frontend/windows/flutter/CMakeLists.txt](../../frontend/windows/flutter/CMakeLists.txt) | 109 |
| [frontend/windows/flutter/generated_plugin_registrant.cc](../../frontend/windows/flutter/generated_plugin_registrant.cc) | 17 |
| [frontend/windows/flutter/generated_plugin_registrant.h](../../frontend/windows/flutter/generated_plugin_registrant.h) | 15 |
| [frontend/windows/flutter/generated_plugins.cmake](../../frontend/windows/flutter/generated_plugins.cmake) | 26 |
| [frontend/windows/runner/CMakeLists.txt](../../frontend/windows/runner/CMakeLists.txt) | 40 |
| [frontend/windows/runner/flutter_window.cpp](../../frontend/windows/runner/flutter_window.cpp) | 71 |
| [frontend/windows/runner/flutter_window.h](../../frontend/windows/runner/flutter_window.h) | 33 |
| [frontend/windows/runner/main.cpp](../../frontend/windows/runner/main.cpp) | 43 |
| [frontend/windows/runner/resource.h](../../frontend/windows/runner/resource.h) | 16 |
| [frontend/windows/runner/utils.cpp](../../frontend/windows/runner/utils.cpp) | 69 |
| [frontend/windows/runner/utils.h](../../frontend/windows/runner/utils.h) | 19 |
| [frontend/windows/runner/win32_window.cpp](../../frontend/windows/runner/win32_window.cpp) | 288 |
| [frontend/windows/runner/win32_window.h](../../frontend/windows/runner/win32_window.h) | 102 |

## infra — 21 file, 3,855 dòng

| File | Dòng |
|---|---:|
| [infra/cloudflare-worker/eslint.config.js](../../infra/cloudflare-worker/eslint.config.js) | 18 |
| [infra/cloudflare-worker/src/db/client.ts](../../infra/cloudflare-worker/src/db/client.ts) | 39 |
| [infra/cloudflare-worker/src/index.ts](../../infra/cloudflare-worker/src/index.ts) | 340 |
| [infra/cloudflare-worker/src/middleware/auth.ts](../../infra/cloudflare-worker/src/middleware/auth.ts) | 101 |
| [infra/cloudflare-worker/src/routes/activity.ts](../../infra/cloudflare-worker/src/routes/activity.ts) | 85 |
| [infra/cloudflare-worker/src/routes/ai.ts](../../infra/cloudflare-worker/src/routes/ai.ts) | 303 |
| [infra/cloudflare-worker/src/routes/approvals.ts](../../infra/cloudflare-worker/src/routes/approvals.ts) | 130 |
| [infra/cloudflare-worker/src/routes/auth.ts](../../infra/cloudflare-worker/src/routes/auth.ts) | 675 |
| [infra/cloudflare-worker/src/routes/cash-sim.ts](../../infra/cloudflare-worker/src/routes/cash-sim.ts) | 382 |
| [infra/cloudflare-worker/src/routes/health.ts](../../infra/cloudflare-worker/src/routes/health.ts) | 40 |
| [infra/cloudflare-worker/src/routes/integrations.ts](../../infra/cloudflare-worker/src/routes/integrations.ts) | 286 |
| [infra/cloudflare-worker/src/routes/inventory.ts](../../infra/cloudflare-worker/src/routes/inventory.ts) | 419 |
| [infra/cloudflare-worker/src/routes/reconciliations.ts](../../infra/cloudflare-worker/src/routes/reconciliations.ts) | 85 |
| [infra/cloudflare-worker/src/routes/reports.ts](../../infra/cloudflare-worker/src/routes/reports.ts) | 291 |
| [infra/hf-llm-space/Dockerfile](../../infra/hf-llm-space/Dockerfile) | 45 |
| [infra/hf-llm-space/entrypoint.sh](../../infra/hf-llm-space/entrypoint.sh) | 72 |
| [infra/modal/bankops_llm_server.py](../../infra/modal/bankops_llm_server.py) | 132 |
| [infra/modal/modal_app.py](../../infra/modal/modal_app.py) | 95 |
| [infra/scripts/setup-neon.sh](../../infra/scripts/setup-neon.sh) | 156 |
| [infra/scripts/upload-model-to-hf.sh](../../infra/scripts/upload-model-to-hf.sh) | 115 |
| [infra/scripts/upload-model-to-modal.sh](../../infra/scripts/upload-model-to-modal.sh) | 46 |
