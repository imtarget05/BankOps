import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/models/dtos.dart';

/// In phiếu duyệt thành PDF 1 trang (A5) để Checker lưu chứng từ.
///
/// Pure-Dart (async vì `pdf` build font), test được không cần widget.
/// Font PDF built-in (Helvetica/WinAnsi) KHÔNG có glyph tiếng Việt nên mọi
/// text in ra đều qua [VnAscii.strip] (không dấu) để tránh ô vuông.
/// Mọi con số là giả lập — đầu trang ghi rõ "PHIEU MO PHONG".
class ApprovalPdf {
  const ApprovalPdf._();

  static Future<List<int>> encode(ApprovalItem item) async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              VnAscii.strip(
                  'PHIẾU MÔ PHỎNG — KHÔNG CÓ GIÁ TRỊ THANH TOÁN'),
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.red800,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              VnAscii.strip('Phiếu chờ duyệt: ${item.id}'),
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 12),
            _ApprovalRow.build('Loai phieu', VnAscii.strip(item.kind)),
            _ApprovalRow.build(
                'Nguoi lap (Maker)', VnAscii.strip(item.maker)),
            _ApprovalRow.build(
                'Tac dong so du', VnAscii.strip(item.impact)),
            _ApprovalRow.build('Chi tiet',
                VnAscii.strip(item.detail.isEmpty ? '—' : item.detail)),
            pw.Spacer(),
            pw.Divider(),
            pw.Text(
              VnAscii.strip(
                  'In tu BankOps demo luc ${DateTime.now().toIso8601String()}. '
                  'Phieu chi co hieu luc sau khi Checker duyet tren he thong.'),
              style:
                  const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          ],
        ),
      ),
    );
    return doc.save();
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
