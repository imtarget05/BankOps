import 'package:flutter/material.dart';

import '../../core/widgets/state_views.dart';
import '../../data/models/dtos.dart';
import '../../data/repositories/bankops_repository.dart';

/// Timeline audit của một phiếu: lọc `getActivity()` theo `subjectId`,
/// sắp xếp theo `occurredAt`, vẽ mốc dot + đường nối (không thêm dep).
///
/// Nhận `repo` trực tiếp để test được độc lập, không cần AppShell.
class RequestTimeline extends StatefulWidget {
  const RequestTimeline({
    super.key,
    required this.requestId,
    required this.repo,
    this.scrollController,
  });

  final String requestId;
  final BankOpsRepository repo;
  final ScrollController? scrollController;

  @override
  State<RequestTimeline> createState() => _RequestTimelineState();
}

class _RequestTimelineState extends State<RequestTimeline> {
  Future<List<ActivityEvent>>? _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repo.getActivity();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('request-timeline-${widget.requestId}'),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Lịch sử phiếu ${widget.requestId}',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: FutureBuilder<List<ActivityEvent>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: LoadingView(itemCount: 2));
                }
                if (snapshot.hasError) {
                  return ErrorView(
                    message: '${snapshot.error}',
                    onRetry: () => setState(
                      () => _future = widget.repo.getActivity(),
                    ),
                  );
                }
                final events = snapshot.data!
                    .where((e) => e.subjectId == widget.requestId)
                    .toList()
                  ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
                if (events.isEmpty) {
                  return const EmptyView(
                    title: 'Chưa có lịch sử cho phiếu này',
                    subtitle:
                        'Các mốc tạo, gửi duyệt và duyệt sẽ hiện ở đây theo thời gian.',
                    icon: Icons.history_outlined,
                  );
                }
                return ListView.builder(
                  controller: widget.scrollController,
                  shrinkWrap: true,
                  itemCount: events.length,
                  itemBuilder: (context, i) =>
                      _TimelineRow(event: events[i], last: i == events.length - 1),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.event, required this.last});

  final ActivityEvent event;
  final bool last;

  static const _labels = {
    'stock_request_created': 'Tạo phiếu kho',
    'cash_request_created': 'Tạo phiếu quỹ',
    'stock_request_pending': 'Gửi duyệt phiếu kho',
    'cash_request_pending': 'Gửi duyệt phiếu quỹ',
    'stock_request_posted': 'Đã duyệt & ghi sổ (kho)',
    'cash_request_posted': 'Đã duyệt & ghi sổ (quỹ)',
    'stock_request_rejected': 'Bị từ chối (kho)',
    'cash_request_rejected': 'Bị từ chối (quỹ)',
  };

  static String _clock(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.day)}/${two(t.month)}/${t.year} ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = event.status == 'posted' || event.status == 'created';
    final color = event.status.contains('reject')
        ? const Color(0xFFB42318)
        : (done ? const Color(0xFF059669) : const Color(0xFFD97706));
    return Container(
      key: Key('timeline-event-${event.id}'),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.surface, width: 2),
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(width: 2, color: scheme.outlineVariant),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: last ? 0 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _labels[event.messageKey] ?? event.messageKey,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_clock(event.occurredAt)} · ${event.status}',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
