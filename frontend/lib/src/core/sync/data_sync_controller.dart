import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import '../../data/repositories/bankops_repository.dart';

/// Loại chủ đề đồng bộ dữ liệu giữa các máy khách và máy chủ.
enum SyncTopic {
  inventory,
  stocktake,
  approvals,
  requests,
  cash,
  dashboard,
  all,
}

/// Thông điệp sự kiện đồng bộ đã chuẩn hóa từ SSE hoặc Lifecycle.
class SyncEvent {
  const SyncEvent({
    required this.topic,
    required this.action,
    this.requestId,
    this.kind,
    this.message,
    this.raw,
  });

  final SyncTopic topic;
  final String action;
  final String? requestId;
  final String? kind;
  final String? message;
  final Map<String, dynamic>? raw;

  @override
  String toString() =>
      'SyncEvent(topic: $topic, action: $action, kind: $kind, requestId: $requestId)';
}

/// Controller điều phối đồng bộ thời gian thực cho ứng dụng Quản Lý Kho Trà Sữa.
///
/// Kết hợp 3 cơ chế:
/// 1. Push từ Server-Sent Events (SSE) qua repository.
/// 2. Bắt sự kiện chuyển tab / mở lại app qua [WidgetsBindingObserver] (Lifecycle Resume).
/// 3. Heartbeat Poller (chu kỳ 60s) đóng vai trò dự phòng khi rớt mạng di động.
class DataSyncController extends ChangeNotifier with WidgetsBindingObserver {
  DataSyncController({this.autoPollInterval = const Duration(seconds: 60)}) {
    WidgetsBinding.instance.addObserver(this);
    _startHeartbeat();
  }

  final Duration autoPollInterval;
  StreamSubscription<String>? _sseSubscription;
  Timer? _heartbeatTimer;
  Timer? _debounceTimer;

  bool _isResumed = true;
  int _syncVersion = 0;
  SyncEvent? _lastEvent;

  /// Phiên bản đồng bộ hiện tại. Tăng lên mỗi khi có tín hiệu làm mới dữ liệu.
  int get syncVersion => _syncVersion;

  /// Sự kiện đồng bộ gần nhất.
  SyncEvent? get lastEvent => _lastEvent;

  /// Gắn kết repository để lắng nghe SSE approvalNotifications.
  void bindRepository(BankOpsRepository? repository) {
    _sseSubscription?.cancel();
    if (repository == null) return;

    _sseSubscription = repository.approvalNotifications.listen(
      _handleRawSsePayload,
      onError: (_) {
        // SSE network error: hệ thống sẽ dựa vào heartbeat poller & lifecycle
      },
    );
  }

  void _handleRawSsePayload(String raw) {
    try {
      final decoded = json.decode(raw);
      if (decoded is Map<String, dynamic>) {
        final data = decoded['data'];
        final action = (data is Map ? data['action'] : null)?.toString() ?? 'update';
        final kind = (data is Map ? data['kind'] : null)?.toString() ?? '';
        final reqId = (data is Map ? data['request_id'] : null)?.toString();
        final msg = (data is Map ? data['message'] : null)?.toString();

        SyncTopic topic;
        switch (kind.toLowerCase()) {
          case 'stocktake':
            topic = SyncTopic.stocktake;
            break;
          case 'inventory':
            topic = SyncTopic.inventory;
            break;
          case 'cash':
            topic = SyncTopic.cash;
            break;
          default:
            topic = SyncTopic.approvals;
        }

        final event = SyncEvent(
          topic: topic,
          action: action,
          kind: kind,
          requestId: reqId,
          message: msg,
          raw: decoded,
        );

        notifySyncNeeded(event: event);
        return;
      }
    } catch (_) {
      // Chuỗi không phải JSON (ví dụ test string): phát sự kiện tổng quát
    }

    notifySyncNeeded(
      event: SyncEvent(
        topic: SyncTopic.all,
        action: 'sse_raw',
        message: raw,
      ),
    );
  }

  /// Phát tín hiệu yêu cầu các màn hình đồng bộ lại dữ liệu.
  /// Sử dụng Debounce 1000ms để tránh bão request khi có nhiều event liên tiếp.
  void notifySyncNeeded({SyncEvent? event}) {
    _lastEvent = event;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 1000), () {
      _syncVersion++;
      notifyListeners();
    });
  }

  /// Lắng nghe vòng đời ứng dụng: khi người dùng chuyển về tab này, lập tức nạp lại số liệu.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isResumed = true;
      notifySyncNeeded(
        event: const SyncEvent(
          topic: SyncTopic.all,
          action: 'lifecycle_resumed',
          message: 'Tab kích hoạt lại - đồng bộ số liệu mới nhất',
        ),
      );
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _isResumed = false;
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(autoPollInterval, (_) {
      if (_isResumed) {
        // Chỉ chạy khi app đang foregrounded
        notifySyncNeeded(
          event: const SyncEvent(
            topic: SyncTopic.all,
            action: 'heartbeat_poll',
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sseSubscription?.cancel();
    _heartbeatTimer?.cancel();
    _debounceTimer?.cancel();
    super.dispose();
  }
}

/// InheritedWidget cung cấp [DataSyncController] cho toàn bộ cây widget con.
class SyncScope extends InheritedWidget {
  const SyncScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final DataSyncController controller;

  static DataSyncController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SyncScope>();
    assert(scope != null, 'No SyncScope found in context');
    return scope!.controller;
  }

  static DataSyncController? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SyncScope>()?.controller;
  }

  @override
  bool updateShouldNotify(SyncScope oldWidget) => controller != oldWidget.controller;
}
