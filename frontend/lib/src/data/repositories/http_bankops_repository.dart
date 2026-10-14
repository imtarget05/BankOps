import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../features/auth/auth_service.dart';
import '../models/dtos.dart';
import 'bankops_repository.dart';

/// Repository HTTP thật, gọi backend FastAPI theo docs/06-api.md.
///
/// - `baseUrl` lấy từ `--dart-define=API_BASE_URL=...`, mặc định
///   `http://localhost:8000/api/v1` (chuẩn hoá qua [AuthService.normalizeApiBaseUrl]).
/// - Token Bearer lấy qua [tokenProvider] (do UI/AuthService cấp).
/// - Lỗi backend dạng envelope `{error:{code,message,request_id}}` được
///   chuyển thành [ApiException] giữ nguyên `requestId`.
class HttpBankOpsRepository implements BankOpsRepository {
  HttpBankOpsRepository({
    String? baseUrl,
    http.Client? client,
    Future<String?> Function()? tokenProvider,
  })  : _baseUrl = AuthService.normalizeApiBaseUrl(
          baseUrl ?? AuthService.defaultBaseUrl,
        ),
        _client = client ?? http.Client(),
        _tokenProvider = tokenProvider {
    _approvalStreamCtrl = StreamController<String>.broadcast(
      onListen: _startSse,
      onCancel: _stopSse,
    );
  }

  final String _baseUrl;
  final http.Client _client;
  final Future<String?> Function()? _tokenProvider;
  late final StreamController<String> _approvalStreamCtrl;
  bool _sseActive = false;
  bool _disposed = false;

  void _startSse() {
    if (_sseActive || _disposed) return;
    _sseActive = true;
    _runSseLoop();
  }

  void _stopSse() {
    _sseActive = false;
  }

  Future<void> _runSseLoop() async {
    while (_sseActive && !_disposed) {
      try {
        final token = await _tokenProvider?.call();
        if (token == null || token.isEmpty) {
          await Future.delayed(const Duration(seconds: 1));
          continue;
        }

        final uri = _uri('/approvals/stream', {'token': token});
        final request = http.Request('GET', uri);
        request.headers['Accept'] = 'text/event-stream';
        request.headers['Cache-Control'] = 'no-cache';

        final streamedResponse = await _client.send(request);
        if (streamedResponse.statusCode == 200) {
          await for (final line in streamedResponse.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
            if (!_sseActive || _disposed) break;
            if (line.startsWith('data: ')) {
              final payload = line.substring(6).trim();
              if (payload.isNotEmpty && !_approvalStreamCtrl.isClosed) {
                _approvalStreamCtrl.add(payload);
              }
            }
          }
        }
      } catch (_) {
        // SSE network disconnect or error: wait before retry
      }
      if (!_sseActive || _disposed) break;
      await Future.delayed(const Duration(seconds: 3));
    }
  }

  String get baseUrl => _baseUrl;
  Future<String?> get accessToken => _tokenProvider?.call() ?? Future.value(null);

  @override
  void dispose() {
    _disposed = true;
    _sseActive = false;
    _approvalStreamCtrl.close();
    _client.close();
  }

  @override
  Stream<String> get approvalNotifications => _approvalStreamCtrl.stream;


  Uri _uri(String path, [Map<String, String>? query]) => Uri.parse('$_baseUrl$path')
      .replace(queryParameters: query == null || query.isEmpty ? null : query);

  Future<Map<String, String>> _headers() async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final token = await _tokenProvider?.call();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Never _throwEnvelope(http.Response resp) {
    String code = 'HTTP_${resp.statusCode}';
    String message = 'Máy chủ trả lỗi ${resp.statusCode}.';
    String? requestId = resp.headers['x-request-id'];
    try {
      final decoded = json.decode(resp.body);
      if (decoded is Map) {
        final err = decoded['error'];
        if (err is Map) {
          if (err['code'] is String) code = err['code'] as String;
          if (err['message'] is String) message = err['message'] as String;
          if (err['request_id'] is String) {
            requestId = err['request_id'] as String;
          }
        } else if (decoded['detail'] is String) {
          message = decoded['detail'] as String;
        }
      }
    } catch (_) {}
    throw ApiException(code, message, requestId: requestId);
  }

  Future<dynamic> _get(String path, [Map<String, String>? query]) async {
    final resp =
        await _client.get(_uri(path, query), headers: await _headers());
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      _throwEnvelope(resp);
    }
    return json.decode(resp.body);
  }

  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> body,
      {Map<String, String>? extraHeaders}) async {
    final headers = await _headers();
    if (extraHeaders != null) headers.addAll(extraHeaders);
    final resp =
        await _client.post(_uri(path), headers: headers, body: json.encode(body));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      _throwEnvelope(resp);
    }
    final decoded = json.decode(resp.body);
    if (decoded is Map<String, dynamic>) return decoded;
    return {'data': decoded};
  }

  Future<Map<String, dynamic>> _put(
      String path, Map<String, dynamic> body,
      {Map<String, String>? extraHeaders}) async {
    final headers = await _headers();
    if (extraHeaders != null) headers.addAll(extraHeaders);
    final resp =
        await _client.put(_uri(path), headers: headers, body: json.encode(body));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      _throwEnvelope(resp);
    }
    final decoded = json.decode(resp.body);
    if (decoded is Map<String, dynamic>) return decoded;
    return {'data': decoded};
  }

  Future<dynamic> _delete(String path) async {
    final resp =
        await _client.delete(_uri(path), headers: await _headers());
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      _throwEnvelope(resp);
    }
    return json.decode(resp.body);
  }

  static List _asList(dynamic body, String key) {
    if (body is Map && body[key] is List) return body[key] as List;
    if (body is List) return body;
    return const [];
  }

  static String _str(Map m, String key, [String fallback = '']) {
    final v = m[key];
    if (v == null) return fallback;
    return v.toString();
  }

  static DateTime _date(Map m, String key) {
    final v = m[key];
    if (v is String) return DateTime.tryParse(v) ?? DateTime.now().toUtc();
    return DateTime.now().toUtc();
  }

  static RequestStatus _status(String raw) {
    if (raw == 'submitted') return RequestStatus.pending;
    for (final s in RequestStatus.values) {
      if (s.name == raw) return s;
    }
    return RequestStatus.draft;
  }

  /// Server kho dùng 'issue' cho xuất kho; quỹ dùng 'payment'.
  static RequestKind _kind(String raw) {
    if (raw == 'issue') return RequestKind.payment;
    for (final k in RequestKind.values) {
      if (k.name == raw) return k;
    }
    return RequestKind.receipt;
  }

  static String _serverStockKind(RequestKind kind) {
    if (kind == RequestKind.payment) return 'issue';
    return kind.name;
  }

  static AssetStatus _assetStatus(String raw) {
    for (final s in AssetStatus.values) {
      if (s.name == raw) return s;
    }
    return AssetStatus.available;
  }

  // ---- auth/users ----

  @override
  Future<List<AppUser>> loadUsers() async {
    try {
      final me = await _get('/me');
      if (me is Map) {
        return [
          AppUser(
            id: _str(me, 'id'),
            username: _str(me, 'username'),
            displayName: _str(me, 'display_name', _str(me, 'username')),
            email: me['email']?.toString(),
            phoneNumber: me['phone_number']?.toString(),
            branch: me['branch']?.toString(),
            roles: (me['roles'] is List ? me['roles'] as List : const [])
                .map((r) => r.toString())
                .toList(),
          ),
        ];
      }
    } catch (_) {}
    return const [
      AppUser(
        id: 'u_maker',
        username: 'demo_maker',
        displayName: 'Nguyễn Văn A (Tạo phiếu)',
        roles: ['maker', 'inventory_custodian', 'cash_simulated_custodian'],
      ),
      AppUser(
        id: 'u_checker',
        username: 'demo_checker',
        displayName: 'Trần Thị B (Duyệt phiếu)',
        roles: ['checker', 'inventory_custodian', 'cash_simulated_custodian'],
      ),
      AppUser(
        id: 'u_auditor',
        username: 'demo_auditor',
        displayName: 'Lê Văn C (Kiểm toán)',
        roles: ['auditor'],
      ),
    ];
  }

  @override
  Future<AppUser> login(String username) async {
    final data = await _post('/auth/login', {
      'username': username,
      'password': 'DemoPass123!',
    });
    final u = (data['user'] is Map) ? data['user'] as Map : data;
    return AppUser(
      id: _str(u, 'id'),
      username: _str(u, 'username', username),
      displayName: _str(u, 'display_name', username),
      email: u['email']?.toString(),
      phoneNumber: u['phone_number']?.toString(),
      branch: u['branch']?.toString(),
      roles: (u['roles'] is List ? u['roles'] as List : const [])
          .map((r) => r.toString())
          .toList(),
    );
  }

  @override
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await _post('/auth/change-password', {
      'old_password': oldPassword,
      'new_password': newPassword,
    });
  }

  @override
  Future<void> changePin({
    required String currentPassword,
    required String newPin,
  }) async {
    await _post('/auth/change-pin', {
      'current_password': currentPassword,
      'new_pin': newPin,
    });
  }

  @override
  Future<PasswordResetResult> requestPasswordReset(String username) async {
    final res = await _post('/auth/forgot-password', {
      'username': username.trim(),
    });
    return PasswordResetResult(
      username: _str(res, 'username', username.trim()),
      message: _str(res, 'message', 'Đã tạo mã xác thực OTP.'),
      otpDemo: res['otp_demo']?.toString(),
      expiresInSeconds: (res['expires_in_seconds'] is int)
          ? res['expires_in_seconds'] as int
          : 900,
    );
  }

  @override
  Future<void> resetPassword({
    required String username,
    required String otp,
    required String newPassword,
  }) async {
    await _post('/auth/reset-password', {
      'username': username.trim(),
      'otp': otp.trim(),
      'new_password': newPassword,
    });
  }

  @override
  Future<AppUser> updateProfile({
    required String displayName,
    String? email,
    String? phoneNumber,
    String? branch,
  }) async {
    final res = await _put('/auth/me', {
      'display_name': displayName.trim(),
      if (email != null) 'email': email.trim(),
      if (phoneNumber != null) 'phone_number': phoneNumber.trim(),
      if (branch != null) 'branch': branch.trim(),
    });
    final u = (res['user'] is Map) ? res['user'] as Map : res;
    return AppUser(
      id: _str(u, 'id'),
      username: _str(u, 'username'),
      displayName: _str(u, 'display_name', displayName.trim()),
      email: u['email']?.toString(),
      phoneNumber: u['phone_number']?.toString(),
      branch: u['branch']?.toString(),
      roles: (u['roles'] is List ? u['roles'] as List : const [])
          .map((r) => r.toString())
          .toList(),
    );
  }

  // ---- inventory ----

  @override
  Future<List<InventoryLocation>> getLocations() async {
    final body = await _get('/inventory/locations');
    return _asList(body, 'locations')
        .whereType<Map>()
        .map((m) => InventoryLocation(
              id: _str(m, 'id'),
              code: _str(m, 'code'),
              name: _str(m, 'name'),
            ))
        .toList();
  }

  @override
  Future<List<InventoryItem>> getItems() async {
    final body = await _get('/inventory/items');
    return _asList(body, 'items')
        .whereType<Map>()
        .map((m) => InventoryItem(
              id: _str(m, 'id'),
              sku: _str(m, 'sku'),
              name: _str(m, 'name'),
              unit: _str(m, 'unit'),
              trackedSerial: m['tracked_serial'] == true,
            ))
        .toList();
  }

  @override
  Future<InventoryItem> createItem({
    required String sku,
    required String name,
    required String unit,
    bool trackedSerial = false,
  }) async {
    final body = await _post('/inventory/items', {
      'sku': sku,
      'name': name,
      'unit': unit,
      'tracked_serial': trackedSerial,
    });
    return InventoryItem(
      id: _str(body, 'id'),
      sku: _str(body, 'sku', sku),
      name: _str(body, 'name', name),
      unit: _str(body, 'unit', unit),
      trackedSerial: body['tracked_serial'] == true,
    );
  }

  @override
  Future<InventoryItem> updateItem({
    required String id,
    String? name,
    String? unit,
    bool? trackedSerial,
  }) async {
    final body = await _put('/inventory/items/$id', {
      if (name != null) 'name': name,
      if (unit != null) 'unit': unit,
      if (trackedSerial != null) 'tracked_serial': trackedSerial,
    });
    return InventoryItem(
      id: _str(body, 'id', id),
      sku: _str(body, 'sku'),
      name: _str(body, 'name'),
      unit: _str(body, 'unit'),
      trackedSerial: body['tracked_serial'] == true,
    );
  }

  @override
  Future<void> deleteItem(String id) async {
    await _delete('/inventory/items/$id');
  }

  @override
  Future<InventoryLocation> createLocation({
    required String code,
    required String name,
  }) async {
    final body = await _post('/inventory/locations', {
      'code': code,
      'name': name,
    });
    return InventoryLocation(
      id: _str(body, 'id'),
      code: _str(body, 'code', code),
      name: _str(body, 'name', name),
    );
  }

  @override
  Future<InventoryLocation> updateLocation({
    required String id,
    String? name,
  }) async {
    final body = await _put('/inventory/locations/$id', {
      if (name != null) 'name': name,
    });
    return InventoryLocation(
      id: _str(body, 'id', id),
      code: _str(body, 'code'),
      name: _str(body, 'name'),
    );
  }

  @override
  Future<void> deleteLocation(String id) async {
    await _delete('/inventory/locations/$id');
  }

  @override
  Future<List<StockBalance>> getBalances({String? locationId}) async {
    final body = await _get('/inventory/balances',
        {if (locationId != null) 'location_id': locationId});
    return _asList(body, 'balances')
        .whereType<Map>()
        .map((m) => StockBalance(
              locationId: _str(m, 'location_id'),
              itemId: _str(m, 'item_id'),
              quantity: _str(m, 'quantity', '0'),
            ))
        .toList();
  }

  @override
  Future<List<AssetRecord>> getAssets({String? locationId}) async {
    final body = await _get('/inventory/assets');
    final all = _asList(body, 'assets').whereType<Map>().map((m) => AssetRecord(
          serial: _str(m, 'serial'),
          itemId: _str(m, 'item_id'),
          locationId: _str(m, 'location_id'),
          status: _assetStatus(_str(m, 'status')),
        ));
    if (locationId == null) return all.toList();
    return all.where((a) => a.locationId == locationId).toList();
  }

  @override
  Future<List<StockMovement>> getMovements({String? itemId}) async {
    final body = await _get('/inventory/movements');
    final all = _asList(body, 'movements')
        .whereType<Map>()
        .map((m) => StockMovement(
              id: _str(m, 'id'),
              itemId: _str(m, 'item_id'),
              locationId: _str(m, 'location_id'),
              quantity: _str(m, 'quantity_signed', '0'),
              kind: _str(m, 'kind', 'receipt'),
              createdAt: _date(m, 'created_at'),
            ));
    if (itemId == null) return all.toList();
    return all.where((x) => x.itemId == itemId).toList();
  }

  @override
  Future<List<StockRequest>> getStockRequests() async {
    final body = await _get('/inventory/requests');
    return _asList(body, 'requests')
        .whereType<Map>()
        .map(_parseStockRequest)
        .toList();
  }

  @override
  Future<StockRequest> createStockRequest({
    required RequestKind kind,
    String? sourceLocationId,
    String? destLocationId,
    required List<StockRequestLine> lines,
    String? reason,
  }) async {
    final serverKind = _serverStockKind(kind);
    final payload = <String, dynamic>{
      'kind': serverKind,
      'reason': reason ?? '',
      'lines': [
        for (final line in lines)
          {
            'item_id': line.itemId,
            'quantity': line.quantity,
            'serials': const <String>[],
          }
      ],
    };
    if (serverKind == 'receipt') {
      payload['dest_id'] = destLocationId ?? sourceLocationId;
    } else if (serverKind == 'issue') {
      payload['source_id'] = sourceLocationId ?? destLocationId;
    } else if (serverKind == 'transfer') {
      payload['source_id'] = sourceLocationId;
      payload['dest_id'] = destLocationId ?? sourceLocationId;
    } else {
      payload['source_id'] = sourceLocationId;
      payload['dest_id'] = destLocationId ?? sourceLocationId;
    }
    final res = await _post(
      '/inventory/requests',
      payload,
      extraHeaders: {'Idempotency-Key': _idemKey()},
    );
    return _parseStockRequest(res);
  }

  @override
  Future<void> deleteStockRequest(String id) async {
    await _delete('/inventory/requests/$id');
  }

  StockRequest _parseStockRequest(Map m) {
    final lines = (m['lines'] is List ? m['lines'] as List : const [])
        .whereType<Map>()
        .map((l) => StockRequestLine(
              itemId: _str(l, 'item_id'),
              quantity: _str(l, 'quantity', '0'),
            ))
        .toList();
    final maker = _str(m, 'maker_id');
    final sourceId = m['source_id']?.toString();
    final destId = m['dest_id']?.toString();
    return StockRequest(
      id: _str(m, 'id'),
      kind: _kind(_str(m, 'kind')),
      status: _status(_str(m, 'status', 'draft')),
      version: (m['version'] is int)
          ? m['version'] as int
          : int.tryParse(_str(m, 'version', '1')) ?? 1,
      createdBy: maker,
      createdByName: _str(m, 'maker_name', maker),
      locationId: sourceId ?? destId ?? '',
      items: lines,
      reason: _str(m, 'reason'),
      createdAt: _date(m, 'created_at'),
      approvedBy: m['approved_by']?.toString(),
      approvedByName: m['approved_by_name']?.toString(),
      rejectReason: m['reject_reason']?.toString(),
      destinationLocationId: destId,
    );
  }

  @override
  Future<StockRequest> submitStockRequest(String id) async {
    final res = _parseStockRequest(await _post(
      '/inventory/requests/$id/submit',
      {},
      extraHeaders: {'Idempotency-Key': _idemKey()},
    ));
    _approvalStreamCtrl.add('new_request:$id:kho');
    return res;
  }

  @override
  Future<StockRequest> approveStockRequest(String id, {String? supervisorPin}) async {
    final res = _parseStockRequest(await _post(
      '/inventory/requests/$id/approve',
      {if (supervisorPin != null) 'supervisor_pin': supervisorPin},
      extraHeaders: {'Idempotency-Key': _idemKey()},
    ));
    _approvalStreamCtrl.add('processed:$id');
    return res;
  }

  @override
  Future<StockRequest> rejectStockRequest(String id, String reason) async {
    final res = _parseStockRequest(await _post(
      '/inventory/requests/$id/reject',
      {'reason': reason},
      extraHeaders: {'Idempotency-Key': _idemKey()},
    ));
    _approvalStreamCtrl.add('processed:$id');
    return res;
  }

  // ---- cash-sim ----

  @override
  Future<List<Cashbox>> getCashboxes() async {
    final body = await _get('/cash-sim/boxes');
    return _asList(body, 'boxes')
        .whereType<Map>()
        .map((m) => Cashbox(
              id: _str(m, 'id'),
              code: _str(m, 'code'),
              name: _str(m, 'name'),
              openingBalance: _str(m, 'opening_balance', '0'),
            ))
        .toList();
  }

  @override
  Future<Cashbox> createCashbox({
    required String code,
    required String name,
    String currency = 'VND',
    String openingBalance = '0.00',
  }) async {
    final body = await _post('/cash-sim/boxes', {
      'code': code,
      'name': name,
      'currency': currency,
      'opening_balance': openingBalance,
    });
    return Cashbox(
      id: _str(body, 'id'),
      code: _str(body, 'code', code),
      name: _str(body, 'name', name),
      openingBalance: _str(body, 'opening_balance', openingBalance),
    );
  }

  @override
  Future<Cashbox> updateCashbox({
    required String id,
    String? name,
  }) async {
    final body = await _put('/cash-sim/boxes/$id', {
      if (name != null) 'name': name,
    });
    return Cashbox(
      id: _str(body, 'id', id),
      code: _str(body, 'code'),
      name: _str(body, 'name'),
      openingBalance: _str(body, 'opening_balance', '0'),
    );
  }

  @override
  Future<void> deleteCashbox(String id) async {
    await _delete('/cash-sim/boxes/$id');
  }

  @override
  Future<List<CashBalance>> getCashBalances() async {
    final body = await _get('/cash-sim/balances');
    return _asList(body, 'balances')
        .whereType<Map>()
        .map((m) => CashBalance(
              cashboxId: _str(m, 'cashbox_id'),
              amount: _str(m, 'amount', '0'),
              currency: _str(m, 'currency', 'VND'),
            ))
        .toList();
  }

  @override
  Future<List<JournalEntry>> getJournals() async {
    final body = await _get('/cash-sim/journals');
    return _asList(body, 'journals')
        .whereType<Map>()
        .map((m) => JournalEntry(
              id: _str(m, 'id'),
              cashboxId: _str(m, 'cashbox_id'),
              kind: _str(m, 'kind', 'receipt'),
              amount: _str(m, 'amount', '0'),
              currency: _str(m, 'currency', 'VND'),
              reason: _str(m, 'reason', _str(m, 'correlation_id')),
              createdAt: _date(m, 'posted_at'),
            ))
        .toList();
  }

  CashRequest _parseCashRequest(Map m) {
    final maker = _str(m, 'maker_id');
    return CashRequest(
      id: _str(m, 'id'),
      kind: _kind(_str(m, 'kind')),
      status: _status(_str(m, 'status', 'draft')),
      version: (m['version'] is int)
          ? m['version'] as int
          : int.tryParse(_str(m, 'version', '1')) ?? 1,
      createdBy: maker,
      createdByName: _str(m, 'maker_name', maker),
      cashboxId: _str(m, 'cashbox_id'),
      amount: _str(m, 'amount', '0'),
      currency: _str(m, 'currency', 'VND'),
      reason: _str(m, 'reason'),
      createdAt: _date(m, 'created_at'),
      approvedBy: m['approved_by']?.toString(),
      approvedByName: m['approved_by_name']?.toString(),
      rejectReason: m['reject_reason']?.toString(),
    );
  }

  @override
  Future<List<CashRequest>> getCashRequests() async {
    final body = await _get('/cash-sim/requests');
    return _asList(body, 'requests')
        .whereType<Map>()
        .map(_parseCashRequest)
        .toList();
  }

  @override
  Future<CashRequest> createCashRequest({
    required String cashboxId,
    required RequestKind kind,
    required String amount,
    String? reason,
  }) async {
    final res = await _post(
      '/cash-sim/requests',
      {
        'kind': kind == RequestKind.payment ? 'payment' : 'receipt',
        'cashbox_id': cashboxId,
        'amount': amount,
        'currency': 'VND',
        'reason': reason ?? '',
      },
      extraHeaders: {'Idempotency-Key': _idemKey()},
    );
    return _parseCashRequest(res);
  }

  @override
  Future<void> deleteCashRequest(String id) async =>
      _delete('/cash-sim/requests/$id');

  @override
  Future<CashRequest> submitCashRequest(String id) async {
    final res = _parseCashRequest(await _post(
      '/cash-sim/requests/$id/submit',
      {},
      extraHeaders: {'Idempotency-Key': _idemKey()},
    ));
    _approvalStreamCtrl.add('new_request:$id:quỹ');
    return res;
  }

  @override
  Future<CashRequest> approveCashRequest(String id, {String? supervisorPin}) async {
    final res = _parseCashRequest(await _post(
      '/cash-sim/requests/$id/approve',
      {if (supervisorPin != null) 'supervisor_pin': supervisorPin},
      extraHeaders: {'Idempotency-Key': _idemKey()},
    ));
    _approvalStreamCtrl.add('processed:$id');
    return res;
  }

  @override
  Future<CashRequest> rejectCashRequest(String id, String reason) async {
    final res = _parseCashRequest(await _post(
      '/cash-sim/requests/$id/reject',
      {'reason': reason},
      extraHeaders: {'Idempotency-Key': _idemKey()},
    ));
    _approvalStreamCtrl.add('processed:$id');
    return res;
  }

  // ---- approvals ----

  @override
  Future<List<ApprovalItem>> getApprovalInbox() async {
    final body = await _get('/approvals/inbox');
    return _asList(body, 'approvals').whereType<Map>().map((m) {
      final id = _str(m, 'id');
      return ApprovalItem(
        id: id,
        kind: _str(m, 'kind'),
        maker: _str(m, 'maker'),
        impact: _str(m, 'impact', _str(m, 'status')),
        detail: _str(m, 'detail', id),
        approvalDetail: m['approval_detail'] is Map
            ? Map<String, dynamic>.from(m['approval_detail'] as Map)
            : (m['approval_detail'] is String
                ? _decodeMap(m['approval_detail'] as String)
                : null),
      );
    }).toList();
  }

  Map<String, dynamic>? _decodeMap(String source) {
    try {
      final decoded = json.decode(source);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } on FormatException {
      return null;
    }
  }

  String _assessmentAmount(ApprovalItem item) {
    final structuredQuantity = item.approvalDetail?['total_quantity'];
    if (structuredQuantity != null) return structuredQuantity.toString();
    final raw = item.impact;
    final decimalMatch = RegExp(r'-?[\d,.]+').firstMatch(raw);
    if (decimalMatch == null) return raw;
    var amount = decimalMatch.group(0)!;
    if (amount.contains('.') && amount.contains(',')) {
      amount = amount.replaceAll(',', '');
    } else if (amount.contains(',')) {
      amount = amount.replaceAll(',', '.');
    }
    return amount;
  }

  @override
  Future<AiRiskAssessment> assessApprovalItem(ApprovalItem item) async {
    try {
      final structuredKind = item.approvalDetail?['kind']?.toString();
      final res = await _post('/ai/assess-request', {
        'request_id': item.id,
        'kind': structuredKind ?? item.kind,
        'amount_or_qty': _assessmentAmount(item),
        'maker': item.maker,
        'reason': item.detail,
      });
      return AiRiskAssessment.fromJson(res);
    } catch (_) {
      final isCash = item.kind.toLowerCase() == 'cash' ||
          item.kind.toLowerCase().contains('quỹ');
      var rawImpact = item.impact;
      final decimalMatch = RegExp(r'[\.,]\d{1,2}(?:\s|[a-zA-Z]|$)').firstMatch(rawImpact);
      if (decimalMatch != null) rawImpact = rawImpact.substring(0, decimalMatch.start);
      final digits = rawImpact.replaceAll(RegExp(r'[^\d]'), '');
      final val = int.tryParse(digits) ?? 0;
      final isHigh = (isCash && val >= 500000000) || (!isCash && val >= 50);
      return AiRiskAssessment(
        requestId: item.id,
        riskLevel: isHigh ? 'high' : 'low',
        riskScore: isHigh ? 88 : 20,
        summary: 'Thẩm định ngoại tuyến cho phiếu ${item.id}',
        flaggedRules: isHigh ? ['Giao dịch vượt hạn mức kiểm soát kép (≥ 500 triệu VND)'] : [],
        recommendations: ['Kiểm tra đối chiếu chứng từ gốc và nhập PIN KSV'],
        auditStamp: 'offline-audit-stamp-${item.id}',
        assessmentSource: 'offline_fallback',
      );
    }
  }

  // ---- health (public, không cần auth) ----

  @override
  Future<HealthStatus> getHealth() async {
    final sw = Stopwatch()..start();
    try {
      final resp = await _client
          .get(
            _uri('/health/live'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));
      sw.stop();
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return HealthStatus(
          alive: false,
          version: '?',
          latencyMs: sw.elapsedMilliseconds,
          error: 'HTTP ${resp.statusCode}',
        );
      }
      final decoded = json.decode(resp.body);
      final version = decoded is Map
          ? (decoded['version']?.toString() ?? '?')
          : '?';
      return HealthStatus(
        alive: true,
        version: version,
        latencyMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      sw.stop();
      return HealthStatus(
        alive: false,
        version: '?',
        latencyMs: sw.elapsedMilliseconds,
        error: '$e',
      );
    }
  }

  // ---- activity ----

  @override
  Future<List<ActivityEvent>> getActivity({String? cursor}) async {
    final body = await _get(
        '/activity/', {if (cursor != null) 'cursor': cursor});
    return _asList(body, 'events')
        .whereType<Map>()
        .map((m) => ActivityEvent(
              id: _str(m, 'id'),
              occurredAt: _date(m, 'occurred_at'),
              subjectId: _str(m, 'subject_id'),
              status: _str(m, 'status'),
              messageKey: _str(m, 'message_key', _str(m, 'status')),
              processed: m['processed'] is int ? m['processed'] as int : null,
              total: m['total'] is int ? m['total'] as int : null,
            ))
        .toList();
  }

  // ---- integrations / reconciliations / reports ----

  String _idemKey() =>
      'idem-${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';

  StagingPreview _parseStagingPreview(Map<String, dynamic> body) {
    final rows = _asList(body, 'rows').whereType<Map>().map((r) {
      final rawData = r['data'] is Map
          ? (r['data'] as Map).map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{};
      final rawErrors = (r['errors'] is List ? r['errors'] as List : const [])
          .map((e) => e.toString())
          .toList();
      return StagingRow(
        rowIndex: r['row_index'] is int ? r['row_index'] as int : 0,
        sourceRowKey: _str(r, 'source_row_key'),
        data: rawData,
        valid: r['valid'] == true,
        errors: rawErrors,
      );
    }).toList();
    return StagingPreview(
      runId: _str(body, 'run_id'),
      validCount: body['valid_count'] is int ? body['valid_count'] as int : 0,
      invalidCount:
          body['invalid_count'] is int ? body['invalid_count'] as int : 0,
      deduplicated: body['deduplicated'] == true,
      mappingVersion:
          body['mapping_version'] is int ? body['mapping_version'] as int : 1,
      rows: rows,
    );
  }

    @override
  Future<List<IntegrationConnection>> getConnections() async {
    final body = await _get('/integrations/connections');
    return _asList(body, 'connections')
        .whereType<Map>()
        .map((m) => IntegrationConnection(
              id: _str(m, 'id'),
              name: _str(m, 'name'),
              endpoint: _str(m, 'type'),
              status: _str(m, 'status', 'connected'),
              lastTestedAt: _date(m, 'last_tested_at'),
              lastError: _str(m, 'last_error', ''),
            ))
        .toList();
  }

  @override
  Future<IntegrationConnection> createConnection({
    required String name,
    required String type,
    String? endpoint,
    Map<String, dynamic>? config,
  }) async {
    final body = await _post(
      '/integrations/connections',
      {
        'name': name,
        'type': type,
        'status': 'connected',
        'config': config ?? (endpoint != null ? {'endpoint': endpoint} : {}),
      },
      extraHeaders: {'Idempotency-Key': _idemKey()},
    );
    return IntegrationConnection(
      id: _str(body, 'id'),
      name: _str(body, 'name'),
      endpoint: _str(body, 'type'),
      status: _str(body, 'status', 'connected'),
      lastTestedAt: _date(body, 'last_tested_at'),
      lastError: _str(body, 'last_error', ''),
    );
  }

  @override
  Future<IntegrationConnection> updateConnection({
    required String id,
    String? name,
    String? endpoint,
    String? status,
  }) async {
    final payload = <String, dynamic>{};
    if (name != null) payload['name'] = name;
    if (status != null) payload['status'] = status;
    if (endpoint != null) payload['config'] = {'endpoint': endpoint};
    final body = await _put('/integrations/connections/$id', payload);
    return IntegrationConnection(
      id: _str(body, 'id'),
      name: _str(body, 'name'),
      endpoint: _str(body, 'type'),
      status: _str(body, 'status', 'connected'),
      lastTestedAt: _date(body, 'last_tested_at'),
      lastError: _str(body, 'last_error', ''),
    );
  }

  @override
  Future<void> deleteConnection(String id) async =>
      _delete('/integrations/connections/$id');

  @override
  Future<Map<String, dynamic>> testConnection(String id) async {
    final body = await _post('/integrations/connections/$id/test', {});
    return body;
  }

  @override
    Future<List<IntegrationRun>> getIntegrationRuns() async {
    final body = await _get('/integrations/runs');
    return _asList(body, 'runs')
        .whereType<Map>()
        .map((m) => IntegrationRun(
              id: _str(m, 'id'),
              connectionId: _str(m, 'connection_id'),
              status: _str(m, 'status'),
              phase: _str(m, 'phase', 'pending'),
              startedAt: _date(m, 'created_at'),
              processed:
                  m['valid_count'] is int ? m['valid_count'] as int : null,
              errorCount: m['invalid_count'] is int ? m['invalid_count'] as int : null,
              total: (m['valid_count'] is int && m['invalid_count'] is int)
                  ? (m['valid_count'] as int) + (m['invalid_count'] as int)
                  : null,
              error: _str(m, 'error', ''),
              endedAt: _date(m, 'finished_at'),
            ))
        .toList();
  }

  @override
  Future<StagingPreview> uploadImportFile({
    required String filename,
    required List<int> bytes,
    required String type,
  }) async {
    final req = http.MultipartRequest('POST', _uri('/integrations/uploads'));
    final headers = await _headers();
    headers.remove('Content-Type');
    headers['Idempotency-Key'] = _idemKey();
    req.headers.addAll(headers);
    req.fields['type'] = type;
    req.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );
    final streamed = await _client.send(req);
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      _throwEnvelope(resp);
    }
    final decoded = json.decode(resp.body) as Map<String, dynamic>;
    return _parseStagingPreview(decoded);
  }

  @override
  Future<StagingPreview> fetchGoogleSheet({
    required String sheetId,
    String tab = 'Sheet1',
  }) async {
    final body = await _post(
      '/integrations/google-sheets/fetch',
      {'sheet_id': sheetId, 'tab': tab},
      extraHeaders: {'Idempotency-Key': _idemKey()},
    );
    return _parseStagingPreview(body);
  }

  @override
  Future<StagingPreview> getRunPreview(String runId) async {
    final body = await _get('/integrations/runs/$runId/preview');
    return _parseStagingPreview(body as Map<String, dynamic>);
  }

  @override
  Future<ConfirmRunResult> confirmRun(String runId) async {
    final body = await _post(
      '/integrations/runs/$runId/confirm',
      {},
      extraHeaders: {'Idempotency-Key': _idemKey()},
    );
    final drafts = _asList(body, 'draft_requests')
        .map((e) => e.toString())
        .toList();
    return ConfirmRunResult(
      runId: _str(body, 'run_id', runId),
      status: _str(body, 'status', 'confirmed'),
      draftRequests: drafts,
    );
  }

  ReconciliationRun _parseReconciliation(Map m) {
    final rawEx = m['exceptions'] is List
        ? m['exceptions'] as List
        : _asList(m, 'exceptions_json');
    return ReconciliationRun(
      id: _str(m, 'id'),
      status: _str(m, 'status'),
      startedAt: _date(m, 'created_at'),
      exceptions: rawEx.map((e) => e.toString()).toList(),
    );
  }

  @override
  Future<List<ReconciliationRun>> getReconciliations() async {
    final body = await _get('/reconciliations');
    final list = _asList(body, 'runs').isNotEmpty
        ? _asList(body, 'runs')
        : _asList(body, 'reconciliations');
    return list.whereType<Map>().map(_parseReconciliation).toList();
  }

  @override
  Future<ReconciliationRun> runReconciliation({String scope = 'cash'}) async {
    final body = await _post(
      '/reconciliations',
      {'scope': scope},
      extraHeaders: {'Idempotency-Key': _idemKey()},
    );
    return _parseReconciliation(body);
  }

  List<InventoryBucket> _parseInventoryBuckets(dynamic body) {
    return _asList(body, 'buckets')
        .whereType<Map>()
        .map((m) => InventoryBucket(
              bucket: _str(m, 'bucket'),
              inboundQty: _str(m, 'inbound_qty', '0'),
              outboundQty: _str(m, 'outbound_qty', '0'),
              netQty: _str(m, 'net_qty', '0'),
              receiptCount:
                  m['receipt_count'] is int ? m['receipt_count'] as int : 0,
              issueCount: m['issue_count'] is int ? m['issue_count'] as int : 0,
            ))
        .toList();
  }

  List<CashflowBucket> _parseCashflowBuckets(dynamic body) {
    return _asList(body, 'buckets')
        .whereType<Map>()
        .map((m) => CashflowBucket(
              bucket: _str(m, 'bucket'),
              totalIn: _str(m, 'total_in', '0'),
              totalOut: _str(m, 'total_out', '0'),
              net: _str(m, 'net', '0'),
              journalCount:
                  m['journal_count'] is int ? m['journal_count'] as int : 0,
            ))
        .toList();
  }

  @override
  Future<List<InventoryBucket>> getInventoryDaily({
    String? dateFrom,
    String? dateTo,
  }) async {
    final body = await _get('/reports/inventory-daily', {
      if (dateFrom != null) 'date_from': dateFrom,
      if (dateTo != null) 'date_to': dateTo,
    });
    return _parseInventoryBuckets(body);
  }

  @override
  Future<List<InventoryBucket>> getInventoryMonthly({
    String? dateFrom,
    String? dateTo,
  }) async {
    final body = await _get('/reports/inventory-monthly', {
      if (dateFrom != null) 'date_from': dateFrom,
      if (dateTo != null) 'date_to': dateTo,
    });
    return _parseInventoryBuckets(body);
  }

  @override
  Future<List<CashflowBucket>> getCashflowDaily({
    String? dateFrom,
    String? dateTo,
  }) async {
    final body = await _get('/reports/cashflow-daily', {
      if (dateFrom != null) 'date_from': dateFrom,
      if (dateTo != null) 'date_to': dateTo,
    });
    return _parseCashflowBuckets(body);
  }

  @override
  Future<List<CashflowBucket>> getCashflowMonthly({
    String? dateFrom,
    String? dateTo,
  }) async {
    final body = await _get('/reports/cashflow-monthly', {
      if (dateFrom != null) 'date_from': dateFrom,
      if (dateTo != null) 'date_to': dateTo,
    });
    return _parseCashflowBuckets(body);
  }

  @override
  Future<List<StagnationItem>> getStagnation({
    int watchDays = 30,
    int stagnantDays = 60,
    int criticalDays = 90,
  }) async {
    final body = await _get('/reports/stagnation', {
      'watch_days': '$watchDays',
      'stagnant_days': '$stagnantDays',
      'critical_days': '$criticalDays',
    });
    return _asList(body, 'items')
        .whereType<Map>()
        .map((m) => StagnationItem(
              itemId: _str(m, 'item_id'),
              sku: _str(m, 'sku'),
              name: _str(m, 'name'),
              quantity: _str(m, 'quantity', '0'),
              daysSinceLastIssue: m['days_since_last_issue'] is int
                  ? m['days_since_last_issue'] as int
                  : null,
              severity: _str(m, 'severity', 'normal'),
            ))
        .toList();
  }
}
