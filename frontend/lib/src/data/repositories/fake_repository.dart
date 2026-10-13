import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../models/dtos.dart';
import 'bankops_repository.dart';

part 'seed_data.dart';

/// Repository demo: đọc sample-data/ + mô phỏng latency và SSE trong bộ nhớ.
class FakeBankOpsRepository implements BankOpsRepository {
  FakeBankOpsRepository(
      {Random? random, Duration latency = const Duration(milliseconds: 350)})
      : _random = random ?? Random(7),
        _latency = latency;

  final Random _random;
  final Duration _latency;
  final _approvalStreamCtrl = StreamController<String>.broadcast();

  @override
  void dispose() {
    _approvalStreamCtrl.close();
  }

  @override
  Stream<String> get approvalNotifications => _approvalStreamCtrl.stream;

  Future<T> _delay<T>(T value) {
    if (_latency == Duration.zero) return Future.value(value);
    return Future<T>.delayed(
      _latency ~/ 2 +
          Duration(
              milliseconds: _random.nextInt(_latency.inMilliseconds ~/ 2 + 1)),
      () => value,
    );
  }

  // ---- users ----
  final _users = <AppUser>[];

  @override
  Future<HealthStatus> getHealth() => _delay(
        const HealthStatus(alive: true, version: '0.1.0', latencyMs: 0),
      );

  @override
  Future<List<AppUser>> loadUsers() async {
    if (_users.isEmpty) _users.addAll(_seedUsers());
    return _delay(List.of(_users));
  }

  @override
  Future<AppUser> login(String username) => _delay(_users.firstWhere(
      (u) => u.username == username,
      orElse: () => throw ApiException('NOT_FOUND', 'Không tìm thấy user')));

  // ---- inventory ----
  final _locations = <InventoryLocation>[];

  @override
  Future<List<InventoryLocation>> getLocations() async {
    if (_locations.isEmpty) _locations.addAll(_seedLocations());
    return _delay(List.of(_locations));
  }

  @override
  Future<InventoryLocation> createLocation({
    required String code,
    required String name,
    String? address,
  }) async {
    if (_locations.isEmpty) _locations.addAll(_seedLocations());
    final loc = InventoryLocation(
      id: 'loc-000${_locations.length + 1}',
      code: code,
      name: name,
    );
    _locations.add(loc);
    return _delay(loc);
  }

  @override
  Future<InventoryLocation> updateLocation({
    required String id,
    String? name,
  }) async {
    final idx = _locations.indexWhere((l) => l.id == id);
    if (idx < 0) throw ApiException('NOT_FOUND', 'Không tìm thấy điểm lưu trữ');
    final cur = _locations[idx];
    _locations[idx] = InventoryLocation(
      id: cur.id,
      code: cur.code,
      name: name ?? cur.name,
    );
    return _delay(_locations[idx]);
  }

  @override
  Future<void> deleteLocation(String id) async {
    _locations.removeWhere((l) => l.id == id);
    return _delay(null);
  }

  final _items = <InventoryItem>[];

  @override
  Future<List<InventoryItem>> getItems() async {
    if (_items.isEmpty) _items.addAll(_seedItems());
    return _delay(List.of(_items));
  }

  @override
  Future<InventoryItem> createItem({
    required String sku,
    required String name,
    required String unit,
    bool trackedSerial = false,
  }) async {
    if (_items.isEmpty) _items.addAll(_seedItems());
    final itm = InventoryItem(
      id: 'itm-000${_items.length + 1}',
      sku: sku,
      name: name,
      unit: unit,
      trackedSerial: trackedSerial,
    );
    _items.add(itm);
    return _delay(itm);
  }

  @override
  Future<InventoryItem> updateItem({
    required String id,
    String? name,
    String? unit,
    bool? trackedSerial,
  }) async {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx < 0) throw ApiException('NOT_FOUND', 'Không tìm thấy vật tư');
    final cur = _items[idx];
    _items[idx] = InventoryItem(
      id: cur.id,
      sku: cur.sku,
      name: name ?? cur.name,
      unit: unit ?? cur.unit,
      trackedSerial: trackedSerial ?? cur.trackedSerial,
    );
    return _delay(_items[idx]);
  }

  @override
  Future<void> deleteItem(String id) async {
    _items.removeWhere((i) => i.id == id);
    return _delay(null);
  }

  @override
  Future<List<StockBalance>> getBalances({String? locationId}) =>
      _delay(_seedBalances()
          .where((b) => locationId == null || b.locationId == locationId)
          .toList());

  @override
  Future<List<AssetRecord>> getAssets({String? locationId}) =>
      _delay(_seedAssets()
          .where((a) => locationId == null || a.locationId == locationId)
          .toList());

  @override
  Future<List<StockMovement>> getMovements({String? itemId}) =>
      _delay(_seedMovements()
          .where((m) => itemId == null || m.itemId == itemId)
          .toList());

  final _stockRequests = <StockRequest>[];

  @override
  Future<List<StockRequest>> getStockRequests() async {
    if (_stockRequests.isEmpty) _stockRequests.addAll(_seedStockRequests());
    return _delay(List.of(_stockRequests));
  }

  @override
  Future<StockRequest> createStockRequest({
    required RequestKind kind,
    String? sourceLocationId,
    String? destLocationId,
    required List<StockRequestLine> lines,
    String? reason,
  }) async {
    if (_stockRequests.isEmpty) _stockRequests.addAll(_seedStockRequests());
    final created = StockRequest(
      id: 'sr-000${_stockRequests.length + 1}',
      kind: kind,
      status: RequestStatus.draft,
      version: 1,
      createdBy: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
      createdByName: 'Nguyễn An (giả)',
      locationId: sourceLocationId ??
          destLocationId ??
          'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
      items: lines,
      reason: reason ?? '',
      createdAt: DateTime.now().toUtc(),
      destinationLocationId: destLocationId,
    );
    _stockRequests.insert(0, created);
    return _delay(created);
  }

  @override
  Future<void> deleteStockRequest(String id) async {
    final idx = _stockRequests.indexWhere((r) => r.id == id);
    if (idx < 0) throw ApiException('NOT_FOUND', 'Không tìm thấy phiếu');
    if (_stockRequests[idx].status != RequestStatus.draft) {
      throw ApiException(
          'CANNOT_DELETE', 'Chỉ có thể xoá phiếu ở trạng thái nháp');
    }
    _stockRequests.removeAt(idx);
    return _delay(null);
  }

  @override
  Future<StockRequest> submitStockRequest(String id) =>
      _transitionStock(id, RequestStatus.pending);

  @override
  Future<StockRequest> approveStockRequest(String id, {String? supervisorPin}) =>
      _transitionStock(id, RequestStatus.posted);

  @override
  Future<StockRequest> rejectStockRequest(String id, String reason) =>
      _transitionStock(id, RequestStatus.rejected);

  Future<StockRequest> _transitionStock(String id, RequestStatus to) async {
    final idx = _stockRequests.indexWhere((r) => r.id == id);
    if (idx < 0) throw ApiException('NOT_FOUND', 'Không tìm thấy phiếu');
    final r = _stockRequests[idx];
    if (r.status.isFinal) {
      throw ApiException('INVALID_STATE', 'Phiếu đã chốt trạng thái');
    }
    _stockRequests[idx] = _copyStock(r, to);
    if (to == RequestStatus.pending) {
      _approvalStreamCtrl.add('new_request:$id:kho');
    } else {
      _approvalStreamCtrl.add('processed:$id');
    }
    return _delay(_stockRequests[idx]);
  }

  StockRequest _copyStock(StockRequest r, RequestStatus to) => StockRequest(
        id: r.id,
        kind: r.kind,
        status: to,
        version: r.version + 1,
        createdBy: r.createdBy,
        createdByName: r.createdByName,
        locationId: r.locationId,
        items: r.items,
        reason: r.reason,
        createdAt: r.createdAt,
        approvedBy: r.approvedBy,
        approvedByName: r.approvedByName,
        rejectReason: r.rejectReason,
        destinationLocationId: r.destinationLocationId,
      );

  // ---- cash sim ----
  final _cashboxes = <Cashbox>[];

  @override
  Future<List<Cashbox>> getCashboxes() async {
    if (_cashboxes.isEmpty) _cashboxes.addAll(_seedCashboxes());
    return _delay(List.of(_cashboxes));
  }

  @override
  Future<Cashbox> createCashbox({
    required String code,
    required String name,
    String currency = 'VND',
    String openingBalance = '0.00',
  }) async {
    if (_cashboxes.isEmpty) _cashboxes.addAll(_seedCashboxes());
    final box = Cashbox(
      id: 'cb-000${_cashboxes.length + 1}',
      code: code,
      name: name,
      openingBalance: openingBalance,
    );
    _cashboxes.add(box);
    return _delay(box);
  }

  @override
  Future<Cashbox> updateCashbox({
    required String id,
    String? name,
  }) async {
    final idx = _cashboxes.indexWhere((b) => b.id == id);
    if (idx < 0) throw ApiException('NOT_FOUND', 'Không tìm thấy kết sắt');
    final cur = _cashboxes[idx];
    _cashboxes[idx] = Cashbox(
      id: cur.id,
      code: cur.code,
      name: name ?? cur.name,
      openingBalance: cur.openingBalance,
    );
    return _delay(_cashboxes[idx]);
  }

  @override
  Future<void> deleteCashbox(String id) async {
    _cashboxes.removeWhere((b) => b.id == id);
    return _delay(null);
  }

  @override
  Future<List<CashBalance>> getCashBalances() => _delay(_seedCashBalances());

  @override
  Future<List<JournalEntry>> getJournals() => _delay(_seedJournals());

  final _cashRequests = <CashRequest>[];

  @override
  Future<List<CashRequest>> getCashRequests() async {
    if (_cashRequests.isEmpty) _cashRequests.addAll(_seedCashRequests());
    return _delay(List.of(_cashRequests));
  }

  @override
  Future<CashRequest> createCashRequest({
    required String cashboxId,
    required RequestKind kind,
    required String amount,
    String? reason,
  }) async {
    if (_cashRequests.isEmpty) _cashRequests.addAll(_seedCashRequests());
    final created = CashRequest(
      id: 'cr-000${_cashRequests.length + 1}',
      kind: kind,
      status: RequestStatus.draft,
      version: 1,
      cashboxId: cashboxId,
      amount: amount,
      currency: 'VND',
      reason: reason ?? '',
      createdBy: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
      createdByName: 'Nguyễn An (giả)',
      createdAt: DateTime.now().toUtc(),
    );
    _cashRequests.insert(0, created);
    return _delay(created);
  }

  @override
  Future<void> deleteCashRequest(String id) async {
    final idx = _cashRequests.indexWhere((r) => r.id == id);
    if (idx < 0) throw ApiException('NOT_FOUND', 'Không tìm thấy phiếu');
    if (_cashRequests[idx].status != RequestStatus.draft) {
      throw ApiException(
          'CANNOT_DELETE', 'Chỉ có thể xoá phiếu ở trạng thái nháp');
    }
    _cashRequests.removeAt(idx);
    return _delay(null);
  }

  @override
  Future<CashRequest> submitCashRequest(String id) =>
      _transitionCash(id, RequestStatus.pending);

  @override
  Future<CashRequest> approveCashRequest(String id, {String? supervisorPin}) =>
      _transitionCash(id, RequestStatus.posted);

  @override
  Future<CashRequest> rejectCashRequest(String id, String reason) =>
      _transitionCash(id, RequestStatus.rejected);

  Future<CashRequest> _transitionCash(String id, RequestStatus to) async {
    final idx = _cashRequests.indexWhere((r) => r.id == id);
    if (idx < 0) throw ApiException('NOT_FOUND', 'Không tìm thấy phiếu');
    final r = _cashRequests[idx];
    if (r.status.isFinal) {
      throw ApiException('INVALID_STATE', 'Phiếu đã chốt trạng thái');
    }
    _cashRequests[idx] = CashRequest(
      id: r.id,
      kind: r.kind,
      status: to,
      version: r.version + 1,
      cashboxId: r.cashboxId,
      amount: r.amount,
      currency: r.currency,
      reason: r.reason,
      createdBy: r.createdBy,
      createdByName: r.createdByName,
      createdAt: r.createdAt,
      approvedBy: r.approvedBy,
      approvedByName: r.approvedByName,
      rejectReason: r.rejectReason,
    );
    if (to == RequestStatus.pending) {
      _approvalStreamCtrl.add('new_request:$id:quỹ');
    } else {
      _approvalStreamCtrl.add('processed:$id');
    }
    return _delay(_cashRequests[idx]);
  }

  // ---- approvals / activity / integrations ----
  @override
  Future<List<ApprovalItem>> getApprovalInbox() async {
    if (_stockRequests.isEmpty) _stockRequests.addAll(_seedStockRequests());
    if (_cashRequests.isEmpty) _cashRequests.addAll(_seedCashRequests());
    final items = <ApprovalItem>[
      for (final r
          in _stockRequests.where((x) => x.status == RequestStatus.pending))
        ApprovalItem(
          id: r.id,
          kind: 'inventory',
          maker: r.createdByName,
          impact: 'Kho (${r.kind.name}) · ${r.items.fold<num>(0, (total, line) => total + (num.tryParse(line.quantity) ?? 0))} đơn vị',
          detail: r.reason.isEmpty ? r.id : r.reason,
          approvalDetail: {
            'kind': r.kind.name,
            'total_quantity': r.items.fold<num>(0, (total, line) => total + (num.tryParse(line.quantity) ?? 0)).toString(),
          },
        ),
      for (final r
          in _cashRequests.where((x) => x.status == RequestStatus.pending))
        ApprovalItem(
          id: r.id,
          kind: 'cash',
          maker: r.createdByName,
          impact:
              '${r.kind == RequestKind.payment ? '-' : '+'}${r.amount} ${r.currency}',
          detail: r.reason.isEmpty ? r.id : r.reason,
        ),
    ];
    return _delay(items);
  }

  @override
  Future<AiRiskAssessment> assessApprovalItem(ApprovalItem item) async {
    final isCash = item.kind.toLowerCase() == 'cash' ||
        item.kind.toLowerCase().contains('quỹ');
    var rawImpact = item.impact;
    final decimalMatch =
        RegExp(r'[\.,]\d{1,2}(?:\s|[a-zA-Z]|$)').firstMatch(rawImpact);
    if (decimalMatch != null) {
      rawImpact = rawImpact.substring(0, decimalMatch.start);
    }
    final digits = rawImpact.replaceAll(RegExp(r'[^\d]'), '');
    final val = int.tryParse(digits) ?? 0;

    String riskLevel = 'low';
    int riskScore = 20;
    final flagged = <String>[];
    final recs = <String>[];

    if (isCash) {
      if (val >= 500000000) {
        riskLevel = 'high';
        riskScore = 88;
        flagged.add('Giá trị giao dịch vượt ngưỡng kiểm soát kép đặc biệt (≥ 500.000.000 VND).');
        flagged.add('Bắt buộc xác thực mã PIN Kiểm soát viên (Supervisor PIN) và đóng dấu Audit Stamp SHA-256.');
        recs.add('Kiểm đếm tiền mặt thực tế tại két và đối chiếu phiếu rút/nộp tiền gốc.');
        recs.add('Yêu cầu 2 chữ ký Maker và Checker trên biên bản bàn giao tiền mặt.');
      } else if (val >= 200000000) {
        riskLevel = 'medium';
        riskScore = 58;
        flagged.add('Giao dịch giá trị trung bình lớn (200.000.000 - 500.000.000 VND).');
        recs.add('Đối chiếu chứng từ ký nhận của khách hàng/GDV trước khi duyệt.');
      } else {
        riskLevel = 'low';
        riskScore = 20;
        recs.add('Giao dịch trong hạn mức định mức thường lệ của quầy.');
      }
    } else {
      if (val >= 50) {
        riskLevel = 'high';
        riskScore = 85;
        flagged.add('Số lượng xuất/nhập ấn chỉ/phôi thẻ vượt hạn mức (≥ 50 đơn vị).');
        flagged.add('Nguy cơ thất thoát phôi bảo mật (thẻ chip EMV, sổ séc trắng).');
        recs.add('Kiểm đếm dải số serial và niêm phong hộp phôi trước khi ký nhận.');
      } else if (val >= 20) {
        riskLevel = 'medium';
        riskScore = 52;
        flagged.add('Số lượng phôi xuất kho trung bình (20 - 50 đơn vị).');
        recs.add('Kiểm tra kế hoạch cấp phát ấn chỉ định kỳ của phòng giao dịch.');
      } else {
        riskLevel = 'low';
        riskScore = 18;
        recs.add('Lệnh xuất nhập vật tư trong định mức ngày.');
      }
    }

    if (item.detail.trim().length < 5) {
      flagged.add('Lý do giao dịch quá ngắn hoặc không nêu rõ mục đích (< 5 ký tự).');
      riskScore = min(98, riskScore + 15);
      if (riskLevel == 'low') riskLevel = 'medium';
      recs.add('Yêu cầu Maker bổ sung diễn giải chi tiết mục đích nghiệp vụ.');
    }

    final stampSeed = '${item.id}:${item.maker}:${item.impact}:$riskScore';
    final stampBytes = utf8.encode(stampSeed);
    final auditStamp = stampBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .padRight(64, '0')
        .substring(0, 64);

    final summary = 'Đánh giá rủi ro: Mức độ ${riskLevel.toUpperCase()} ($riskScore/100) cho phiếu ${item.id}. '
        '${riskLevel == 'high' ? 'Cần kiểm soát kép và nhập PIN KSV.' : 'Đủ điều kiện xem xét phê duyệt.'}';

    return _delay(AiRiskAssessment(
      requestId: item.id,
      riskLevel: riskLevel,
      riskScore: riskScore,
      summary: summary,
      flaggedRules: flagged,
      recommendations: recs,
      auditStamp: auditStamp,
    ));
  }

  final _events = <ActivityEvent>[];

  @override
  Future<List<ActivityEvent>> getActivity({String? cursor}) async {
    if (_events.isEmpty) _events.addAll(_seedActivity());
    return _delay(List.of(_events));
  }

  final _connections = <IntegrationConnection>[];

  @override
  Future<List<IntegrationConnection>> getConnections() async {
    if (_connections.isEmpty) _connections.addAll(_seedConnections());
    return _delay(List.of(_connections));
  }

  @override
  Future<IntegrationConnection> createConnection({
    required String name,
    required String type,
    String? endpoint,
    Map<String, dynamic>? config,
  }) async {
    if (_connections.isEmpty) _connections.addAll(_seedConnections());
        final conn = IntegrationConnection(
      id: 'conn-000${_connections.length + 1}',
      name: name,
      endpoint: endpoint ?? type,
      status: 'connected',
      lastTestedAt: null,
      lastError: null,
    );
    _connections.add(conn);
    return _delay(conn);
  }

  @override
  Future<IntegrationConnection> updateConnection({
    required String id,
    String? name,
    String? endpoint,
    String? status,
  }) async {
    final idx = _connections.indexWhere((c) => c.id == id);
    if (idx < 0) throw ApiException('NOT_FOUND', 'Không tìm thấy kết nối');
        final cur = _connections[idx];
    _connections[idx] = IntegrationConnection(
      id: cur.id,
      name: name ?? cur.name,
      endpoint: endpoint ?? cur.endpoint,
      status: status ?? cur.status,
      lastTestedAt: cur.lastTestedAt,
      lastError: cur.lastError,
    );
    return _delay(_connections[idx]);
  }

  @override
  Future<void> deleteConnection(String id) async {
    _connections.removeWhere((c) => c.id == id);
    return _delay(null);
  }

  @override
  Future<Map<String, dynamic>> testConnection(String id) async {
    return _delay({
      'success': true,
      'latency_ms': 45,
      'message': 'Kết nối hoạt động bình thường (mô phỏng)',
    });
  }

  final _runs = <IntegrationRun>[];
  final _stagingPreviews = <String, StagingPreview>{};

  @override
  Future<List<IntegrationRun>> getIntegrationRuns() async {
    if (_runs.isEmpty) _runs.addAll(_seedRuns());
    return _delay(List.of(_runs));
  }

  @override
  Future<StagingPreview> uploadImportFile({
    required String filename,
    required List<int> bytes,
    required String type,
  }) async {
    final text = utf8.decode(bytes, allowMalformed: true);
    final rawRows = <Map<String, dynamic>>[];
    if (type == 'json' || filename.toLowerCase().endsWith('.json')) {
      final decoded = json.decode(text);
      final list = decoded is Map && decoded['rows'] is List
          ? decoded['rows'] as List
          : (decoded is List ? decoded : const []);
      for (final item in list) {
        if (item is Map) {
          rawRows.add(item.map((k, v) => MapEntry(k.toString(), v)));
        }
      }
    } else {
      final lines = text
          .split(RegExp(r'\r?\n'))
          .where((l) => l.trim().isNotEmpty)
          .toList();
      if (lines.isNotEmpty) {
        final headers = lines.first.split(',').map((h) => h.trim()).toList();
        for (var i = 1; i < lines.length; i++) {
          final cells = lines[i].split(',').map((c) => c.trim()).toList();
          final row = <String, dynamic>{};
          for (var j = 0; j < headers.length && j < cells.length; j++) {
            row[headers[j]] = cells[j];
          }
          rawRows.add(row);
        }
      }
    }
    return _delay(_stageRows(rawRows));
  }

  @override
  Future<StagingPreview> fetchGoogleSheet({
    required String sheetId,
    String tab = 'Sheet1',
  }) async {
    if (sheetId.trim().length < 5) {
      throw ApiException('INVALID_SHEET_ID', 'sheet_id không hợp lệ');
    }
    final demoRows = <Map<String, dynamic>>[
      {
        'sku': 'DEMO-PAPER-A4',
        'location_code': 'DEMO-HN',
        'quantity': '15',
        'source_row_key': 'sheet-$sheetId-1',
      },
      {
        'sku': 'DEMO-LAPTOP',
        'location_code': 'DEMO-HCM',
        'quantity': '2',
        'source_row_key': 'sheet-$sheetId-2',
      },
    ];
    return _delay(_stageRows(demoRows));
  }

  StagingPreview _stageRows(List<Map<String, dynamic>> rawRows) {
    final validSkus = _seedItems().map((i) => i.sku).toSet();
    final validLocs = _seedLocations().map((l) => l.code).toSet();
    final staged = <StagingRow>[];
    var validCount = 0;
    var invalidCount = 0;
    for (var i = 0; i < rawRows.length; i++) {
      final r = rawRows[i];
      final errors = <String>[];
      final sku = (r['sku'] ?? r['item_sku'] ?? '').toString().trim();
      final loc = (r['location_code'] ?? r['location'] ?? '').toString().trim();
      final qty = double.tryParse((r['quantity'] ?? '').toString());
      if (sku.isEmpty) {
        errors.add('thiếu sku');
      } else if (!validSkus.contains(sku)) {
        errors.add("sku '$sku' không tồn tại");
      }
      if (loc.isEmpty) {
        errors.add('thiếu location_code');
      } else if (!validLocs.contains(loc)) {
        errors.add("location '$loc' không tồn tại");
      }
      if (qty == null || qty <= 0) {
        errors.add('quantity phải > 0');
      }
      final isValid = errors.isEmpty;
      if (isValid) {
        validCount++;
      } else {
        invalidCount++;
      }
      staged.add(StagingRow(
        rowIndex: i,
        sourceRowKey: (r['source_row_key'] ?? '$sku:$loc:$i').toString(),
        data: r,
        valid: isValid,
        errors: errors,
      ));
    }
    if (_runs.isEmpty) _runs.addAll(_seedRuns());
    final runId = 'ir-000${_runs.length + 1}';
    final preview = StagingPreview(
      runId: runId,
      validCount: validCount,
      invalidCount: invalidCount,
      rows: staged,
    );
    _stagingPreviews[runId] = preview;
        _runs.insert(
      0,
      IntegrationRun(
        id: runId,
        connectionId: 'ic-0001',
        status: 'staged',
        phase: 'staged',
        startedAt: DateTime.now().toUtc(),
        processed: validCount,
        errorCount: invalidCount,
        total: rawRows.length,
      ),
    );
    return preview;
  }

  @override
  Future<StagingPreview> getRunPreview(String runId) async {
    final preview = _stagingPreviews[runId];
    if (preview == null) {
      throw ApiException('NOT_FOUND', 'Không tìm thấy staging run $runId');
    }
    return _delay(preview);
  }

  @override
  Future<ConfirmRunResult> confirmRun(String runId) async {
    final preview = _stagingPreviews[runId];
    if (preview == null) {
      throw ApiException('NOT_FOUND', 'Không tìm thấy staging run $runId');
    }
    if (preview.invalidCount > 0) {
      throw ApiException(
        'CONFIRM_HAS_ERRORS',
        'Run còn ${preview.invalidCount} dòng lỗi — sửa nguồn rồi upload lại',
      );
    }
    if (preview.validCount == 0) {
      throw ApiException('CONFIRM_EMPTY', 'Run không có dòng hợp lệ');
    }
    if (_stockRequests.isEmpty) _stockRequests.addAll(_seedStockRequests());
    final draftId = 'sr-import-${_stockRequests.length + 1}';
    _stockRequests.insert(
      0,
      StockRequest(
        id: draftId,
        kind: RequestKind.receipt,
        status: RequestStatus.draft,
        version: 1,
        createdBy: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
        createdByName: 'Nguyễn An (giả)',
        locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
        items: const [
          StockRequestLine(
            itemId: 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
            quantity: '10.000',
          ),
        ],
        reason: 'Import từ staging run $runId',
        createdAt: DateTime.now().toUtc(),
      ),
    );
    if (_events.isEmpty) _events.addAll(_seedActivity());
    _events.insert(
      0,
      ActivityEvent(
        id: 'ae-import-${_events.length + 1}',
        occurredAt: DateTime.now().toUtc(),
        subjectId: runId,
        status: 'confirmed',
        messageKey: 'integration.run.confirmed',
        processed: preview.validCount,
        total: preview.rows.length,
      ),
    );
    return _delay(ConfirmRunResult(
      runId: runId,
      status: 'confirmed',
      draftRequests: [draftId],
    ));
  }

  @override
  Future<List<ReconciliationRun>> getReconciliations() =>
      _delay(_seedReconciliations());

  @override
  Future<ReconciliationRun> runReconciliation({String scope = 'cash'}) =>
      _delay(
        ReconciliationRun(
          id: 'rc-$scope-001',
          status: 'matched',
          startedAt: DateTime.now().toUtc(),
          exceptions: const [],
        ),
      );

  // ---- reports ----
  @override
  Future<List<InventoryBucket>> getInventoryDaily({
    String? dateFrom,
    String? dateTo,
  }) =>
      _delay(_seedInventoryDaily());

  @override
  Future<List<InventoryBucket>> getInventoryMonthly({
    String? dateFrom,
    String? dateTo,
  }) =>
      _delay(_seedInventoryMonthly());

  @override
  Future<List<CashflowBucket>> getCashflowDaily({
    String? dateFrom,
    String? dateTo,
  }) =>
      _delay(_seedCashflowDaily());

  @override
  Future<List<CashflowBucket>> getCashflowMonthly({
    String? dateFrom,
    String? dateTo,
  }) =>
      _delay(_seedCashflowMonthly());

  @override
  Future<List<StagnationItem>> getStagnation({
    int watchDays = 30,
    int stagnantDays = 60,
    int criticalDays = 90,
  }) =>
      _delay(_seedStagnation());
}
