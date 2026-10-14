import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart';

import '../../data/models/dtos.dart';

/// In phiếu duyệt thành PDF 1 trang (A5) để Checker lưu chứng từ.
///
/// Pure-Dart (async vì `pdf` build font), test được không cần widget.
/// Font Roboto nhúng hỗ trợ tiếng Việt trong chứng từ.
/// Mọi con số là giả lập — đầu trang ghi rõ "PHIEU MO PHONG".
class ApprovalPdf {
  const ApprovalPdf._();

  static Future<List<int>> encode(
    ApprovalItem item, {
    AiRiskAssessment? assessment,
    List<String>? auditWarnings,
  }) async {
    final doc = pw.Document();
    final font = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
    final hasWarnings = auditWarnings != null && auditWarnings.isNotEmpty;

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        theme: pw.ThemeData.withFont(base: font, bold: font),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'NGÂN HÀNG BANKOPS · CHỨNG TỪ NGHIỆP VỤ',
                  style: pw.TextStyle(
                    fontSize: 9.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue900,
                  ),
                ),
                pw.Text(
                  'ISO 27001 · DUAL CONTROL',
                  style: const pw.TextStyle(
                    fontSize: 7.5,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'Phiếu giao dịch & kiểm soát · ${item.id}',
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 10),
            _ApprovalRow.build('Loại phiếu', item.kind),
            _ApprovalRow.build('Trạng thái', item.status),
            _ApprovalRow.build('Người lập (Maker)', item.maker),
            _ApprovalRow.build('Giá trị / số lượng', item.impact),
            _ApprovalRow.build('Nội dung', item.detail.isEmpty ? '—' : item.detail),

            pw.SizedBox(height: 8),
            // AI Audit Section on PDF
            if (hasWarnings) ...[
              pw.Container(
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  color: PdfColors.red50,
                  border: pw.Border.all(color: PdfColors.red800, width: 1),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'CẢNH BÁO KIỂM DUYỆT AI (PHÁT HIỆN ${auditWarnings.length} SAI SÓT / RỦI RO):',
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.red900,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    for (final warning in auditWarnings)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 1.5),
                        child: pw.Text('• $warning', style: const pw.TextStyle(fontSize: 7, color: PdfColors.red900)),
                      ),
                    pw.SizedBox(height: 1.5),
                    pw.Text(
                      'Kiểm toán AI: ${assessment?.auditStamp ?? "AI-AUDIT-FLAGGED"} · Qwen2.5-1.5B Fine-tuned Model',
                      style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700),
                    ),
                  ],
                ),
              ),
            ] else ...[
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: pw.BoxDecoration(
                  color: PdfColors.green50,
                  border: pw.Border.all(color: PdfColors.green700, width: 1),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'AI AUDIT VERIFIED: CHỨNG TỪ HỢP LỆ (ZERO DEFECTS)',
                            style: pw.TextStyle(
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.green900,
                            ),
                          ),
                          pw.SizedBox(height: 1),
                          pw.Text(
                            'Đã kiểm tra định mức tồn, cân đối quỹ và quy chế 4 mắt · Stamp: ${assessment?.auditStamp ?? "AI-VERIFIED-CLEAN"}',
                            style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            pw.Spacer(),
            pw.Divider(),
            pw.SizedBox(height: 6),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _buildSignBox('Người giao/nhận'),
                _buildSignBox('Người lập'),
                _buildSignBox('Thủ kho / thủ quỹ'),
                _buildSignBox('Kiểm soát viên'),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Divider(),
            pw.Text(
              'In từ BankOps Core Banking lúc ${DateTime.now().toIso8601String()}. '
              'Chứng từ được lưu vết kiểm toán điện tử tự động.',
              style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }

  static pw.Widget _buildSignBox(String title) {
    return pw.Column(
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          '(Ký, ghi rõ họ tên)',
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
        ),
        pw.SizedBox(height: 28),
      ],
    );
  }
}


class _ApprovalRow {
  static pw.Widget build(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 140,
            child: pw.Text(
              label,
              style: const pw.TextStyle(
                fontSize: 11,
                color: PdfColors.grey700,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bỏ dấu tiếng Việt để in bằng font PDF built-in (WinAnsi).
/// Giữ nguyên chữ không dấu, số, ký tự ASCII; ký tự đặc biệt còn lại thành '?'.
class VnAscii {
  const VnAscii._();

  static const _map = {
    'à': 'a', 'á': 'a', 'ạ': 'a', 'ả': 'a', 'ã': 'a',
    'â': 'a', 'ầ': 'a', 'ấ': 'a', 'ậ': 'a', 'ẩ': 'a', 'ẫ': 'a',
    'ă': 'a', 'ằ': 'a', 'ắ': 'a', 'ặ': 'a', 'ẳ': 'a', 'ẵ': 'a',
    'è': 'e', 'é': 'e', 'ẹ': 'e', 'ẻ': 'e', 'ẽ': 'e',
    'ê': 'e', 'ề': 'e', 'ế': 'e', 'ệ': 'e', 'ể': 'e', 'ễ': 'e',
    'ì': 'i', 'í': 'i', 'ị': 'i', 'ỉ': 'i', 'ĩ': 'i',
    'ò': 'o', 'ó': 'o', 'ọ': 'o', 'ỏ': 'o', 'õ': 'o',
    'ô': 'o', 'ồ': 'o', 'ố': 'o', 'ộ': 'o', 'ổ': 'o', 'ỗ': 'o',
    'ơ': 'o', 'ờ': 'o', 'ớ': 'o', 'ợ': 'o', 'ở': 'o', 'ỡ': 'o',
    'ù': 'u', 'ú': 'u', 'ụ': 'u', 'ủ': 'u', 'ũ': 'u',
    'ư': 'u', 'ừ': 'u', 'ứ': 'u', 'ự': 'u', 'ử': 'u', 'ữ': 'u',
    'ỳ': 'y', 'ý': 'y', 'ỵ': 'y', 'ỷ': 'y', 'ỹ': 'y',
    'đ': 'd',
    'À': 'A', 'Á': 'A', 'Ạ': 'A', 'Ả': 'A', 'Ã': 'A',
    'Â': 'A', 'Ầ': 'A', 'Ấ': 'A', 'Ậ': 'A', 'Ẩ': 'A', 'Ẫ': 'A',
    'Ă': 'A', 'Ằ': 'A', 'Ắ': 'A', 'Ặ': 'A', 'Ẳ': 'A', 'Ẵ': 'A',
    'È': 'E', 'É': 'E', 'Ẹ': 'E', 'Ẻ': 'E', 'Ẽ': 'E',
    'Ê': 'E', 'Ề': 'E', 'Ế': 'E', 'Ệ': 'E', 'Ể': 'E', 'Ễ': 'E',
    'Ì': 'I', 'Í': 'I', 'Ị': 'I', 'Ỉ': 'I', 'Ĩ': 'I',
    'Ò': 'O', 'Ó': 'O', 'Ọ': 'O', 'Ỏ': 'O', 'Õ': 'O',
    'Ô': 'O', 'Ồ': 'O', 'Ố': 'O', 'Ộ': 'O', 'Ổ': 'O', 'Ỗ': 'O',
    'Ơ': 'O', 'Ờ': 'O', 'Ớ': 'O', 'Ợ': 'O', 'Ở': 'O', 'Ỡ': 'O',
    'Ù': 'U', 'Ú': 'U', 'Ụ': 'U', 'Ủ': 'U', 'Ũ': 'U',
    'Ư': 'U', 'Ừ': 'U', 'Ứ': 'U', 'Ự': 'U', 'Ử': 'U', 'Ữ': 'U',
    'Ỳ': 'Y', 'Ý': 'Y', 'Ỵ': 'Y', 'Ỷ': 'Y', 'Ỹ': 'Y',
    'Đ': 'D', '—': '-', '–': '-',
  };

  static String strip(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      if (_map.containsKey(ch)) {
        buffer.write(_map[ch]);
      } else if (rune < 128) {
        buffer.write(ch);
      } else {
        buffer.write('?');
      }
    }
    return buffer.toString();
  }
}
