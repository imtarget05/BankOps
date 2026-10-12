import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/formatting.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/dtos.dart';

class ActivityCenter extends StatelessWidget {
  const ActivityCenter({
    super.key,
    required this.events,
    this.onRefresh,
  });

  final List<ActivityEvent> events;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Center(child: EmptyView(title: 'Chưa có hoạt động nào được ghi nhận.'));
    }
    final statusColors = context.statusColors;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hoạt động & Tiến trình nền',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Toàn bộ lịch sử thao tác lập lệnh, phê duyệt, đối soát và tiến trình nền bất biến',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (onRefresh != null) ...[
              const SizedBox(width: 16),
              FilledButton.icon(
                key: const Key('activity-resync-btn'),
                onPressed: onRefresh,
                icon: const Icon(Icons.sync_rounded, size: 18),
                label: const Text('Đồng bộ lại'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A8A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 20),
        for (final e in events)
          Container(
            key: Key('activity-item-${e.id}'),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _colorFor(e.status, statusColors).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _iconFor(e.status),
                          color: _colorFor(e.status, statusColors),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _formatMessageKey(e.messageKey),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: _colorFor(e.status, statusColors).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    e.status.toUpperCase(),
                                    style: TextStyle(
                                      color: _colorFor(e.status, statusColors),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Mã đối tượng: ${e.subjectId} • ID: ${e.id.length > 8 ? "${e.id.substring(0, 8)}…" : e.id}',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              AppFormat.dateTime(e.occurredAt),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (e.processed != null && e.total != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '${e.processed}/${e.total}',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF1E3A8A),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (e.processed != null && e.total != null && e.total! > 0) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (e.processed! / e.total!).clamp(0.0, 1.0),
                        minHeight: 6,
                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _formatMessageKey(String key) {
    if (key.contains('reconcile')) return 'Đối soát Sổ cái và Kho quỹ định kỳ';
    if (key.contains('approve')) return 'Kiểm soát viên phê duyệt giao dịch';
    if (key.contains('reject')) return 'Từ chối yêu cầu giao dịch kiểm soát';
    if (key.contains('create') || key.contains('draft')) return 'Giao dịch viên lập phiếu mới';
    if (key.contains('submit')) return 'Gửi phiếu lên hòm thư duyệt 4-Mắt';
    if (key.contains('transfer')) return 'Điều chuyển quỹ tiền mặt liên chi nhánh';
    return key;
  }

  IconData _iconFor(String status) {
    switch (status) {
      case 'posted':
      case 'succeeded':
      case 'confirmed':
      case 'created':
        return Icons.check_circle_rounded;
      case 'pending':
      case 'running':
      case 'queued':
        return Icons.schedule_rounded;
      case 'failed':
      case 'rejected':
        return Icons.error_outline_rounded;
      default:
        return Icons.notifications_none_rounded;
    }
  }

  Color _colorFor(String status, AppStatusColors colors) {
    switch (status) {
      case 'posted':
      case 'succeeded':
      case 'confirmed':
      case 'created':
        return const Color(0xFF059669);
      case 'pending':
      case 'running':
      case 'queued':
        return const Color(0xFFD97706);
      case 'failed':
      case 'rejected':
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFF2563EB);
    }
  }
}
