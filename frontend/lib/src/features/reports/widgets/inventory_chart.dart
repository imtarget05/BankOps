import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/util/csv_export.dart';
import '../../../core/util/formatting.dart';
import '../../../core/util/report_excel.dart';
import '../../../core/util/report_share.dart';
import '../../../core/widgets/state_views.dart';
import '../../../data/models/dtos.dart';

class InventoryChart extends StatelessWidget {
  const InventoryChart({super.key, required this.buckets});

  final List<InventoryBucket> buckets;

  @override
  Widget build(BuildContext context) {
    if (buckets.isEmpty) {
      return const EmptyView(
        title: 'Chưa có dữ liệu nhập/xuất kho',
        subtitle:
            'Tạo phiếu kho và được Checker duyệt — biểu đồ nhập/xuất sẽ hiện ở đây.',
        icon: Icons.inventory_2_outlined,
      );
    }
    final statusColors = context.statusColors;
    final scheme = Theme.of(context).colorScheme;

    var maxY = 10.0;
    double totalIn = 0;
    double totalOut = 0;
    int totalReceipts = 0;
    int totalIssues = 0;
    for (final b in buckets) {
      if (b.inboundValue > maxY) maxY = b.inboundValue;
      if (b.outboundValue > maxY) maxY = b.outboundValue;
      totalIn += b.inboundValue;
      totalOut += b.outboundValue;
      totalReceipts += b.receiptCount;
      totalIssues += b.issueCount;
    }
    maxY *= 1.25;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Legend & nút xuất file
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _LegendDot(
                    color: statusColors.success,
                    label: 'Nhập kho (Inbound): ${AppFormat.quantity(totalIn.toStringAsFixed(0))}',
                  ),
                  _LegendDot(
                    color: statusColors.warning,
                    label: 'Xuất kho (Outbound): ${AppFormat.quantity(totalOut.toStringAsFixed(0))}',
                  ),
                ],
              ),
            ),
            IconButton(
              key: const Key('export-inventory-csv-btn'),
              icon: const Icon(Icons.content_copy_outlined, size: 20),
              tooltip: 'Sao chép CSV nhập/xuất kho',
              onPressed: () => CsvExport.copyToClipboard(
                context,
                label: 'nhập/xuất kho',
                headers: ReportExcel.inventoryHeaders,
                rows: [
                  for (final b in buckets)
                    [
                      b.bucket,
                      b.inboundQty,
                      b.outboundQty,
                      b.netQty,
                      b.receiptCount,
                      b.issueCount
                    ],
                ],
              ),
            ),
            IconButton(
              key: const Key('export-inventory-xlsx-btn'),
              icon: const Icon(Icons.download_outlined, size: 20),
              tooltip: 'Tải file Excel nhập/xuất kho',
              onPressed: () => ReportShare.shareXlsx(
                context,
                filename: 'nhap-xuat-kho.xlsx',
                bytes: ReportExcel.encodeInventory(buckets),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Biểu đồ cột
        SizedBox(
          height: 260,
          child: BarChart(
            BarChartData(
              maxY: maxY,
              alignment: BarChartAlignment.spaceAround,
              gridData: const FlGridData(show: true, drawVerticalLine: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= buckets.length) {
                        return const SizedBox.shrink();
                      }
                      final label = buckets[idx].bucket;
                      final shortLabel =
                          label.length > 5 ? label.substring(5) : label;
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          shortLabel,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < buckets.length; i++)
                  BarChartGroupData(
                    x: i,
                    barsSpace: 4,
                    barRods: [
                      BarChartRodData(
                        toY: buckets[i].inboundValue,
                        color: statusColors.success,
                        width: 14,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      BarChartRodData(
                        toY: buckets[i].outboundValue,
                        color: statusColors.warning,
                        width: 14,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Bảng đối chiếu số liệu chi tiết
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'BẢNG ĐỐI CHIẾU NHẬP/XUẤT KHO CHI TIẾT',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                    ),
                    Text(
                      '${buckets.length} kỳ · $totalReceipts phiếu nhập · $totalIssues phiếu xuất',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              for (final b in buckets)
                ListTile(
                  dense: true,
                  leading: Icon(Icons.inventory_2_outlined, color: scheme.primary),
                  title: Text(b.bucket, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    'Phiếu nhập: ${b.receiptCount} · Phiếu xuất: ${b.issueCount}',
                  ),
                  trailing: Text(
                    '+${b.inboundQty} / -${b.outboundQty} (Net: ${b.netQty})',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
