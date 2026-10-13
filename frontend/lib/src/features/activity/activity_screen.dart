import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_shell.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/dtos.dart';
import '../../data/repositories/bankops_repository.dart';
import 'activity_center.dart';

/// Màn hoạt động — activity feed với tự làm mới định kỳ (poll 15s).
///
/// Flutter chưa có SSE client nên dùng poll nền + chỉ báo LIVE.
/// Không flash loading khi refresh nền: giữ dữ liệu cũ tới khi có mới.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  static const _pollInterval = Duration(seconds: 15);

  BankOpsRepository? _repo;
  Timer? _timer;
  List<ActivityEvent>? _events;
  Object? _error;
  bool _loading = false;
  DateTime? _lastUpdated;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repo == null) {
      _repo = RepositoryScope.of(context);
      _load();
      _timer ??= Timer.periodic(
        _pollInterval,
        (_) => _load(silent: true),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final repo = _repo;
    if (repo == null) return;
    if (!silent) setState(() => _loading = true);
    try {
      final events = await repo.getActivity();
      if (!mounted) return;
      setState(() {
        _events = events;
        _error = null;
        _loading = false;
        _lastUpdated = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LiveBar(
          lastUpdated: _lastUpdated,
          loading: _loading,
          onRefresh: () => _load(),
        ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    final events = _events;
    if (_loading && events == null) {
      return const Center(child: LoadingView());
    }
    if (_error != null && events == null) {
      return Center(
        child: ErrorView(
          message: '$_error',
          onRetry: () => _load(),
        ),
      );
    }
    return ActivityCenter(
      events: events ?? const [],
      onRefresh: () => _load(),
    );
  }
}

/// Thanh trạng thái realtime: chấm LIVE + thời gian cập nhật + làm mới tay.
class _LiveBar extends StatelessWidget {
  const _LiveBar({
    required this.lastUpdated,
    required this.loading,
    required this.onRefresh,
  });

  final DateTime? lastUpdated;
  final bool loading;
  final VoidCallback onRefresh;

  static String _clock(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('activity-live-bar'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant.withAlpha(128)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF10B981),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              lastUpdated == null
                  ? 'Đang kết nối dòng hoạt động…'
                  : 'Trực tiếp · tự làm mới 15s · cập nhật ${_clock(lastUpdated!)}',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (loading)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            IconButton(
              key: const Key('activity-refresh-btn'),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              tooltip: 'Làm mới ngay',
              onPressed: onRefresh,
            ),
        ],
      ),
    );
  }
}
