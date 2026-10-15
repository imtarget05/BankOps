import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/app_toast.dart';

/// Xuất CSV không cần thêm package: dựng chuỗi CSV chuẩn (quote + escape)
/// rồi sao chép vào clipboard để dán sang Sheets/Excel.
///
/// Lý do không dùng file download: giữ `pubspec.yaml` nguyên (không thêm
/// dep `excel`/`pdf`), chạy được cả Web + iOS mà không cần quyền lưu file.
class CsvExport {
  const CsvExport._();

  /// Dựng chuỗi CSV từ headers + rows. Giá trị `null` thành ô trống.
  static String encode(List<String> headers, List<List<Object?>> rows) {
    final buffer = StringBuffer();
    buffer.writeln(headers.map(_cell).join(','));
    for (final row in rows) {
      buffer.writeln(row.map(_cell).join(','));
    }
    return buffer.toString();
  }

  /// Ký tự mở đầu khiến Excel/Sheets hiểu ô là công thức (CWE-1236).
  static final RegExp _formulaLead = RegExp(r'^[=+\-@\t\r]');

  /// Số hợp lệ (kể cả âm) — giữ nguyên để "-1234" vẫn là số, không bị escape.
  static final RegExp _numeric = RegExp(r'^-?\d+(\.\d+)?$');

  static String _cell(Object? value) {
    if (value == null) return '';
    var text = value.toString();
    // Chống CSV/formula injection: ô bắt đầu bằng = + - @ TAB CR (và không phải
    // số thuần) được thêm tiền tố ' để Excel/Sheets coi là text, không thực thi.
    if (_formulaLead.hasMatch(text) && !_numeric.hasMatch(text)) {
      text = "'$text";
    }
    if (text.contains(RegExp(r'[",\n\r]'))) {
      return '"${text.replaceAll('"', '""')}"';
    }
    return text;
  }

  /// Sao chép CSV vào clipboard + toast xác nhận. Dùng cho nút "Sao chép CSV".
  static Future<void> copyToClipboard(
    BuildContext context, {
    required String label,
    required List<String> headers,
    required List<List<Object?>> rows,
  }) async {
    try {
      final csv = encode(headers, rows);
      await Clipboard.setData(ClipboardData(text: csv));
      if (!context.mounted) return;
      AppToast.success(
        context,
        'Đã sao chép CSV "$label" (${rows.length} dòng) — dán sang Sheets/Excel để dùng',
      );
    } catch (e) {
      if (!context.mounted) return;
      AppToast.error(context, 'Không xuất được CSV: $e');
    }
  }
}
