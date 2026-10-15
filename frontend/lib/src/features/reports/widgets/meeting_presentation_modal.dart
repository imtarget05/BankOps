import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/util/formatting.dart';
import '../../../core/util/report_share.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/models/dtos.dart';
import '../reports_filter.dart';
import 'meeting_report_pdf.dart';
import 'meeting_summary_formatter.dart';

/// Chế độ Trình chiếu Cuộc họp (Executive Meeting Presentation Deck).
/// Tối ưu cho màn hình lớn / máy chiếu phòng họp lãnh đạo.
class MeetingPresentationModal extends StatefulWidget {
  const MeetingPresentationModal({
    super.key,
    required this.inventoryBuckets,
    required this.cashflowBuckets,
    required this.stagnationItems,
    required this.reconciliations,
    required this.granularity,
    this.dateRange,
    this.staffAssessment,
    this.staffNotes,
  });

  final List<InventoryBucket> inventoryBuckets;
  final List<CashflowBucket> cashflowBuckets;
  final List<StagnationItem> stagnationItems;
  final List<ReconciliationRun> reconciliations;
  final ReportGranularity granularity;
  final DateTimeRange? dateRange;
  final String? staffAssessment;
  final String? staffNotes;

  static void show(
    BuildContext context, {
    required List<InventoryBucket> inventoryBuckets,
    required List<CashflowBucket> cashflowBuckets,
    required List<StagnationItem> stagnationItems,
    required List<ReconciliationRun> reconciliations,
    required ReportGranularity granularity,
    DateTimeRange? dateRange,
    String? staffAssessment,
    String? staffNotes,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 720),
            child: MeetingPresentationModal(
              inventoryBuckets: inventoryBuckets,
              cashflowBuckets: cashflowBuckets,
              stagnationItems: stagnationItems,
              reconciliations: reconciliations,
              granularity: granularity,
              dateRange: dateRange,
              staffAssessment: staffAssessment,
              staffNotes: staffNotes,
            ),
          ),
        ),
      ),
    );
  }

  @override
  State<MeetingPresentationModal> createState() =>
      _MeetingPresentationModalState();
}

class _MeetingPresentationModalState extends State<MeetingPresentationModal> {
  final PageController _pageController = PageController();
  int _currentSlide = 0;
  static const int _totalSlides = 4;

  void _nextSlide() {
    if (_currentSlide < _totalSlides - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _prevSlide() {
    if (_currentSlide > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _copySummary() {
    final md = MeetingSummaryFormatter.generateMarkdown(
      inventoryBuckets: widget.inventoryBuckets,
      cashflowBuckets: widget.cashflowBuckets,
      stagnationItems: widget.stagnationItems,
      reconciliations: widget.reconciliations,
      granularity: widget.granularity,
      dateRange: widget.dateRange,
      staffAssessment: widget.staffAssessment,
      staffNotes: widget.staffNotes,
    );
    Clipboard.setData(ClipboardData(text: md));
    AppToast.success(context, 'Đã sao chép tóm tắt cuộc họp vào Clipboard.');
  }

  void _printPdf() {
    ReportShare.printPdf(
      context,
      filename: 'bao-cao-van-hanh-kho-tra-sua.pdf',
      build: () => MeetingReportPdf.encode(
        inventoryBuckets: widget.inventoryBuckets,
        cashflowBuckets: widget.cashflowBuckets,
        stagnationItems: widget.stagnationItems,
        reconciliations: widget.reconciliations,
        granularity: widget.granularity,
        dateRange: widget.dateRange,
        staffAssessment: widget.staffAssessment,
        staffNotes: widget.staffNotes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor:
            theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'SLIDE DECK',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Báo Cáo Điều Hành Cuộc Họp Giao Ban · Slide ${_currentSlide + 1}/$_totalSlides',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sao chép văn bản tóm tắt',
            icon: const Icon(Icons.content_copy_outlined),
            onPressed: _copySummary,
          ),
          IconButton(
            tooltip: 'In / Xuất PDF A4',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: _printPdf,
          ),
          IconButton(
            tooltip: 'Đóng chế độ trình chiếu',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: PageView(
        controller: _pageController,
        onPageChanged: (idx) => setState(() => _currentSlide = idx),
        children: [
          _buildSlide1Snapshot(context),
          _buildSlide2Stagnation(context),
          _buildSlide3Cashflow(context),
          _buildSlide4Actions(context),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          border:
              Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            OutlinedButton.icon(
              onPressed: _currentSlide > 0 ? _prevSlide : null,
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Trang trước'),
            ),
            Row(
              children: List.generate(_totalSlides, (index) {
                final isSelected = index == _currentSlide;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: isSelected ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            FilledButton.icon(
              onPressed: _currentSlide < _totalSlides - 1
                  ? _nextSlide
                  : () => Navigator.of(context).pop(),
              icon: Icon(
                  _currentSlide < _totalSlides - 1
                      ? Icons.arrow_forward
                      : Icons.check,
                  size: 16),
              label: Text(_currentSlide < _totalSlides - 1
                  ? 'Tiếp theo'
                  : 'Hoàn thành'),
            ),
          ],
        ),
      ),
    );
  }

  // Slide 1: Bức tranh toàn cảnh
  Widget _buildSlide1Snapshot(BuildContext context) {
    final theme = Theme.of(context);
    final statusColors = context.statusColors;

    double totalIn = 0;
    double totalOut = 0;
    for (final b in widget.cashflowBuckets) {
      totalIn += b.inValue;
      totalOut += b.outValue;
    }
    final netCash = totalIn - totalOut;

    double totalInbound = 0;
    double totalOutbound = 0;
    for (final b in widget.inventoryBuckets) {
      totalInbound += b.inboundValue;
      totalOutbound += b.outboundValue;
    }
    final netInv = totalInbound - totalOutbound;

    final criticalCount =
        widget.stagnationItems.where((i) => i.severity == 'critical').length;
    final totalRuns = widget.reconciliations.length;
    final cleanRuns =
        widget.reconciliations.where((r) => r.exceptions.isEmpty).length;
    final matchRate = totalRuns > 0
        ? (cleanRuns / totalRuns * 100).toStringAsFixed(0)
        : '100';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '1. TỔNG QUAN TÌNH HÌNH VẬN HÀNH TRONG KỲ',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tóm tắt số liệu tồn kho, nhập xuất nguyên liệu và các chỉ số vận hành cửa hàng.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _bigMetricCard(
                  context,
                  title: 'DÒNG TIỀN RÒNG (NET)',
                  value: '${netCash >= 0 ? '+' : ''}${_compactMoney(netCash)}',
                  subtitle:
                      'Thu ${_compactMoney(totalIn)} · Chi ${_compactMoney(totalOut)}',
                  color:
                      netCash >= 0 ? statusColors.success : statusColors.danger,
                  icon: Icons.account_balance_wallet_outlined,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _bigMetricCard(
                  context,
                  title: 'LUÂN CHUYỂN NGUYÊN LIỆU',
                  value:
                      '${netInv >= 0 ? '+' : ''}${AppFormat.quantity(netInv.toStringAsFixed(0))}',
                  subtitle:
                      'Nhập ${AppFormat.quantity(totalInbound.toStringAsFixed(0))} · Xuất ${AppFormat.quantity(totalOutbound.toStringAsFixed(0))}',
                  color: theme.colorScheme.primary,
                  icon: Icons.inventory_2_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _bigMetricCard(
                  context,
                  title: 'ĐỐI SOÁT CHUẨN',
                  value: '$matchRate% Khớp',
                  subtitle: '$cleanRuns/$totalRuns phiên thành công tuyệt đối',
                  color: statusColors.success,
                  icon: Icons.verified_user_outlined,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _bigMetricCard(
                  context,
                  title: 'ĐIỂM NÓNG TỒN ĐỌNG',
                  value: '$criticalCount mặt hàng',
                  subtitle: 'Mặt hàng có thời gian chưa xuất >=90 ngày',
                  color: criticalCount > 0
                      ? statusColors.danger
                      : statusColors.success,
                  icon: Icons.warning_amber_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Slide 2: Điểm nóng tồn đọng
  Widget _buildSlide2Stagnation(BuildContext context) {
    final theme = Theme.of(context);
    final critical =
        widget.stagnationItems.where((i) => i.severity == 'critical').toList();
    final stagnant =
        widget.stagnationItems.where((i) => i.severity == 'stagnant').toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '2. PHÂN TÍCH HÀNG TỒN ĐỌNG & RỦI RO LỖI THỜI',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Rà soát nguyên liệu không phát sinh sử dụng để tránh hết hạn và lãng phí.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          if (critical.isEmpty && stagnant.isEmpty)
            Card(
              color: Colors.green.shade50,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              child: const Padding(
                padding: EdgeInsets.all(24),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 36),
                    SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Kho nguyên liệu đang vận hành tốt! Không có mặt hàng nào tồn đọng trên 60 ngày.',
                        style: TextStyle(
                            color: Colors.green,
                            fontSize: 16,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Text(
              'Danh sách vật tư tồn đọng mức độ Nghiêm trọng (>=90 ngày) & Tồn đọng (>=60 ngày):',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: (critical + stagnant).take(6).length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, idx) {
                  final item = (critical + stagnant)[idx];
                  final isCritical = item.severity == 'critical';
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: (isCritical ? Colors.red : Colors.orange)
                          .withValues(alpha: 0.15),
                      child: Icon(
                        isCritical ? Icons.error_outline : Icons.warning_amber,
                        color: isCritical ? Colors.red : Colors.orange,
                        size: 20,
                      ),
                    ),
                    title: Text('${item.name} (${item.sku})',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      item.daysSinceLastIssue != null
                          ? '${item.daysSinceLastIssue} ngày từ lần xuất gần nhất'
                          : 'Chưa từng phát sinh phiếu xuất',
                    ),
                    trailing: Text(
                      'Tồn: ${item.quantity}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isCritical
                            ? Colors.red.shade800
                            : Colors.orange.shade800,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Slide 3: Dòng tiền & Cân đối quỹ
  Widget _buildSlide3Cashflow(BuildContext context) {
    final theme = Theme.of(context);
    final statusColors = context.statusColors;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '3. CHI TIẾT NHẬP – XUẤT & CÂN ĐỐI TỒN KHO',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Biến động thu chi tiền mặt theo từng chu kỳ kiểm toán. Bút toán được kiểm soát 4 mắt nghiêm ngặt.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          if (widget.cashflowBuckets.isEmpty)
            const Text('Chưa có dữ liệu dòng tiền trong kỳ này.')
          else
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(
                        label: Text('Chu kỳ',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Thu quỹ (VND)',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Chi quỹ (VND)',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Dòng tiền ròng (Net)',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Số bút toán',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  rows: widget.cashflowBuckets.map((b) {
                    final net = b.netValue;
                    return DataRow(
                      cells: [
                        DataCell(Text(b.bucket,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600))),
                        DataCell(Text(AppFormat.money(b.totalIn))),
                        DataCell(Text(AppFormat.money(b.totalOut))),
                        DataCell(
                          Text(
                            '${net >= 0 ? '+' : ''}${AppFormat.money(b.net)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: net >= 0
                                  ? statusColors.success
                                  : statusColors.danger,
                            ),
                          ),
                        ),
                        DataCell(Text('${b.journalCount}')),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Slide 4: Kiến nghị & Quyết nghị
  Widget _buildSlide4Actions(BuildContext context) {
    final theme = Theme.of(context);
    final critical =
        widget.stagnationItems.where((i) => i.severity == 'critical').toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '4. TRỌNG TÂM KIẾN NGHỊ & QUYẾT NGHỊ CUỘC HỌP',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Đề xuất các giải pháp xử lý cụ thể để Ban Giám đốc và các Trưởng bộ phận biểu quyết thông qua.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          _actionCard(
            context,
            index: '1',
            title: 'Kế hoạch xử lý nguyên liệu & hàng tồn kho',
            detail: critical.isNotEmpty
                ? 'Thành lập Hội đồng thanh lý nội bộ xử lý ${critical.length} mặt hàng ứ đọng >=90 ngày để giải phóng không gian lưu kho và giảm chi phí bảo quản.'
                : 'Tiếp tục rà soát định kỳ hàng tuần, duy trì định mức tồn kho tối thiểu cho các chi nhánh theo kế hoạch kinh doanh.',
          ),
          const SizedBox(height: 14),
          _actionCard(
            context,
            index: '2',
            title: 'Điều phối thanh khoản & Cân đối quỹ',
            detail:
                'Thực hiện đối soát cuối ngày giữa số liệu phần mềm và kiểm kê thực tế; ưu tiên xử lý chênh lệch và nguyên liệu cận date.',
          ),
          const SizedBox(height: 14),
          _actionCard(
            context,
            index: '3',
            title: 'Siết chặt quy trình kiểm soát 4 mắt (Dual-control)',
            detail:
                'Bắt buộc xác thực Mã PIN Kiểm Soát Viên khi duyệt lệnh giá trị lớn, kiểm tra kỹ chứng từ đối soát trước khi chốt phiên làm việc.',
          ),
          if (widget.staffNotes != null &&
              widget.staffNotes!.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            _actionCard(
              context,
              index: '4',
              title: 'Ý kiến phát biểu của bộ phận báo cáo',
              detail: widget.staffNotes!.trim(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bigMetricCard(
    BuildContext context, {
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    required IconData icon,
  }) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Icon(icon, color: color, size: 24),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionCard(
    BuildContext context, {
    required String index,
    required String title,
    required String detail,
  }) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: theme.colorScheme.primary,
              child: Text(index,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(detail,
                      style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _compactMoney(double amount) {
    final abs = amount.abs();
    if (abs >= 1000000000) {
      return '${(amount / 1000000000).toStringAsFixed(2)} tỷ VND';
    }
    if (abs >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)} tr VND';
    }
    return '${amount.toStringAsFixed(0)} VND';
  }
}
