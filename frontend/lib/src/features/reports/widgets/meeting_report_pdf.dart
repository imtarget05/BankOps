import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/util/formatting.dart';
import '../../../data/models/dtos.dart';
import '../reports_filter.dart';

/// Tạo tài liệu PDF A4 báo cáo giao ban điều hành phục vụ in ấn hoặc lưu trữ cuộc họp.
class MeetingReportPdf {
  const MeetingReportPdf._();

  static Future<List<int>> encode({
    required List<InventoryBucket> inventoryBuckets,
    required List<CashflowBucket> cashflowBuckets,
    required List<StagnationItem> stagnationItems,
    required List<ReconciliationRun> reconciliations,
    required ReportGranularity granularity,
    DateTimeRange? dateRange,
    String? staffAssessment,
    String? staffNotes,
  }) async {
    final doc = pw.Document();
    final font =
        pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));

    // Tính tổng dòng tiền
    double totalIn = 0;
    double totalOut = 0;
    int totalJournals = 0;
    for (final b in cashflowBuckets) {
      totalIn += b.inValue;
      totalOut += b.outValue;
      totalJournals += b.journalCount;
    }
    final netCash = totalIn - totalOut;

    // Tính tổng kho
    double totalInbound = 0;
    double totalOutbound = 0;
    int totalReceipts = 0;
    int totalIssues = 0;
    for (final b in inventoryBuckets) {
      totalInbound += b.inboundValue;
      totalOutbound += b.outboundValue;
      totalReceipts += b.receiptCount;
      totalIssues += b.issueCount;
    }
    final netInventory = totalInbound - totalOutbound;

    // Phân tầng tồn đọng
    final critical =
        stagnationItems.where((i) => i.severity == 'critical').toList();
    final stagnant =
        stagnationItems.where((i) => i.severity == 'stagnant').toList();
    final watch = stagnationItems.where((i) => i.severity == 'watch').toList();

    // Đối soát
    final totalRuns = reconciliations.length;
    final cleanRuns = reconciliations.where((r) => r.exceptions.isEmpty).length;
    final matchRate = totalRuns > 0
        ? (cleanRuns / totalRuns * 100).toStringAsFixed(1)
        : '100.0';

    final periodStr = dateRange != null
        ? '${AppFormat.date(dateRange.start)} → ${AppFormat.date(dateRange.end)}'
        : (granularity == ReportGranularity.daily
            ? 'Tổng hợp theo ngày'
            : 'Tổng hợp theo tháng');

    final assessmentStr = staffAssessment ??
        (critical.isNotEmpty
            ? 'Cảnh báo rủi ro (Tồn đọng >= 90 ngày)'
            : 'Vận hành đạt chuẩn');

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: pw.ThemeData.withFont(base: font, bold: font, italic: font),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Header báo cáo kho trà sữa
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'HỆ THỐNG CỬA HÀNG & KHO F&B BANKOPS',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue900,
                      ),
                    ),
                    pw.Text(
                      'Chi nhánh Vận hành Trung tâm',
                      style: const pw.TextStyle(
                          fontSize: 8.5, color: PdfColors.grey700),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'BÁO CÁO VẬN HÀNH ĐIỀU HÀNH',
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue900,
                      ),
                    ),
                    pw.Text(
                      'Hệ thống Quản trị Doanh nghiệp BankOps',
                      style: const pw.TextStyle(
                          fontSize: 8, color: PdfColors.grey600),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Divider(thickness: 1.5, color: PdfColors.blue900),
            pw.SizedBox(height: 10),

            // Tiêu đề báo cáo
            pw.Center(
              child: pw.Column(
                children: [
                  pw.Text(
                    'BÁO CÁO TỔNG HỢP VẬN HÀNH KINH DOANH & TỒN KHO',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.black,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Kỳ báo cáo: $periodStr · Ngày in: ${AppFormat.dateTime(DateTime.now())}',
                    style: const pw.TextStyle(
                        fontSize: 9, color: PdfColors.grey700),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Đánh giá trạng thái: $assessmentStr',
                    style: pw.TextStyle(
                      fontSize: 9.5,
                      fontWeight: pw.FontWeight.bold,
                      color: critical.isNotEmpty
                          ? PdfColors.red800
                          : PdfColors.green800,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 14),

            // Mục 1: Chỉ số tổng hợp dòng tiền & kho
            pw.Text(
              'I. TỔNG HỢP CHỈ SỐ THANH KHOẢN & VẬN HÀNH KHO',
              style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue900),
            ),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    _cellHeader('Chỉ số vận hành'),
                    _cellHeader('Giá trị trong kỳ'),
                    _cellHeader('Chi tiết / Đơn vị'),
                  ],
                ),
                pw.TableRow(
                  children: [
                    _cellText('Tổng thu tiền mặt (Thu quỹ)'),
                    _cellText(AppFormat.money(totalIn.toStringAsFixed(0))),
                    _cellText('$totalJournals bút toán thực hiện'),
                  ],
                ),
                pw.TableRow(
                  children: [
                    _cellText('Tổng chi tiền mặt (Chi quỹ)'),
                    _cellText(AppFormat.money(totalOut.toStringAsFixed(0))),
                    _cellText('Điều chỉnh & xuất kho'),
                  ],
                ),
                pw.TableRow(
                  children: [
                    _cellText('Dòng tiền thuần ròng (Net)'),
                    _cellText(
                      AppFormat.money(netCash.toStringAsFixed(0)),
                      bold: true,
                      color:
                          netCash >= 0 ? PdfColors.green900 : PdfColors.red900,
                    ),
                    _cellText(netCash >= 0
                        ? 'Thặng dư thanh khoản'
                        : 'Thâm hụt dòng tiền'),
                  ],
                ),
                pw.TableRow(
                  children: [
                    _cellText('Nhập kho nguyên liệu'),
                    _cellText(
                        '${AppFormat.quantity(totalInbound.toStringAsFixed(0))} đơn vị'),
                    _cellText('$totalReceipts phiếu nhập hoàn tất'),
                  ],
                ),
                pw.TableRow(
                  children: [
                    _cellText('Xuất kho / sử dụng nguyên liệu'),
                    _cellText(
                        '${AppFormat.quantity(totalOutbound.toStringAsFixed(0))} đơn vị'),
                    _cellText('$totalIssues phiếu xuất hoàn tất'),
                  ],
                ),
                pw.TableRow(
                  children: [
                    _cellText('Biến động tồn kho ròng'),
                    _cellText(
                        '${AppFormat.quantity(netInventory.toStringAsFixed(0))} đơn vị',
                        bold: true),
                    _cellText('Chênh lệch nhập - xuất'),
                  ],
                ),
                pw.TableRow(
                  children: [
                    _cellText('Tỷ lệ đối soát hoàn hảo'),
                    _cellText('$matchRate%',
                        bold: true, color: PdfColors.blue900),
                    _cellText('$cleanRuns/$totalRuns phiên sạch ngoại lệ'),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 12),

            // Mục 2: Điểm nóng tồn đọng
            pw.Text(
              'II. PHÂN TÍCH RỦI RO & ĐIỂM NÓNG TỒN ĐỌNG VẬT TƯ',
              style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue900),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Phân tầng: Nghiêm trọng (>=90 ngày): ${critical.length} mặt hàng | Tồn đọng (>=60 ngày): ${stagnant.length} | Cần theo dõi (>=30 ngày): ${watch.length}',
              style:
                  const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey800),
            ),
            pw.SizedBox(height: 6),
            if (critical.isEmpty)
              pw.Container(
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  color: PdfColors.green50,
                  border: pw.Border.all(color: PdfColors.green200),
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Text(
                  'Không có nguyên liệu nào tồn đọng trên 90 ngày. Tốc độ sử dụng đang trong ngưỡng an toàn.',
                  style: const pw.TextStyle(
                      fontSize: 8.5, color: PdfColors.green900),
                ),
              )
            else
              pw.Table(
                border:
                    pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.red50),
                    children: [
                      _cellHeader('Mã SKU'),
                      _cellHeader('Tên nguyên liệu'),
                      _cellHeader('Số lượng tồn'),
                      _cellHeader('Thời gian chưa xuất'),
                    ],
                  ),
                  for (final item in critical.take(4))
                    pw.TableRow(
                      children: [
                        _cellText(item.sku, bold: true),
                        _cellText(item.name),
                        _cellText(item.quantity),
                        _cellText(
                          item.daysSinceLastIssue != null
                              ? '${item.daysSinceLastIssue} ngày'
                              : 'Chưa từng xuất',
                          color: PdfColors.red900,
                        ),
                      ],
                    ),
                ],
              ),
            pw.SizedBox(height: 12),

            // Mục 3: Đề xuất điều hành & Kế hoạch
            pw.Text(
              'III. ĐỀ XUẤT ĐIỀU HÀNH & KẾ HOẠCH VẬN HÀNH TIẾP THEO',
              style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue900),
            ),
            pw.SizedBox(height: 4),
            pw.Bullet(
              text: critical.isNotEmpty
                  ? 'Đề nghị Hội đồng thanh lý / Tổ quản lý kho rà soát ${critical.length} mặt hàng tồn đọng lâu ngày.'
                  : 'Duy trì định mức tồn kho tối thiểu - tối đa theo kế hoạch quý.',
              style: const pw.TextStyle(fontSize: 8.5),
            ),
            pw.Bullet(
              text: netCash < 0
                  ? 'Cân đối thanh khoản do dòng tiền chi đang cao hơn dòng tiền thu trong kỳ báo cáo.'
                  : 'Thanh khoản quỹ ổn định, đảm bảo đáp ứng đầy đủ hạn mức chi trả của chi nhánh.',
              style: const pw.TextStyle(fontSize: 8.5),
            ),
            pw.Bullet(
              text:
                  'Tuân thủ nghiêm ngặt quy trình kiểm soát phê duyệt và bảo mật hệ thống.',
              style: const pw.TextStyle(fontSize: 8.5),
            ),
            if (staffNotes != null && staffNotes.trim().isNotEmpty) ...[
              pw.SizedBox(height: 4),
              pw.Text(
                'Ý kiến đề xuất bổ sung: ${staffNotes.trim()}',
                style: pw.TextStyle(
                    fontSize: 8.5,
                    fontStyle: pw.FontStyle.italic,
                    color: PdfColors.grey800),
              ),
            ],

            pw.Spacer(),

            // Chữ ký 3 bên chuẩn doanh nghiệp
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _signatureBlock('NGƯỜI LẬP BÁO CÁO\n(Nhân viên phụ trách)',
                    'Ký và ghi rõ họ tên'),
                _signatureBlock('THỦ KHO / THỦ QUỸ\n(Phụ trách kho vận)',
                    'Ký và ghi rõ họ tên'),
                _signatureBlock('GIÁM ĐỐC / QUẢN LÝ\n(Phê duyệt)',
                    'Ký và đóng dấu xác nhận'),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Center(
              child: pw.Text(
                'Hệ thống Quản trị Doanh nghiệp BankOps · Báo cáo vận hành kinh doanh',
                style:
                    const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey500),
              ),
            ),
          ],
        ),
      ),
    );

    return doc.save();
  }

  static pw.Widget _cellHeader(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: pw.Text(
        text,
        style: pw.TextStyle(
            fontSize: 8.5,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blue900),
      ),
    );
  }

  static pw.Widget _cellText(String text,
      {bool bold = false, PdfColor color = PdfColors.black}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
            fontSize: 8,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: color),
      ),
    );
  }

  static pw.Widget _signatureBlock(String title, String hint) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          title,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black),
        ),
        pw.SizedBox(height: 38),
        pw.Text(
          hint,
          style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
        ),
      ],
    );
  }
}
