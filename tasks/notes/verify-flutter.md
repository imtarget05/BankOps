# Verify Flutter (2026-10-13, WP-A → WP-D)

- SDK: Flutter 3.47.7 / Dart 3.13.5 (brew cask, khớp pubspec `>=3.4.0 <4.0.0`)
- Cuối đợt: `flutter analyze`: **No issues found!** · `flutter test`: **28/28 passed**
  - report_export (5: excel round-trip x3, pdf header, vn-ascii)
  - request_timeline (3: có sự kiện, rỗng, mở sheet từ Requests)
  - + 20 tests cũ (đợt A–C) vẫn xanh.
