import 'package:excel/excel.dart';

import '../../data/models/dtos.dart';

/// Tạo file Excel (.xlsx) thật từ dữ liệu báo cáo — thay cho CSV clipboard.
///
/// Pure-Dart (không cần BuildContext) để test được không cần widget.
/// Tên sheet dùng tiếng Việt không dấu (Excel sheet name an toàn).
class ReportExcel {
  const ReportExcel._();

  static List<String> get inventoryHeaders => const [
        'bucket',
        'inbound_qty',
        'outbound_qty',
        'net_qty',
        'receipt_count',
        'issue_count',
      ];

  static List<String> get cashflowHeaders => const [
        'bucket',
        'total_in',
        'total_out',
        'net',
        'journal_count',
      ];

  static List<String> get stagnationHeaders => const [
        'sku',
        'name',
        'quantity',
        'days_since_last_issue',
        'severity',
      ];

  static List<int> encodeInventory(List<InventoryBucket> buckets) {
    return _encode(
      sheetName: 'NhapXuatKho',
      headers: inventoryHeaders,
      rows: [
        for (final b in buckets)
          [
            TextCellValue(b.bucket),
            TextCellValue(b.inboundQty),
            TextCellValue(b.outboundQty),
            TextCellValue(b.netQty),
            IntCellValue(b.receiptCount),
            IntCellValue(b.issueCount),
          ],
      ],
    );
  }

  static List<int> encodeCashflow(List<CashflowBucket> buckets) {
    return _encode(
      sheetName: 'DongTien',
      headers: cashflowHeaders,
      rows: [
        for (final b in buckets)
          [
            TextCellValue(b.bucket),
            TextCellValue(b.totalIn),
            TextCellValue(b.totalOut),
            TextCellValue(b.net),
            IntCellValue(b.journalCount),
          ],
      ],
    );
  }

  static List<int> encodeStagnation(List<StagnationItem> items) {
    return _encode(
      sheetName: 'TonDong',
      headers: stagnationHeaders,
      rows: [
        for (final item in items)
          [
            TextCellValue(item.sku),
            TextCellValue(item.name),
            TextCellValue(item.quantity),
            item.daysSinceLastIssue == null
                ? null
                : IntCellValue(item.daysSinceLastIssue!),
            TextCellValue(item.severity),
          ],
      ],
    );
  }

  static List<int> _encode({
    required String sheetName,
    required List<String> headers,
    required List<List<CellValue?>> rows,
  }) {
    final excel = Excel.createExcel();
    excel.delete('Sheet1');
    final sheet = excel[sheetName];
    sheet.appendRow(headers.map(TextCellValue.new).toList());
    for (final row in rows) {
      sheet.appendRow(row);
    }
    final bytes = excel.encode();
    if (bytes == null) throw StateError('Không tạo được file Excel');
    return bytes;
  }

  /// Đọc lại sheet thành ma trận string (dùng cho test round-trip).
  static List<List<String>> decodeSheet(List<int> bytes, String sheetName) {
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables[sheetName];
    if (sheet == null) throw StateError('Thiếu sheet $sheetName');
    return [
      for (final row in sheet.rows)
        [for (final cell in row) cell?.value?.toString() ?? ''],
    ];
  }
}
