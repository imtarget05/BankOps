/// Nút online/offline + banner "Ngoại tuyến - sẽ đồng bộ" (SRS §4.2).
///
/// Hub duy nhất điều khiển trạng thái mạng và danh sách tác vụ đang chờ
/// đồng bộ. Cập nhật từ các màn/tương tác; khi online, các tác vụ trong
/// [StocktakeOutbox] được flush lại kịp thời.
library;

import 'package:flutter/material.dart';
import 'dart:async';

import 'stocktake_outbox.dart';

/// Trạng thái của OfflineHub.
class _OfflineState {
  _OfflineState();

  bool offline = false;
  int pending = 0;
  int failed = 0;
}

/// Hub duy nhất (singleton) điều khiển trạng thái mạng + outbox UI.
class OfflineHub {
  OfflineHub._();

  static final OfflineHub instance = OfflineHub._();

  final List<VoidCallback> _listeners = [];
  final _state = _OfflineState();

  bool get offline => _state.offline;
  int get pending => _state.pending;
  int get failed => _state.failed;
  List<OutBoxEntry> get queue => StocktakeOutbox.shared.queue;
  bool get hasPending => _state.pending > 0 || StocktakeOutbox.shared.hasPending;

  /// Địa chỉ health-check của backend, dùng khi flush outbound (offline). Có thể
  /// cập nhật từ [AppShell] khi biết API_BASE_URL (mặc định localhost:8000).
  String pingUrl = 'http://localhost:8000/health/live';

  void listen(void Function() fn) {
    _listeners.add(fn);
  }

  void _notify() {
    for (final fn in _listeners) {
      fn();
    }
  }

  /// Gọi khi thiết bị mất kết nối (ví dụ HttpClient trả lỗi khi flush).
  void markOffline() {
    if (!_state.offline) {
      _state.offline = true;
      _state.pending = StocktakeOutbox.shared.hasPending ? 1 : 0;
      _notify();
    }
  }

  /// Gọi khi thiết bị quay lại kết nối.
  void markOnline() {
    if (_state.offline) {
      _state.offline = false;
      _state.pending = 0;
      _state.failed = 0;
      _notify();
    }
  }

  /// Tác vụ trong queue thất bại khi flush -> đếm + giữ ở pending.
  void recordFailed() {
    _state.failed++;
    _state.pending = StocktakeOutbox.shared.hasPending ? 1 : 0;
    _notify();
  }

  /// Tạo tác vụ offline mới trong queue (gọi từ repository khi submit bị lỗi mạng).
  void addQueued() {
    _state.pending = StocktakeOutbox.shared.hasPending ? 1 : 0;
    _notify();
  }

  /// Flush toàn bộ queue ngay (dùng khi người dùng bấm "Thử lại").
  Future<void> flushNow({String? pingUrl}) async {
    if (StocktakeOutbox.shared.hasPending) {
      await StocktakeOutbox.shared.tryFlush(pingUrl: pingUrl);
    }
  }
}

/// Banner hiển thị khi mạng yếu/mất kết nối; cung cấp nút "Thử lại".
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, this.pending = 0});

  final int pending;

  @override
  Widget build(BuildContext context) {
    if (pending <= 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = isDark ? const Color(0xFF7C3AED) : const Color(0xFF2563EB);

    return AnimatedOpacity(
      opacity: (pending > 0) ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 250),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_outlined, color: Colors.orangeAccent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Ngoại tuyến - sẽ đồng bộ khi kết nối lại',
                style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13),
              ),
            ),
            if (pending > 0)
              FilledButton.icon(
                onPressed: () => _retry(context, pending),
                icon: const Icon(Icons.refresh, size: 16),
                label: Text('Thử lại ($pending)'),
              )
            else
              const SizedBox(width: 24),
          ],
        ),
      ),
    );
  }

  static void _retry(BuildContext context, int pending) {
    // Khơi động flush từ màn hiện tại (Hub giữ trạng thái).
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đang thử gửi lại $pending ca đồng bộ...')),
        );
    }
  }
}
