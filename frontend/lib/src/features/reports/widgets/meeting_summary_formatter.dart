import 'package:flutter/material.dart';

import '../../../core/util/formatting.dart';
import '../../../data/models/dtos.dart';
import '../reports_filter.dart';

/// Bộ sinh văn bản tóm tắt giao ban cuộc họp (Meeting Briefing Formatter).
/// Dùng để sao chép vào Clipboard (dán vào Biên bản họp, Email, Teams/Slack)
/// hoặc hiển thị trong chế độ trình chiếu.
class MeetingSummaryFormatter {
  const MeetingSummaryFormatter._();

  static String generateMarkdown({
    required List<InventoryBucket> inventoryBuckets,
    required List<CashflowBucket> cashflowBuckets,
    required List<StagnationItem> stagnationItems,
    required List<ReconciliationRun> reconciliations,
    required ReportGranularity granularity,
    DateTimeRange? dateRange,
    String? staffAssessment,
    String? staffNotes,
  }) {
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
            ? 'Cảnh báo rủi ro cao (Có tồn đọng >= 90 ngày)'
            : 'Vận hành ổn định');

    final sb = StringBuffer();
    sb.writeln('# BÁO CÁO VẬN HÀNH QUẢN LÝ KHO TRÀ SỮA');
    sb.writeln('**Kỳ báo cáo:** $periodStr');
    sb.writeln(
        '**Thời điểm trích xuất:** ${AppFormat.dateTime(DateTime.now())}');
    sb.writeln('**Đánh giá sức khỏe vận hành:** $assessmentStr');
    sb.writeln();

    sb.writeln('## 1. DÒNG TIỀN & THANH KHOẢN SỔ QUỸ');
    sb.writeln(
        '- **Tổng thu quỹ:** ${AppFormat.money(totalIn.toStringAsFixed(0))}');
    sb.writeln(
        '- **Tổng chi quỹ:** ${AppFormat.money(totalOut.toStringAsFixed(0))}');
    sb.writeln(
        '- **Dòng tiền ròng (Net):** ${AppFormat.money(netCash.toStringAsFixed(0))} ${netCash >= 0 ? '(Thặng dư)' : '(Thâm hụt)'}');
    sb.writeln('- **Tổng số giao dịch:** $totalJournals bút toán');
    sb.writeln();

    sb.writeln('## 2. VẬN HÀNH KHO NGUYÊN LIỆU');
    sb.writeln(
        '- **Tổng nhập kho:** ${AppFormat.quantity(totalInbound.toStringAsFixed(0))} đơn vị ($totalReceipts phiếu)');
    sb.writeln(
        '- **Tổng xuất kho:** ${AppFormat.quantity(totalOutbound.toStringAsFixed(0))} đơn vị ($totalIssues phiếu)');
    sb.writeln(
        '- **Biến động lưu kho ròng:** ${AppFormat.quantity(netInventory.toStringAsFixed(0))} đơn vị');
    sb.writeln();

    sb.writeln('## 3. ĐIỂM NÓNG TỒN ĐỌNG & RỦI RO');
    sb.writeln('- **Nghiêm trọng (>= 90 ngày):** ${critical.length} mặt hàng');
    sb.writeln('- **Tồn đọng (>= 60 ngày):** ${stagnant.length} mặt hàng');
    sb.writeln('- **Cần theo dõi (>= 30 ngày):** ${watch.length} mặt hàng');
    if (critical.isNotEmpty) {
      sb.writeln('**Danh sách hàng cần xử lý gấp:**');
      for (final item in critical.take(5)) {
        final days = item.daysSinceLastIssue != null
            ? '${item.daysSinceLastIssue} ngày'
            : 'Chưa từng xuất';
        sb.writeln(
            '  * [${item.sku}] ${item.name} — Tồn: ${item.quantity} (Tồn đọng $days)');
      }
    }
    sb.writeln();

    sb.writeln('## 4. KIỂM SOÁT ĐỐI SOÁT & TUÂN THỦ (QUY TRÌNH PHÊ DUYỆT)');
    sb.writeln('- **Tổng số phiên đối soát:** $totalRuns lượt');
    sb.writeln('- **Tỷ lệ khớp lệnh chuẩn:** $matchRate%');
    sb.writeln('- **Phiên có ngoại lệ:** ${totalRuns - cleanRuns} lượt');
    sb.writeln();

    sb.writeln('## 5. TRỌNG TÂM THẢO LUẬN & KIẾN NGHỊ CUỘC HỌP');
    if (critical.isNotEmpty) {
      sb.writeln(
          '1. **Xử lý hàng tồn:** Rà soát ${critical.length} nguyên liệu tồn đọng trên 90 ngày.');
    }
    if (netCash < 0) {
      sb.writeln(
          '2. **Cân đối thanh khoản:** Dòng tiền chi đang vượt dòng tiền thu trong kỳ báo cáo.');
    } else {
      sb.writeln(
          '2. **Cân đối quỹ:** Duy trì thanh khoản an toàn theo hạn mức định mức chi nhánh.');
    }
    if (totalRuns - cleanRuns > 0) {
      sb.writeln(
          '3. **Xử lý ngoại lệ đối soát:** Đề nghị người phụ trách và bộ phận quản lý lập biên bản giải trình các chênh lệch.');
    } else {
      sb.writeln(
          '3. **Kiểm soát quy trình:** Tiếp tục duy trì chuẩn kiểm duyệt phân quyền và bảo mật quy trình.');
    }

    if (staffNotes != null && staffNotes.trim().isNotEmpty) {
      sb.writeln();
      sb.writeln('## 6. GHI CHÚ BỔ SUNG CỦA BỘ PHẬN BÁO CÁO');
      sb.writeln(staffNotes.trim());
    }

    return sb.toString();
  }
}
