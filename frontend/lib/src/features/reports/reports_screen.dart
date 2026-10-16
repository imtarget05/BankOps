import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_shell.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/report_share.dart';
import '../../core/util/role_visibility.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/demo_banner.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/dtos.dart';
import '../../data/repositories/bankops_repository.dart';
import 'reports_filter.dart';
import 'widgets/cashflow_chart.dart';
import 'widgets/executive_kpi_deck.dart';
import 'widgets/inventory_chart.dart';
import 'widgets/meeting_notes_tab.dart';
import 'widgets/meeting_presentation_modal.dart';
import 'widgets/meeting_report_pdf.dart';
import 'widgets/meeting_summary_formatter.dart';
import 'widgets/stagnation_list.dart';

/// Màn báo cáo điều hành & giao ban cuộc họp — biểu đồ nhập/xuất kho, dòng tiền mô phỏng, cảnh báo tồn đọng, đối soát và công cụ thuyết trình.
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
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Không thể chạy đối soát: ${friendlyError(error)}')));
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
        roles.any((role) => const {
              'approver',
              'checker',
              'auditor',
              'cash_sim_operator'
            }.contains(role));
    final results = await Future.wait([
      invFuture,
      cashFuture,
      repo.getStagnation(),
      canViewReconciliation
          ? _loadReconciliations(repo)
          : Future.value(<ReconciliationRun>[]),
      repo.getConsumptionTop(),
      repo.getShiftHistory(),
    ]);
    return _ReportsData(
      inventoryBuckets: results[0] as List<InventoryBucket>,
      cashflowBuckets: results[1] as List<CashflowBucket>,
      stagnationItems: results[2] as List<StagnationItem>,
      reconciliations: results[3] as List<ReconciliationRun>,
      consumptionTop: results[4] as List<ConsumptionTopItem>,
      shiftHistory: results[5] as List<ShiftHistoryItem>,
    );
  }

  Future<List<ReconciliationRun>> _loadReconciliations(
      BankOpsRepository repo) async {
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
      length: 7,
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
          final roles =
              RoleVisibility.rolesOf(SessionScope.maybeOf(context)?.user);
          final canRunReconciliation = roles.isEmpty ||
              roles.any((role) => const {
                    'approver',
                    'checker',
                    'cash_sim_operator'
                  }.contains(role));

          return NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Tiêu đề & các nút hành động cuộc họp
                      Wrap(
                        spacing: 16,
                        runSpacing: 10,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.start,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Báo cáo & Biểu đồ',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Trung tâm Báo cáo Điều hành & Đánh giá Giao ban Cuộc họp',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              FilledButton.icon(
                                key: const Key('btn-meeting-mode-header'),
                                onPressed: () => MeetingPresentationModal.show(
                                  context,
                                  inventoryBuckets: data.inventoryBuckets,
                                  cashflowBuckets: data.cashflowBuckets,
                                  stagnationItems: data.stagnationItems,
                                  reconciliations: data.reconciliations,
                                  granularity: _granularity,
                                  dateRange: _dateRange,
                                ),
                                icon: const Icon(Icons.co_present_outlined,
                                    size: 18),
                                label: const Text('Chế độ Cuộc họp'),
                              ),
                              OutlinedButton.icon(
                                key: const Key('btn-copy-meeting-header'),
                                onPressed: () {
                                  final md =
                                      MeetingSummaryFormatter.generateMarkdown(
                                    inventoryBuckets: data.inventoryBuckets,
                                    cashflowBuckets: data.cashflowBuckets,
                                    stagnationItems: data.stagnationItems,
                                    reconciliations: data.reconciliations,
                                    granularity: _granularity,
                                    dateRange: _dateRange,
                                  );
                                  Clipboard.setData(ClipboardData(text: md));
                                  AppToast.success(context,
                                      'Đã sao chép tóm tắt cuộc họp vào Clipboard.');
                                },
                                icon: const Icon(Icons.content_copy_outlined,
                                    size: 18),
                                label: const Text('Sao chép Tóm tắt'),
                              ),
                              OutlinedButton.icon(
                                key: const Key('btn-print-meeting-pdf-header'),
                                onPressed: () {
                                  ReportShare.printPdf(
                                    context,
                                    filename: 'bao-cao-van-hanh-kho-tra-sua.pdf',
                                    build: () => MeetingReportPdf.encode(
                                      inventoryBuckets: data.inventoryBuckets,
                                      cashflowBuckets: data.cashflowBuckets,
                                      stagnationItems: data.stagnationItems,
                                      reconciliations: data.reconciliations,
                                      granularity: _granularity,
                                      dateRange: _dateRange,
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.picture_as_pdf_outlined,
                                    size: 18),
                                label: const Text('In PDF A4'),
                              ),
                            ],
                          ),
                        ],
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
                      const SizedBox(height: 12),
                      // Bộ chỉ số điều hành cốt lõi (Executive KPI Deck)
                      ExecutiveKpiDeck(
                        cashflowBuckets: data.cashflowBuckets,
                        inventoryBuckets: data.inventoryBuckets,
                        stagnationItems: data.stagnationItems,
                        reconciliations: data.reconciliations,
                      ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(
                child: TabBar(
                  isScrollable: true,
                  tabs: [
                    Tab(key: Key('tab-reports-inventory'), text: 'Nhập/Xuất kho'),
                    Tab(
                        key: Key('tab-reports-cashflow'),
                        text: 'Dòng tiền mô phỏng'),
                    Tab(key: Key('tab-reports-stagnation'), text: 'Tồn đọng'),
                    Tab(key: Key('tab-reports-reconciliation'), text: 'Đối soát'),
                    Tab(
                        key: Key('tab-reports-meeting-notes'),
                        text: 'Biên bản Giao ban & Đánh giá'),
                    Tab(
                        key: Key('tab-reports-consumption-top'),
                        text: 'Top Tiêu Hao F&B'),
                    Tab(
                        key: Key('tab-reports-shift-history'),
                        text: 'Lịch Sử Chốt Ca'),
                  ],
                ),
              ),
            ],
            body: TabBarView(
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
                MeetingNotesTab(
                  inventoryBuckets: data.inventoryBuckets,
                  cashflowBuckets: data.cashflowBuckets,
                  stagnationItems: data.stagnationItems,
                  reconciliations: data.reconciliations,
                  granularity: _granularity,
                  dateRange: _dateRange,
                  onOpenPresentation: () => MeetingPresentationModal.show(
                    context,
                    inventoryBuckets: data.inventoryBuckets,
                    cashflowBuckets: data.cashflowBuckets,
                    stagnationItems: data.stagnationItems,
                    reconciliations: data.reconciliations,
                    granularity: _granularity,
                    dateRange: _dateRange,
                  ),
                ),
                _ConsumptionTopTab(items: data.consumptionTop),
                _ShiftHistoryTab(items: data.shiftHistory),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ReconciliationTab extends StatelessWidget {
  const _ReconciliationTab(
      {required this.runs,
      required this.canRun,
      required this.busy,
      required this.onRun});

  final List<ReconciliationRun> runs;
  final bool canRun;
  final bool busy;
  final ValueChanged<String> onRun;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (canRun)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(spacing: 8, children: [
              OutlinedButton.icon(
                  onPressed: busy ? null : () => onRun('cash'),
                  icon: const Icon(Icons.savings_outlined),
                  label: const Text('Đối soát quỹ')),
              OutlinedButton.icon(
                  onPressed: busy ? null : () => onRun('inventory'),
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('Đối soát kho')),
            ]),
          ),
        if (runs.isEmpty)
          const EmptyView(
            title: 'Chưa có lượt đối soát',
            subtitle:
                'Chạy đối soát để kiểm tra chênh lệch giữa giao dịch và số dư.',
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

class _ConsumptionTopTab extends StatelessWidget {
  const _ConsumptionTopTab({required this.items});

  final List<ConsumptionTopItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Chưa có dữ liệu tiêu hao nguyên liệu trong kỳ.'),
        ),
      );
    }

    final maxQty = items.fold<double>(
      0.0,
      (max, it) {
        final q = double.tryParse(it.usedQty) ?? 0.0;
        return q > max ? q : max;
      },
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.leaderboard_rounded,
                        color: Color(0xFF2563EB), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Top Nguyên Liệu Tiêu Hao (SRS §3.5)',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Tổng hợp lượng sử dụng qua các ca kiểm kê và xuất kho pha chế',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 16),
                itemBuilder: (context, idx) {
                  final it = items[idx];
                  final qty = double.tryParse(it.usedQty) ?? 0.0;
                  final ratio =
                      maxQty > 0 ? (qty / maxQty).clamp(0.0, 1.0) : 0.0;

                  Color rankColor = Colors.grey;
                  if (idx == 0) rankColor = const Color(0xFFEAB308); // Gold
                  if (idx == 1) rankColor = const Color(0xFF94A3B8); // Silver
                  if (idx == 2) rankColor = const Color(0xFFB45309); // Bronze

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: rankColor.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '#${idx + 1}',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                                color: rankColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  it.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  'SKU: ${it.sku}${it.category != null ? " • ${it.category}" : ""}',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color:
                                        theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${it.usedQty} ${it.unit ?? ""}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: Color(0xFF2563EB),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 6,
                          backgroundColor: theme.colorScheme.outlineVariant
                              .withValues(alpha: 0.3),
                          color: const Color(0xFF2563EB),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ShiftHistoryTab extends StatelessWidget {
  const _ShiftHistoryTab({required this.items});

  final List<ShiftHistoryItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Chưa có lịch sử chốt ca nào được ghi nhận.'),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF059669).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.history_rounded,
                        color: Color(0xFF059669), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lịch Sử Chốt Ca & Đối Soát Nhân Viên (SRS §3.5)',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Theo dõi trách nhiệm từng ca làm việc, tỷ lệ khớp và độ lệch kiểm đếm',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, idx) {
                  final it = items[idx];
                  final hasVariance = it.varianceLines > 0;

                  Color badgeColor = const Color(0xFF059669);
                  String statusText = 'Khớp hoàn toàn';
                  if (it.status == 'open') {
                    badgeColor = const Color(0xFF2563EB);
                    statusText = 'Đang kiểm đếm';
                  } else if (it.status == 'submitted') {
                    badgeColor = const Color(0xFFD97706);
                    statusText = 'Chờ duyệt';
                  } else if (hasVariance) {
                    badgeColor = const Color(0xFFDC2626);
                    statusText = 'Lệch ${it.varianceLines} mục';
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            hasVariance
                                ? Icons.warning_amber_rounded
                                : Icons.verified_outlined,
                            size: 20,
                            color: badgeColor,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    it.shiftName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color:
                                          badgeColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      statusText,
                                      style: TextStyle(
                                        color: badgeColor,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Nhân viên: ${it.maker} • Ngày: ${it.businessDate ?? "Hôm nay"} • Tổng mục: ${it.lineCount}${it.completedAt != null ? " • Hoàn tất: ${it.completedAt!.substring(11, 16)}" : ""}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color:
                                      theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Độ lệch: ${it.totalAbsVariance}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: hasVariance
                                    ? const Color(0xFFDC2626)
                                    : const Color(0xFF059669),
                              ),
                            ),
                            Text(
                              hasVariance ? 'Cần giải trình' : 'Chuẩn ca',
                              style: TextStyle(
                                fontSize: 10.5,
                                color:
                                    theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
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
    this.consumptionTop = const [],
    this.shiftHistory = const [],
  });

  final List<InventoryBucket> inventoryBuckets;
  final List<CashflowBucket> cashflowBuckets;
  final List<StagnationItem> stagnationItems;
  final List<ReconciliationRun> reconciliations;
  final List<ConsumptionTopItem> consumptionTop;
  final List<ShiftHistoryItem> shiftHistory;
}
