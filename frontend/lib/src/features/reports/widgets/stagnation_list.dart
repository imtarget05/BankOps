import 'package:flutter/material.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/util/csv_export.dart';
import '../../../core/util/report_excel.dart';
import '../../../core/util/report_share.dart';
import '../../../core/widgets/state_views.dart';
import '../../../data/models/dtos.dart';

class StagnationList extends StatefulWidget {
  const StagnationList({super.key, required this.items});

  final List<StagnationItem> items;

  @override
  State<StagnationList> createState() => _StagnationListState();
}

class _StagnationListState extends State<StagnationList> {
  String _severityFilter = 'all';

  @override
  Widget build(BuildContext context) {
    final isVi = context.isVietnamese;
    if (widget.items.isEmpty) {
      return EmptyView(
        title: isVi
            ? 'Không có hàng tồn đọng cần cảnh báo'
            : 'No stagnant inventory alerts',
        subtitle: isVi
            ? 'Mọi vật tư đều luân chuyển tốt trong ngưỡng 30/60/90 ngày.'
            : 'All materials are moving well within 30/60/90 days.',
        icon: Icons.check_circle_outline,
      );
    }
    final statusColors = context.statusColors;
    final theme = Theme.of(context);

    final criticalCount = widget.items.where((i) => i.severity == 'critical').length;
    final stagnantCount = widget.items.where((i) => i.severity == 'stagnant').length;
    final watchCount = widget.items.where((i) => i.severity == 'watch').length;

    final filteredItems = _severityFilter == 'all'
        ? widget.items
        : widget.items.where((i) => i.severity == _severityFilter).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Thanh phân tầng rủi ro & nút xuất file
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    label: Text(isVi ? 'Tất cả (${widget.items.length})' : 'All (${widget.items.length})'),
                    selected: _severityFilter == 'all',
                    onSelected: (_) => setState(() => _severityFilter = 'all'),
                  ),
                  FilterChip(
                    avatar: const Icon(Icons.error_outline, size: 16, color: Colors.red),
                    label: Text(isVi ? 'Nghiêm trọng ($criticalCount)' : 'Critical ($criticalCount)'),
                    selected: _severityFilter == 'critical',
                    onSelected: (_) => setState(() => _severityFilter = 'critical'),
                  ),
                  FilterChip(
                    avatar: const Icon(Icons.warning_amber, size: 16, color: Colors.orange),
                    label: Text(isVi ? 'Tồn đọng ($stagnantCount)' : 'Stagnant ($stagnantCount)'),
                    selected: _severityFilter == 'stagnant',
                    onSelected: (_) => setState(() => _severityFilter = 'stagnant'),
                  ),
                  FilterChip(
                    avatar: const Icon(Icons.visibility_outlined, size: 16, color: Colors.amber),
                    label: Text(isVi ? 'Theo dõi ($watchCount)' : 'Watch ($watchCount)'),
                    selected: _severityFilter == 'watch',
                    onSelected: (_) => setState(() => _severityFilter = 'watch'),
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('export-stagnation-csv-btn'),
                  onPressed: () => CsvExport.copyToClipboard(
                    context,
                    label: isVi ? 'tồn đọng' : 'stagnant stock',
                    headers: ReportExcel.stagnationHeaders,
                    rows: [
                      for (final item in widget.items)
                        [
                          item.sku,
                          item.name,
                          item.quantity,
                          item.daysSinceLastIssue,
                          item.severity
                        ],
                    ],
                  ),
                  icon: const Icon(Icons.content_copy_outlined, size: 18),
                  label: Text(isVi ? 'Sao chép CSV' : 'Copy CSV'),
                ),
                OutlinedButton.icon(
                  key: const Key('export-stagnation-xlsx-btn'),
                  onPressed: () => ReportShare.shareXlsx(
                    context,
                    filename: 'ton-dong.xlsx',
                    bytes: ReportExcel.encodeStagnation(widget.items),
                  ),
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: Text(isVi ? 'Tải Excel' : 'Download Excel'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Thẻ cảnh báo tóm tắt cho phòng họp
        if (criticalCount > 0)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: statusColors.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: statusColors.danger.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: statusColors.danger, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isVi
                        ? 'Đề xuất giao ban: Có $criticalCount mặt hàng không luân chuyển trên 90 ngày. Cần trình Ban Giám đốc phương án thanh lý hoặc điều chuyển kho trước ngày 30.'
                        : 'Meeting proposal: $criticalCount non-moving items over 90 days. Present liquidation or transfer plan to executive board.',
                    style: TextStyle(color: statusColors.danger, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),

        // Danh sách thẻ chi tiết
        for (final item in filteredItems)
          Card(
            key: Key('stagnation-item-${item.sku}'),
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: item.severity == 'critical'
                    ? statusColors.danger.withValues(alpha: 0.4)
                    : theme.colorScheme.outlineVariant,
              ),
            ),
            child: ListTile(
              leading: Icon(
                _iconFor(item.severity),
                color: _colorFor(item.severity, statusColors),
              ),
              title: Text('${item.name} (${item.sku})', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                item.daysSinceLastIssue == null
                    ? 'Chưa từng xuất kho · Tồn: ${item.quantity}'
                    : '${item.daysSinceLastIssue} ngày từ lần xuất gần nhất · Tồn: ${item.quantity}',
              ),
              trailing: Chip(
                label: Text(
                  _labelFor(item.severity),
                  style: TextStyle(
                    color: _colorFor(item.severity, statusColors),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                side: BorderSide(color: _colorFor(item.severity, statusColors)),
              ),
            ),
          ),
      ],
    );
  }

  IconData _iconFor(String severity) {
    switch (severity) {
      case 'critical':
        return Icons.error_outline;
      case 'stagnant':
        return Icons.warning_amber_rounded;
      case 'watch':
        return Icons.visibility_outlined;
      default:
        return Icons.check_circle_outline;
    }
  }

  Color _colorFor(String severity, AppStatusColors colors) {
    switch (severity) {
      case 'critical':
        return colors.danger;
      case 'stagnant':
      case 'watch':
        return colors.warning;
      default:
        return colors.success;
    }
  }

  String _labelFor(String severity) {
    switch (severity) {
      case 'critical':
        return 'Nghiêm trọng (>=90 ngày)';
      case 'stagnant':
        return 'Tồn đọng (>=60 ngày)';
      case 'watch':
        return 'Theo dõi (>=30 ngày)';
      default:
        return 'Bình thường';
    }
  }
}
