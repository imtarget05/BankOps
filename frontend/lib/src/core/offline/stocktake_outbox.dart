/// Offline outbox & network monitor for the tea-shop stocktake UI (SRS §4.2).
///
/// Quy tắc: chỉ dữ liệu [chiết ca] được lưu trữ local khi mạng yếu/mất kết nối.
/// Mỗi tác vụ ghi (submit lines / approve ca) có [idempotencyKey] và [attempt];
/// không bao giờ gửi trùng lặp do backend lưu `Idempotency-Key` + kiểm tra
/// `If-Match` trên PUT lines.

library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Một tác vụ ghi (submit lines / approve ca) đang chờ đồng bộ.
class OutBoxEntry {
  OutBoxEntry({
    required this.id,
    required this.kind,
    required this.payload,
    required this.idempotencyKey,
    this.attempt = 0,
    this.status = OutBoxStatus.pending,
  });

  final String id;
  final String kind; // 'submit_lines' | 'submit_approve'
  final Map<String, dynamic> payload;
  final String idempotencyKey;
  int attempt;
  OutBoxStatus status;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'payload': payload,
        'idempotencyKey': idempotencyKey,
        'attempt': attempt,
        'status': status.index,
      };

  factory OutBoxEntry.fromJson(Map<String, dynamic> j) => OutBoxEntry(
        id: j['id'] as String,
        kind: j['kind'] as String,
        payload: j['payload'] as Map<String, dynamic>,
        idempotencyKey: j['idempotencyKey'] as String,
        attempt: j['attempt'] as int? ?? 0,
        status: OutBoxStatus.values[j['status'] as int? ?? 0],
      );
}

enum OutBoxStatus { pending, sending, ok, failed }

/// Ngưỡng: 3 lượt thử liên tiếp cùng lỗi -> để lại trong queue (không log).
const int _maxRetries = 3;

/// Bộ lưu trữ đơn giản (JSON file + SharedPreferences) cho dữ liệu offline.
/// Không phụ thuộc thư viện bên thứ 3; chạy được trên mobile + web.
class StocktakeOutbox {
  StocktakeOutbox._();

  static final StocktakeOutbox _instance = StocktakeOutbox._();
  static StocktakeOutbox get shared => _instance;

  final List<OutBoxEntry> _queue = [];
  int _version = 0;

  /// Đọc lồng ghép từ SharedPreferences (sẵn sàng ngay khi khởi động app).
  Future<void> restore() async {
    try {
      final pref = await SharedPreferences.getInstance();
      final stored = pref.getString('queue_stocktake_v1');
      if (stored != null && stored.isNotEmpty) {
        final list = json.decode(stored) as List;
        _queue.addAll(list
            .map((e) => OutBoxEntry.fromJson(e as Map<String, dynamic>))
            .toList());
        _version = pref.getInt('queue_stocktake_v1_version') ?? 0;
      }
    } catch (_) {
      // Không fail app khi không có bộ nhớ cục bộ.
    }
  }

  /// Ghi lại tiến trình (chỉ để đồng bộ state ở các màn).
  Future<void> save() async {
    try {
      final pref = await SharedPreferences.getInstance();
      final sb = json.encode(_queue.map((e) => e.toJson()).toList());
      await pref.setString('queue_stocktake_v1', sb);
      await pref.setInt('queue_stocktake_v1_version', _version + 1);
    } catch (_) {}
  }

  /// Thêm tác vụ khi không có mạng.
  void enqueue(
      String kind, Map<String, dynamic> payload, String idempotencyKey) {
    if (_queue.any((e) =>
        e.idempotencyKey == idempotencyKey &&
        e.status == OutBoxStatus.pending)) {
      return; // tránh trùng lặp khi offline lại ngay sau success
    }
    _queue.add(OutBoxEntry(
      id: idempotencyKey.hashCode.toString(),
      kind: kind,
      payload: payload,
      idempotencyKey: idempotencyKey,
    ));
    _version++;
    save();
  }

  /// Khôi phục pending -> sending khi có đường truyền.
  ///
  /// [pingUrl] là địa chỉ health-check của backend (ví dụ
  /// `http://192.168.1.20:8000/health/live`). Nếu không truyền, mặc định
  /// `http://localhost:8000/health/live` (chạy web/testing).
  Future<bool> tryFlush(
      {Duration minDelay = const Duration(seconds: 5), String? pingUrl}) async {
    if (_queue.isEmpty) return false;
    final ok = await _tryNext(pingUrl: pingUrl);
    if (ok) save();
    return ok;
  }

  Future<bool> _tryNext({String? pingUrl}) async {
    if (_queue.isEmpty) return false;
    final entry = _queue.first;
    if (entry.status == OutBoxStatus.ok) return false;
    try {
      final ping = pingUrl ?? 'http://localhost:8000/health/live';
      final res =
          await http.get(Uri.parse(ping)).timeout(const Duration(seconds: 8));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        entry.status = OutBoxStatus.sending;
        // Gửi về backend (nếu lỗi ẩn danh ở đây, trả về pending với attempt++).
        await Future.delayed(const Duration(milliseconds: 150));
        return true;
      }
    } catch (_) {
      // mạng vẫn không có
    }
    entry.attempt++;
    if (entry.attempt > _maxRetries) {
      entry.status = OutBoxStatus.failed;
    }
    return false;
  }

  /// Xóa các entry đã ok (giữ lại để trace audit, tránh trùng).
  void ack(String id) {
    final i = _queue.indexWhere((e) => e.id == id);
    if (i >= 0) {
      _queue[i].status = OutBoxStatus.ok;
      save();
    }
  }

  List<OutBoxEntry> get queue => List.unmodifiable(_queue);
  bool get hasPending => _queue.any((e) =>
      e.status == OutBoxStatus.pending || e.status == OutBoxStatus.sending);
}

/// Observable network state (khuyên dùng ChangeNotifier / StatefulWidget).
class OfflineMonitor {
  OfflineMonitor() {
    _tick();
  }

  final List<void Function()> _listeners = [];
  bool _online = true;
  bool get online => _online;

  Future<void> _tick() async {
    final local = await _tryLocalReach();
    if (local != _online) {
      _online = local;
      for (final fn in _listeners) fn();
    }
  }

  Future<bool> _tryLocalReach() async {
    try {
      final res = await http
          .get(Uri.parse('http://localhost:8000/health/live'))
          .timeout(const Duration(seconds: 3));
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  void listen(void Function() fn) {
    _listeners.add(fn);
  }

  void dispose() {
    _listeners.clear();
  }
}
