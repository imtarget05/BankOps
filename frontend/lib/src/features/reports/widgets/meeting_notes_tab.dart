import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/util/report_share.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/models/dtos.dart';
import '../reports_filter.dart';
import 'meeting_report_pdf.dart';

/// Tab đánh giá vận hành & chuẩn bị nội dung họp giao ban cho nhân viên.
class MeetingNotesTab extends StatefulWidget {
  const MeetingNotesTab({
    super.key,
    required this.inventoryBuckets,
    required this.cashflowBuckets,
    required this.stagnationItems,
    required this.reconciliations,
    required this.granularity,
    this.dateRange,
    required this.onOpenPresentation,
  });

  final List<InventoryBucket> inventoryBuckets;
  final List<CashflowBucket> cashflowBuckets;
  final List<StagnationItem> stagnationItems;
  final List<ReconciliationRun> reconciliations;
  final ReportGranularity granularity;
  final DateTimeRange? dateRange;
  final VoidCallback onOpenPresentation;

  @override
  State<MeetingNotesTab> createState() => _MeetingNotesTabState();
}

class _MeetingNotesTabState extends State<MeetingNotesTab> {
  late String _selectedStatus;
  final TextEditingController _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final critical =
        widget.stagnationItems.where((i) => i.severity == 'critical').length;
    _selectedStatus =
        critical > 0 ? 'Cảnh báo rủi ro cao' : 'Vận hành đạt chuẩn';
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
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
        staffAssessment: _selectedStatus,
        staffNotes: _notesController.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Phân tích dữ liệu để sinh talking points
    final critical =
        widget.stagnationItems.where((i) => i.severity == 'critical').toList();
    double totalIn = 0;
    double totalOut = 0;
    for (final b in widget.cashflowBuckets) {
      totalIn += b.inValue;
      totalOut += b.outValue;
    }
    final netCash = totalIn - totalOut;
    final totalRuns = widget.reconciliations.length;
    final cleanRuns =
        widget.reconciliations.where((r) => r.exceptions.isEmpty).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Thanh công cụ nhanh phục vụ cuộc họp
        Card(
          elevation: 0,
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
                color: theme.colorScheme.primary.withValues(alpha: 0.2)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.assessment_outlined,
                        color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Báo Cáo Đánh Giá Hoạt Động & Vận Hành',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                FilledButton.icon(
                  key: const Key('btn-export-meeting-pdf'),
                  onPressed: _printPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('Xuất Báo Cáo A4'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Khối 1: Đánh giá sức khỏe vận hành của nhân viên
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '1. ĐÁNH GIÁ TRẠNG THÁI VẬN HÀNH (STAFF ASSESSMENT)',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Chọn nhận định đánh giá trước khi bước vào phòng họp lãnh đạo:',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('🟢 Vận hành đạt chuẩn (Ổn định)'),
                      selected: _selectedStatus == 'Vận hành đạt chuẩn',
                      onSelected: (val) {
                        if (val)
                          setState(
                              () => _selectedStatus = 'Vận hành đạt chuẩn');
                      },
                    ),
                    ChoiceChip(
                      label: const Text('🟡 Cần lưu ý theo dõi'),
                      selected: _selectedStatus == 'Cần lưu ý theo dõi',
                      onSelected: (val) {
                        if (val)
                          setState(
                              () => _selectedStatus = 'Cần lưu ý theo dõi');
                      },
                    ),
                    ChoiceChip(
                      label: const Text('🔴 Cảnh báo rủi ro cao'),
                      selected: _selectedStatus == 'Cảnh báo rủi ro cao',
                      onSelected: (val) {
                        if (val)
                          setState(
                              () => _selectedStatus = 'Cảnh báo rủi ro cao');
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Khối 2: Trọng tâm phát biểu & Kiến nghị tự động (Auto Talking Points)
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome,
                        size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      '2. TRỌNG TÂM PHÁT BIỂU & KIẾN NGHỊ CUỘC HỌP (TALKING POINTS)',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _bulletItem(
                  context,
                  title: 'Thanh khoản Quỹ:',
                  content: netCash >= 0
                      ? 'Dòng tiền thặng dư ${_compactMoney(netCash)}. Đảm bảo khả năng thanh toán cho chi nhánh.'
                      : 'Cảnh báo thâm hụt dòng tiền ${_compactMoney(netCash.abs())}. Cần đề xuất điều chuyển vốn giữa các quỹ.',
                  isAlert: netCash < 0,
                ),
                _bulletItem(
                  context,
                  title: 'Nguyên liệu tồn kho:',
                  content: critical.isNotEmpty
                      ? 'Phát hiện ${critical.length} mặt hàng tồn đọng >=90 ngày chưa từng xuất. Đề xuất thành lập hội đồng thanh lý hoặc luân chuyển nội bộ.'
                      : 'Vật tư luân chuyển nhịp nhàng, không có điểm nóng tồn đọng nghiêm trọng.',
                  isAlert: critical.isNotEmpty,
                ),
                _bulletItem(
                  context,
                  title: 'Kiểm soát & Đối soát:',
                  content: totalRuns - cleanRuns > 0
                      ? 'Có ${totalRuns - cleanRuns} phiên đối soát phát hiện ngoại lệ chênh lệch. Đề nghị người phụ trách giải trình biên bản đối soát.'
                      : '100% phiên đối soát khớp số liệu, tuân thủ chặt chẽ quy trình phê duyệt kiểm soát.',
                  isAlert: totalRuns - cleanRuns > 0,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Khối 3: Ghi chú nhận định cá nhân
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '3. GHI CHÚ PHÁT BIỂU RIÊNG CỦA NHÂN VIÊN',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Nhập thêm ý kiến cá nhân để xuất kèm báo cáo PDF hoặc sao chép vào biên bản họp:',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('input-meeting-staff-notes'),
                  controller: _notesController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText:
                        'Ví dụ: Chi nhánh đề xuất bổ sung thêm 200 cuốn Sổ tiết kiệm loại 10 trang trước ngày 20...',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      AppToast.info(context,
                          'Đã lưu ghi chú vào phiên làm việc hiện tại.');
                    },
                    icon: const Icon(Icons.save_outlined, size: 16),
                    label: const Text('Lưu ghi chú'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _bulletItem(
    BuildContext context, {
    required String title,
    required String content,
    required bool isAlert,
  }) {
    final statusColors = context.statusColors;
    final color = isAlert ? statusColors.danger : statusColors.success;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 4, right: 8),
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: Theme.of(context).textTheme.bodyMedium,
                children: [
                  TextSpan(
                      text: '$title ',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: content),
                ],
              ),
            ),
          ),
        ],
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
