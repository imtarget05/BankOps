import 'dart:async';

import '../models/dtos.dart';

/// Kết quả lỗi API demo (409/422…).
class ApiException implements Exception {
  ApiException(this.code, this.message, {this.requestId});

  final String code;
  final String message;
  final String? requestId;

  @override
  String toString() => 'ApiException($code): $message';
}

/// Hợp đồng repository theo docs/06-api.md. UI chỉ phụ thuộc interface này;
/// backend FastAPI có thể nối sau bằng cùng contract.
abstract class BankOpsRepository {
  // POST /auth/login, GET /me
  Future<List<AppUser>> loadUsers();
  Future<AppUser> login(String username);

  // GET /inventory/locations, /items, /balances, /assets
  Future<List<InventoryLocation>> getLocations();
  Future<List<InventoryItem>> getItems();
  Future<List<StockBalance>> getBalances({String? locationId});
  Future<List<AssetRecord>> getAssets({String? locationId});
  Future<List<StockMovement>> getMovements({String? itemId});

  // CRUD Inventory Items & Locations
  Future<InventoryItem> createItem({
    required String sku,
    required String name,
    required String unit,
    bool trackedSerial = false,
  });
  Future<InventoryItem> updateItem({
    required String id,
    String? name,
    String? unit,
    bool? trackedSerial,
  });
  Future<void> deleteItem(String id);

  Future<InventoryLocation> createLocation({
    required String code,
    required String name,
  });
  Future<InventoryLocation> updateLocation({
    required String id,
    String? name,
  });
  Future<void> deleteLocation(String id);

  // GET /inventory/requests, POST /inventory/requests
  Future<List<StockRequest>> getStockRequests();
  Future<StockRequest> createStockRequest({
    required RequestKind kind,
    String? sourceLocationId,
    String? destLocationId,
    required List<StockRequestLine> lines,
    String? reason,
  });
  Future<void> deleteStockRequest(String id);
  // POST /inventory/requests/{id}/submit|approve|reject
  Future<StockRequest> submitStockRequest(String id);
  Future<StockRequest> approveStockRequest(String id);
  Future<StockRequest> rejectStockRequest(String id, String reason);

  // GET /cash-sim/boxes, /balances, /journals, /requests
  Future<List<Cashbox>> getCashboxes();
  Future<Cashbox> createCashbox({
    required String code,
    required String name,
    String currency = 'VND',
    String openingBalance = '0.00',
  });
  Future<Cashbox> updateCashbox({
    required String id,
    String? name,
  });
  Future<void> deleteCashbox(String id);

  Future<List<CashBalance>> getCashBalances();
  Future<List<JournalEntry>> getJournals();
  Future<List<CashRequest>> getCashRequests();
  Future<CashRequest> createCashRequest({
    required String cashboxId,
    required RequestKind kind,
    required String amount,
    String? reason,
  });
  Future<void> deleteCashRequest(String id);
  Future<CashRequest> submitCashRequest(String id);
  Future<CashRequest> approveCashRequest(String id);
  Future<CashRequest> rejectCashRequest(String id, String reason);

  // GET /approvals/inbox & AI Thẩm định rủi ro
  Future<List<ApprovalItem>> getApprovalInbox();
  Future<AiRiskAssessment> assessApprovalItem(ApprovalItem item);
  Stream<String> get approvalNotifications;


  // GET /activity, GET /events/stream
  Future<List<ActivityEvent>> getActivity({String? cursor});

  // GET /integrations/connections, /integration-runs
  Future<List<IntegrationConnection>> getConnections();
  Future<IntegrationConnection> createConnection({
    required String name,
    required String type,
    String? endpoint,
    Map<String, dynamic>? config,
  });
  Future<IntegrationConnection> updateConnection({
    required String id,
    String? name,
    String? endpoint,
    String? status,
  });
  Future<void> deleteConnection(String id);
  Future<Map<String, dynamic>> testConnection(String id);
  Future<List<IntegrationRun>> getIntegrationRuns();
  Future<StagingPreview> uploadImportFile({
    required String filename,
    required List<int> bytes,
    required String type,
  });
  Future<StagingPreview> fetchGoogleSheet({
    required String sheetId,
    String tab = 'Sheet1',
  });
  Future<StagingPreview> getRunPreview(String runId);
  Future<ConfirmRunResult> confirmRun(String runId);

  // GET /reconciliations, POST /reconciliations
  Future<List<ReconciliationRun>> getReconciliations();
  Future<ReconciliationRun> runReconciliation({String scope = 'cash'});

  // GET /reports/*
  Future<List<InventoryBucket>> getInventoryDaily({
    String? dateFrom,
    String? dateTo,
  });
  Future<List<InventoryBucket>> getInventoryMonthly({
    String? dateFrom,
    String? dateTo,
  });
  Future<List<CashflowBucket>> getCashflowDaily({
    String? dateFrom,
    String? dateTo,
  });
  Future<List<CashflowBucket>> getCashflowMonthly({
    String? dateFrom,
    String? dateTo,
  });
  Future<List<StagnationItem>> getStagnation({
    int watchDays = 30,
    int stagnantDays = 60,
    int criticalDays = 90,
  });
}
