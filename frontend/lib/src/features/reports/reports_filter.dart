import 'package:flutter/material.dart';

enum ReportGranularity { daily, monthly }

class ReportsFilter extends StatelessWidget {
  const ReportsFilter({
    super.key,
    required this.granularity,
    required this.onGranularityChanged,
    this.dateRange,
    this.onDateRangeChanged,
  });

  final ReportGranularity granularity;
  final ValueChanged<ReportGranularity> onGranularityChanged;
  final DateTimeRange? dateRange;
  final ValueChanged<DateTimeRange?>? onDateRangeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sevenDaysAgo = today.subtract(const Duration(days: 7));
    final thirtyDaysAgo = today.subtract(const Duration(days: 30));

    // Kiểm tra preset nào đang được chọn
    final isTodaySelected = dateRange != null &&
        dateRange!.start.year == today.year &&
        dateRange!.start.month == today.month &&
        dateRange!.start.day == today.day &&
        dateRange!.end.difference(dateRange!.start).inDays <= 1;

    final is7DaysSelected = dateRange != null &&
        !isTodaySelected &&
        dateRange!.start.difference(sevenDaysAgo).inDays.abs() <= 1;

    final is30DaysSelected = dateRange != null &&
        !isTodaySelected &&
        !is7DaysSelected &&
        dateRange!.start.difference(thirtyDaysAgo).inDays.abs() <= 1;

    final isAllSelected = dateRange == null;
    final isCustomSelected = dateRange != null &&
        !isTodaySelected &&
        !is7DaysSelected &&
        !is30DaysSelected;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Granularity toggle (Ngày / Tháng)
            SegmentedButton<ReportGranularity>(
              key: const Key('reports-granularity-toggle'),
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: WidgetStateProperty.all(
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              segments: const [
                ButtonSegment(
                  value: ReportGranularity.daily,
                  label: Text('Theo ngày'),
                  icon: Icon(Icons.calendar_today_outlined, size: 14),
                ),
                ButtonSegment(
                  value: ReportGranularity.monthly,
                  label: Text('Theo tháng'),
                  icon: Icon(Icons.date_range_outlined, size: 14),
                ),
              ],
              selected: {granularity},
              onSelectionChanged: (set) {
                if (set.isNotEmpty) onGranularityChanged(set.first);
              },
            ),
            const SizedBox(width: 12),
            Container(
              height: 24,
              width: 1,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 12),

            // Nút preset: Tất cả
            _PresetChip(
              label: 'Tất cả',
              isSelected: isAllSelected,
              onTap: () => onDateRangeChanged?.call(null),
            ),
            const SizedBox(width: 6),

            // Nút preset: Hôm nay
            _PresetChip(
              label: 'Hôm nay',
              isSelected: isTodaySelected,
              onTap: () {
                onDateRangeChanged?.call(
                  DateTimeRange(
                    start: today,
                    end: today.add(const Duration(hours: 23, minutes: 59)),
                  ),
                );
              },
            ),
            const SizedBox(width: 6),

            // Nút preset: 7 ngày qua
            _PresetChip(
              label: '7 ngày qua',
              isSelected: is7DaysSelected,
              onTap: () {
                onDateRangeChanged?.call(
                  DateTimeRange(start: sevenDaysAgo, end: now),
                );
              },
            ),
            const SizedBox(width: 6),

            // Nút preset: 30 ngày qua
            _PresetChip(
              label: '30 ngày qua',
              isSelected: is30DaysSelected,
              onTap: () {
                onDateRangeChanged?.call(
                  DateTimeRange(start: thirtyDaysAgo, end: now),
                );
              },
            ),
            const SizedBox(width: 6),

            // Nút chọn ngày tùy chỉnh
            OutlinedButton.icon(
              key: const Key('reports-date-range-btn'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                side: BorderSide(
                  color: isCustomSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant,
                ),
                backgroundColor: isCustomSelected
                    ? theme.colorScheme.primary.withValues(alpha: 0.08)
                    : null,
              ),
              icon: Icon(
                Icons.calendar_month_outlined,
                size: 15,
                color: isCustomSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              label: Text(
                isCustomSelected
                    ? '${dateRange!.start.toIso8601String().substring(0, 10)} → ${dateRange!.end.toIso8601String().substring(0, 10)}'
                    : 'Tùy chọn ngày',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      isCustomSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isCustomSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                ),
              ),
              onPressed: () async {
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2025),
                  lastDate: DateTime(2027),
                  initialDateRange: dateRange,
                );
                if (picked != null) {
                  onDateRangeChanged?.call(picked);
                }
              },
            ),

            if (dateRange != null) ...[
              const SizedBox(width: 4),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Xóa bộ lọc ngày',
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => onDateRangeChanged?.call(null),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? primary
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? primary : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
