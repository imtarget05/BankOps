import 'package:flutter/material.dart';

import '../../app/app_shell.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/role_visibility.dart';
import '../../core/widgets/demo_banner.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/dtos.dart';
import '../../data/repositories/bankops_repository.dart';
import 'reports_filter.dart';
import 'widgets/cashflow_chart.dart';
import 'widgets/inventory_chart.dart';
import 'widgets/stagnation_list.dart';

/// Màn báo cáo — biểu đồ nhập/xuất kho, dòng tiền mô phỏng, cảnh báo tồn đọng, và đối soát.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  ReportGranularity _granularity = ReportGranularity.daily;
  DateTimeRange? _dateRange;
  Future<_ReportsData>? _future;
  bool _reconciling = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = RepositoryScope.of(context);
    _future ??= _load(repo);
  }

  void _reload() {
    final repo = RepositoryScope.of(context);
    setState(() {
      _future = _load(repo);
    });
  }

  Future<void> _runReconciliation(String scope) async {
    if (_reconciling) return;
    setState(() => _reconciling = true);
    try {
      await RepositoryScope.of(context).runReconciliation(scope: scope);
      _reload();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không thể chạy đối soát: $error')));
    } finally {
      if (mounted) setState(() => _reconciling = false);
    }
  }

  Future<_ReportsData> _load(BankOpsRepository repo) async {
    final dateFrom = _dateRange?.start.toIso8601String();
    final dateTo = _dateRange?.end.toIso8601String();
    final invFuture = _granularity == ReportGranularity.daily
        ? repo.getInventoryDaily(dateFrom: dateFrom, dateTo: dateTo)
        : repo.getInventoryMonthly(dateFrom: dateFrom, dateTo: dateTo);
    final cashFuture = _granularity == ReportGranularity.daily
        ? repo.getCashflowDaily(dateFrom: dateFrom, dateTo: dateTo)
        : repo.getCashflowMonthly(dateFrom: dateFrom, dateTo: dateTo);

    final roles = RoleVisibility.rolesOf(SessionScope.maybeOf(context)?.user);
    final canViewReconciliation = roles.isEmpty ||
        roles.any((role) => const {'approver', 'checker', 'auditor', 'cash_sim_operator'}.contains(role));
    final results = await Future.wait([
      invFuture,
      cashFuture,
      repo.getStagnation(),
      canViewReconciliation ? _loadReconciliations(repo) : Future.value(<ReconciliationRun>[]),
    ]);
    return _ReportsData(
      inventoryBuckets: results[0] as List<InventoryBucket>,
      cashflowBuckets: results[1] as List<CashflowBucket>,
      stagnationItems: results[2] as List<StagnationItem>,
      reconciliations: results[3] as List<ReconciliationRun>,
    );
  }

  Future<List<ReconciliationRun>> _loadReconciliations(BankOpsRepository repo) async {
    try {
      return await repo.getReconciliations();
    } on ApiException catch (error) {
      if (error.code == 'FORBIDDEN' || error.code == 'HTTP_403') return [];
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: FutureBuilder<_ReportsData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: LoadingView());
          }
          if (snapshot.hasError) {
            return Center(
              child: ErrorView(
                message: '${snapshot.error}',
                onRetry: _reload,
              ),
            );
          }
          final data = snapshot.data!;
          final roles = RoleVisibility.rolesOf(SessionScope.maybeOf(context)?.user);
          final canRunReconciliation = roles.isEmpty ||
              roles.any((role) => const {'approver', 'checker', 'cash_sim_operator'}.contains(role));
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Báo cáo & Biểu đồ',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    const DemoBanner(),
                    const SizedBox(height: 12),
                    ReportsFilter(
                      granularity: _granularity,
                      onGranularityChanged: (g) {
                        _granularity = g;
                        _reload();
                      },
                      dateRange: _dateRange,
                      onDateRangeChanged: (range) {
                        _dateRange = range;
                        _reload();
                      },
                    ),
                  ],
                ),
              ),
              const TabBar(
                isScrollable: true,
                tabs: [
                  Tab(key: Key('tab-reports-inventory'), text: 'Nhập/Xuất kho'),
                  Tab(key: Key('tab-reports-cashflow'), text: 'Dòng tiền mô phỏng'),
                  Tab(key: Key('tab-reports-stagnation'), text: 'Tồn đọng'),
                  Tab(key: Key('tab-reports-reconciliation'), text: 'Đối soát'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: InventoryChart(buckets: data.inventoryBuckets),
                    ),
                    SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: CashflowChart(buckets: data.cashflowBuckets),
                    ),
                    SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: StagnationList(items: data.stagnationItems),
                    ),
                    _ReconciliationTab(
                      runs: data.reconciliations,
                      canRun: canRunReconciliation,
                      busy: _reconciling,
                      onRun: _runReconciliation,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ReconciliationTab extends StatelessWidget {
  const _ReconciliationTab({required this.runs, required this.canRun, required this.busy, required this.onRun});

  final List<ReconciliationRun> runs;
  final bool canRun;
  final bool busy;
  final ValueChanged<String> onRun;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (canRun) Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Wrap(spacing: 8, children: [
            OutlinedButton.icon(onPressed: busy ? null : () => onRun('cash'), icon: const Icon(Icons.savings_outlined), label: const Text('Đối soát quỹ')),
            OutlinedButton.icon(onPressed: busy ? null : () => onRun('inventory'), icon: const Icon(Icons.inventory_2_outlined), label: const Text('Đối soát kho')),
          ]),
        ),
        if (runs.isEmpty) const EmptyView(
          title: 'Chưa có lượt đối soát',
          subtitle: 'Chạy đối soát để kiểm tra chênh lệch giữa giao dịch và số dư.',
          icon: Icons.balance_outlined,
        ),
        for (final r in runs)
          Card(
            child: ListTile(
              title: Text('${r.id} [${r.status}]'),
              subtitle: Text('Ngoại lệ: ${r.exceptions.join(', ')}'),
              trailing: Icon(
                r.exceptions.isEmpty
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
                color: r.exceptions.isEmpty
                    ? context.statusColors.success
                    : context.statusColors.danger,
              ),
            ),
          ),
      ],
    );
  }
}

class _ReportsData {
  const _ReportsData({
    required this.inventoryBuckets,
    required this.cashflowBuckets,
    required this.stagnationItems,
    required this.reconciliations,
  });

  final List<InventoryBucket> inventoryBuckets;
  final List<CashflowBucket> cashflowBuckets;
  final List<StagnationItem> stagnationItems;
  final List<ReconciliationRun> reconciliations;
}
