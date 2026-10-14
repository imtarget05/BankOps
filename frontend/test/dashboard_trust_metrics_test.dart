import 'package:bankops/src/data/models/dtos.dart';
import 'package:bankops/src/features/dashboard/dashboard_trust_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('does not turn an empty cash dataset into a reassuring progress score',
      () {
    final metrics = DashboardTrustMetrics.fromData(
      cashboxes: [],
      cashBalances: [],
      locations: [],
      items: [],
      balances: [],
      reconciliations: [],
    );

    expect(metrics.cashCoverage, isNull);
    expect(metrics.cashState.label, 'Chưa có dữ liệu');
    expect(metrics.stockCoverage, isNull);
    expect(metrics.stockState.label, 'Chưa có dữ liệu');
    expect(metrics.ledgerState.label, 'Chưa đối soát');
  });

  test('uses the real coverage ratio and reconciliation exceptions', () {
    final metrics = DashboardTrustMetrics.fromData(
      cashboxes: const [
        Cashbox(
            id: 'vault', code: 'V1', name: 'Két chính', openingBalance: '0'),
        Cashbox(id: 'teller', code: 'T1', name: 'Quầy', openingBalance: '0'),
      ],
      cashBalances: const [
        CashBalance(cashboxId: 'vault', amount: '500', currency: 'VND')
      ],
      locations: const [InventoryLocation(id: 'hq', code: 'HQ', name: 'Hội sở')],
      items: const [
        InventoryItem(
            id: 'form-a',
            sku: 'A',
            name: 'Ấn chỉ A',
            unit: 'tờ',
            trackedSerial: false),
        InventoryItem(
            id: 'form-b',
            sku: 'B',
            name: 'Ấn chỉ B',
            unit: 'tờ',
            trackedSerial: false),
      ],
      balances: const [
        StockBalance(locationId: 'hq', itemId: 'form-a', quantity: '10')
      ],
      reconciliations: [
        ReconciliationRun(
            id: 'gl-1',
            status: 'completed',
            startedAt: DateTime(2026, 10, 14),
            exceptions: ['Sai lệch quỹ']),
      ],
    );

    expect(metrics.cashCoverage, 0.5);
    expect(metrics.cashState.label, 'Thiếu dữ liệu');
    expect(metrics.stockCoverage, 0.5);
    expect(metrics.stockState.label, 'Thiếu dữ liệu');
    expect(metrics.ledgerState.label, 'Có ngoại lệ');
  });
}
