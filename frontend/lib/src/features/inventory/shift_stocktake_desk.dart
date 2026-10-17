import 'package:flutter/material.dart';

/// Dòng đối soát cho quầy kiểm kê. Số lý thuyết luôn được tính từ luồng ca,
/// không lấy trực tiếp từ ô kiểm thực tế.
class ShiftStocktakeLine {
  const ShiftStocktakeLine({
    required this.name,
    required this.unit,
    required this.openingQty,
    required this.receivedQty,
    required this.usedQty,
    required this.countedQty,
    this.reason = '',
  });

  final String name;
  final String unit;
  final double openingQty;
  final double receivedQty;
  final double usedQty;
  final double countedQty;
  final String reason;

  double get theoreticalQty => openingQty + receivedQty - usedQty;
  double get varianceQty => countedQty - theoreticalQty;
  bool get hasVariance => varianceQty.abs() >= 0.001;
}

/// Khung thao tác nhanh cho ca làm việc tại quầy.
///
/// Backend hiện có chỉ trả bản ghi kiểm kê cuối ca, vì vậy widget này nhận
/// snapshot dữ liệu đã chuẩn hóa từ màn kho và không tự ghi dữ liệu.
class ShiftStocktakeDesk extends StatefulWidget {
  const ShiftStocktakeDesk({
    super.key,
    required this.lines,
    this.onStartShiftStocktake,
  });

  final List<ShiftStocktakeLine> lines;
  final VoidCallback? onStartShiftStocktake;

  @override
  State<ShiftStocktakeDesk> createState() => _ShiftStocktakeDeskState();
}

class _ShiftStocktakeDeskState extends State<ShiftStocktakeDesk> {
  var _shift = _Shift.morning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasVariance = widget.lines.any((line) => line.hasVariance);

    return Semantics(
      container: true,
      label: 'Quầy kiểm kê theo ca',
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              runSpacing: 12,
              spacing: 12,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Quầy kiểm kê theo ca',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(
                      '${_shift.title} · ${_shift.hours}',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: widget.onStartShiftStocktake,
                    icon: const Icon(Icons.playlist_add_check_outlined),
                    label: const Text('Mở phiên kiểm kê'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _ShiftTabs(
              selected: _shift,
              onChanged: (value) => setState(() => _shift = value),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: hasVariance
                    ? theme.colorScheme.errorContainer
                    : theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    hasVariance
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline,
                    color: hasVariance
                        ? theme.colorScheme.onErrorContainer
                        : theme.colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hasVariance
                          ? 'Có chênh lệch cần đối soát trước khi chốt ca.'
                          : 'Số thực tế khớp sổ theo công thức cuối ca.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: hasVariance
                            ? theme.colorScheme.onErrorContainer
                            : theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Tồn lý thuyết = Tồn đầu + Nhập − Sử dụng. '
              'Độ lệch = Kiểm thực tế − Tồn lý thuyết.',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            _ReconciliationTable(lines: widget.lines),
          ],
        ),
      ),
    );
  }
}

class _ShiftTabs extends StatelessWidget {
  const _ShiftTabs({required this.selected, required this.onChanged});

  final _Shift selected;
  final ValueChanged<_Shift> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _Shift.values
            .map(
              (shift) => ChoiceChip(
                label: Text('${shift.title}\n${shift.hours}',
                    textAlign: TextAlign.center),
                selected: selected == shift,
                onSelected: (_) => onChanged(shift),
                showCheckmark: false,
                labelStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
            )
            .toList(),
      );
}

class _ReconciliationTable extends StatelessWidget {
  const _ReconciliationTable({required this.lines});

  final List<ShiftStocktakeLine> lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const headerStyle = TextStyle(fontWeight: FontWeight.w800);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              minWidth:
                  constraints.maxWidth < 1080 ? 1080 : constraints.maxWidth),
          child: DataTable(
            headingRowColor: WidgetStatePropertyAll(
                theme.colorScheme.surfaceContainerHighest),
            columns: const [
              DataColumn(label: Text('Nguyên liệu', style: headerStyle)),
              DataColumn(label: Text('ĐVT', style: headerStyle)),
              DataColumn(
                  label: Text('Tồn đầu', style: headerStyle), numeric: true),
              DataColumn(
                  label: Text('Nhập', style: headerStyle), numeric: true),
              DataColumn(
                  label: Text('Sử dụng', style: headerStyle), numeric: true),
              DataColumn(
                  label: Text('Tồn lý thuyết', style: headerStyle),
                  numeric: true),
              DataColumn(
                  label: Text('Kiểm thực tế', style: headerStyle),
                  numeric: true),
              DataColumn(
                  label: Text('Độ lệch', style: headerStyle), numeric: true),
              DataColumn(label: Text('Trạng thái', style: headerStyle)),
              DataColumn(label: Text('Lý do', style: headerStyle)),
            ],
            rows: lines.map((line) => _row(context, line)).toList(),
          ),
        ),
      ),
    );
  }

  DataRow _row(BuildContext context, ShiftStocktakeLine line) {
    final color = line.hasVariance
        ? Theme.of(context).colorScheme.error
        : const Color(0xFF15803D);
    final status = line.hasVariance ? 'Cần đối soát' : 'Khớp';
    final diff = line.varianceQty;
    final diffText = '${diff > 0 ? '+' : ''}${_qty(diff)}';
    return DataRow(cells: [
      DataCell(
          Text(line.name, style: const TextStyle(fontWeight: FontWeight.w700))),
      DataCell(Text(line.unit)),
      DataCell(Text(_qty(line.openingQty))),
      DataCell(Text(_qty(line.receivedQty))),
      DataCell(Text(_qty(line.usedQty))),
      DataCell(Text(_qty(line.theoreticalQty))),
      DataCell(Text(_qty(line.countedQty))),
      DataCell(Text('Lệch $diffText',
          style: TextStyle(color: color, fontWeight: FontWeight.w800))),
      DataCell(Text(status,
          style: TextStyle(color: color, fontWeight: FontWeight.w800))),
      DataCell(Text(line.reason.isEmpty ? '—' : line.reason)),
    ]);
  }

  String _qty(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2);
}

enum _Shift {
  morning('Ca Sáng', '07:30 – 15:00'),
  afternoon('Ca Chiều', '15:00 – 23:00'),
  split('Ca Lỡ', '07:30 – 18:00');

  const _Shift(this.title, this.hours);
  final String title;
  final String hours;
}
