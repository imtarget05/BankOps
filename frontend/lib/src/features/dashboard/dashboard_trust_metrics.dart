import '../../data/models/dtos.dart';

/// Facts used by the dashboard to prevent presentation-only percentages from
/// being mistaken for verified operational data.
class DashboardTrustMetrics {
  const DashboardTrustMetrics._({
    required this.cashCoverage,
    required this.stockCoverage,
    required this.cashState,
    required this.stockState,
    required this.ledgerState,
  });

  factory DashboardTrustMetrics.fromData({
    required List<Cashbox> cashboxes,
    required List<CashBalance> cashBalances,
    required List<InventoryLocation> locations,
    required List<InventoryItem> items,
    required List<StockBalance> balances,
    required List<ReconciliationRun> reconciliations,
  }) {
    final knownCashboxIds = cashboxes.map((box) => box.id).toSet();
    final coveredCashboxIds = cashBalances
        .where((balance) => knownCashboxIds.contains(balance.cashboxId))
        .map((balance) => balance.cashboxId)
        .toSet();
    final cashCoverage =
        cashboxes.isEmpty ? null : coveredCashboxIds.length / cashboxes.length;

    final expectedStockPairs = <String>{
      for (final location in locations)
        for (final item in items) '${location.id}:${item.id}',
    };
    final coveredStockPairs = balances
        .map((balance) => '${balance.locationId}:${balance.itemId}')
        .where(expectedStockPairs.contains)
        .toSet();
    final stockCoverage = expectedStockPairs.isEmpty
        ? null
        : coveredStockPairs.length / expectedStockPairs.length;

    final latestReconciliation = reconciliations.isEmpty
        ? null
        : reconciliations.reduce(
            (current, candidate) =>
                candidate.startedAt.isAfter(current.startedAt)
                    ? candidate
                    : current,
          );

    return DashboardTrustMetrics._(
      cashCoverage: cashCoverage,
      stockCoverage: stockCoverage,
      cashState: _coverageState(cashCoverage),
      stockState: _coverageState(stockCoverage),
      ledgerState: latestReconciliation == null
          ? const DashboardDataState('Chưa đối soát', DashboardDataTone.neutral)
          : latestReconciliation.exceptions.isNotEmpty
              ? const DashboardDataState(
                  'Có ngoại lệ', DashboardDataTone.warning)
              : latestReconciliation.status == 'completed'
                  ? const DashboardDataState('Đã khớp', DashboardDataTone.good)
                  : const DashboardDataState(
                      'Đang đối soát', DashboardDataTone.neutral),
    );
  }

  final double? cashCoverage;
  final double? stockCoverage;
  final DashboardDataState cashState;
  final DashboardDataState stockState;
  final DashboardDataState ledgerState;

  static DashboardDataState _coverageState(double? coverage) {
    if (coverage == null) {
      return const DashboardDataState(
          'Chưa có dữ liệu', DashboardDataTone.neutral);
    }
    if (coverage < 1) {
      return const DashboardDataState(
          'Thiếu dữ liệu', DashboardDataTone.warning);
    }
    return const DashboardDataState('Đã kiểm tra', DashboardDataTone.good);
  }
}

enum DashboardDataTone { neutral, good, warning }

class DashboardDataState {
  const DashboardDataState(this.label, this.tone);

  final String label;
  final DashboardDataTone tone;
}
