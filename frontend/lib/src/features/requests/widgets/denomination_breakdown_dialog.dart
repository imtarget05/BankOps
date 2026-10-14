import 'package:flutter/material.dart';

import '../../../core/util/formatting.dart';

class DenominationResult {
  const DenominationResult({
    required this.totalAmount,
    required this.breakdownSummary,
    required this.counts,
  });

  final int totalAmount;
  final String breakdownSummary;
  final Map<int, int> counts;
}

/// Hộp thoại kiểm đếm và kê khai mệnh giá tiền mặt ngân hàng.
/// Hỗ trợ các mệnh giá VND lưu hành: 500k, 200k, 100k, 50k, 20k, 10k, 5k, 2k, 1k.
class DenominationBreakdownDialog extends StatefulWidget {
  const DenominationBreakdownDialog({super.key, this.initialCounts});

  final Map<int, int>? initialCounts;

  static const List<int> denominations = [
    500000,
    200000,
    100000,
    50000,
    20000,
    10000,
    5000,
    2000,
    1000,
  ];

  @override
  State<DenominationBreakdownDialog> createState() =>
      _DenominationBreakdownDialogState();
}

class _DenominationBreakdownDialogState
    extends State<DenominationBreakdownDialog> {
  late final Map<int, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final denom in DenominationBreakdownDialog.denominations)
        denom: TextEditingController(
          text: (widget.initialCounts?[denom] ?? 0) > 0
              ? widget.initialCounts![denom].toString()
              : '',
        ),
    };
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  int get _totalAmount {
    int sum = 0;
    for (final denom in DenominationBreakdownDialog.denominations) {
      final count = int.tryParse(_controllers[denom]!.text.trim()) ?? 0;
      sum += denom * count;
    }
    return sum;
  }

  int get _totalNotes {
    int notes = 0;
    for (final denom in DenominationBreakdownDialog.denominations) {
      notes += int.tryParse(_controllers[denom]!.text.trim()) ?? 0;
    }
    return notes;
  }

  void _reset() {
    setState(() {
      for (final c in _controllers.values) {
        c.text = '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _totalAmount;
    final totalNotes = _totalNotes;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF059669).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.point_of_sale_rounded, color: Color(0xFF059669)),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bảng Kê Mệnh Giá Tiền Mặt',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Kiểm đếm số lượng tờ theo mệnh giá VND',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Tổng tiền kiểm đếm', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        Text(
                          '${AppFormat.number(total.toString())} đ',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF059669),
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('Tổng số tờ', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        Text(
                          '$totalNotes tờ',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              for (final denom in DenominationBreakdownDialog.denominations) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 100,
                        child: Text(
                          '${AppFormat.number(denom.toString())} đ',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          key: Key('denom-input-$denom'),
                          controller: _controllers[denom],
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: '0',
                            suffixText: 'tờ',
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 100,
                        child: Text(
                          '${AppFormat.number(((int.tryParse(_controllers[denom]!.text.trim()) ?? 0) * denom).toString())} đ',
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            fontSize: 12,
                            color: (int.tryParse(_controllers[denom]!.text.trim()) ?? 0) > 0
                                ? theme.colorScheme.primary
                                : Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _reset,
          child: const Text('Xóa trắng'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Đóng'),
        ),
        FilledButton(
          key: const Key('apply-denomination-btn'),
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF059669)),
          onPressed: () {
            final counts = <int, int>{};
            final parts = <String>[];
            for (final denom in DenominationBreakdownDialog.denominations) {
              final cnt = int.tryParse(_controllers[denom]!.text.trim()) ?? 0;
              if (cnt > 0) {
                counts[denom] = cnt;
                final label = denom >= 1000 ? '${denom ~/ 1000}k' : '$denom';
                parts.add('$label: $cnt tờ');
              }
            }
            final summary = parts.isEmpty
                ? ''
                : 'Bảng kê: ${parts.join(', ')} (Tổng: ${AppFormat.number(total.toString())} đ)';

            Navigator.of(context).pop(
              DenominationResult(
                totalAmount: total,
                breakdownSummary: summary,
                counts: counts,
              ),
            );
          },
          child: const Text('Áp dụng vào phiếu'),
        ),
      ],
    );
  }
}
