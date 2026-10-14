import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/util/csv_export.dart';
import '../../../core/util/formatting.dart';
import '../../../core/util/report_excel.dart';
import '../../../core/util/report_share.dart';
import '../../../core/widgets/state_views.dart';
import '../../../data/models/dtos.dart';

class CashflowChart extends StatelessWidget {
  const CashflowChart({super.key, required this.buckets});

  final List<CashflowBucket> buckets;

  @override
  Widget build(BuildContext context) {
    if (buckets.isEmpty) {
      return const EmptyView(
        title: 'Chưa có dữ liệu dòng tiền mô phỏng',
        subtitle:
            'Tạo phiếu quỹ và được Checker duyệt — biểu đồ thu/chi sẽ hiện ở đây.',
        icon: Icons.savings_outlined,
      );
    }
    final statusColors = context.statusColors;
    final scheme = Theme.of(context).colorScheme;

    var maxY = 100000.0;
    double totalIn = 0;
    double totalOut = 0;
    int totalJournals = 0;
    for (final b in buckets) {
      if (b.inValue > maxY) maxY = b.inValue;
      if (b.outValue > maxY) maxY = b.outValue;
      totalIn += b.inValue;
      totalOut += b.outValue;
      totalJournals += b.journalCount;
    }
    maxY *= 1.25;
    final netFlow = totalIn - totalOut;

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
                    label: 'Thu quỹ mô phỏng (VND): ${AppFormat.money(totalIn.toStringAsFixed(0))}',
                  ),
                  _LegendDot(
                    color: statusColors.danger,
                    label: 'Chi quỹ mô phỏng (VND): ${AppFormat.money(totalOut.toStringAsFixed(0))}',
                  ),
                ],
              ),
            ),
            IconButton(
              key: const Key('export-cashflow-csv-btn'),
              icon: const Icon(Icons.content_copy_outlined, size: 20),
              tooltip: 'Sao chép CSV dòng tiền',
              onPressed: () => CsvExport.copyToClipboard(
                context,
                label: 'dòng tiền mô phỏng',
                headers: ReportExcel.cashflowHeaders,
                rows: [
                  for (final b in buckets)
                    [b.bucket, b.totalIn, b.totalOut, b.net, b.journalCount],
                ],
              ),
            ),
            IconButton(
              key: const Key('export-cashflow-xlsx-btn'),
              icon: const Icon(Icons.download_outlined, size: 20),
              tooltip: 'Tải file Excel dòng tiền',
              onPressed: () => ReportShare.shareXlsx(
                context,
                filename: 'dong-tien-mo-phong.xlsx',
                bytes: ReportExcel.encodeCashflow(buckets),
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
                        toY: buckets[i].inValue,
                        color: statusColors.success,
                        width: 14,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      BarChartRodData(
                        toY: buckets[i].outValue,
                        color: statusColors.danger,
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
                      'BẢNG ĐỐI CHIẾU DÒNG TIỀN CHI TIẾT',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                    ),
                    Text(
                      'Net: ${netFlow >= 0 ? '+' : ''}${AppFormat.money(netFlow.toStringAsFixed(0))} · $totalJournals bút toán',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: netFlow >= 0 ? statusColors.success : statusColors.danger,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              for (final b in buckets)
                ListTile(
                  dense: true,
                  leading: Icon(Icons.savings_outlined, color: scheme.primary),
                  title: Text(b.bucket, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('Số bút toán: ${b.journalCount} (MÔ PHỎNG)'),
                  trailing: Text(
                    '+${b.totalIn} / -${b.totalOut} VND',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: b.netValue >= 0 ? statusColors.success : statusColors.danger,
                        ),
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
