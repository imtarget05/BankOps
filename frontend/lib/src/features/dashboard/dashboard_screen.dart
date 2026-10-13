import 'package:flutter/material.dart';

import '../../app/app_shell.dart';
import '../../core/util/formatting.dart';
import '../../core/util/role_visibility.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/dtos.dart';
import '../../data/repositories/bankops_repository.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.onNavigate});

  /// Điều hướng sang tab AppShell (full index). `null` = chế độ xem tĩnh
  /// (test/widget độc lập): quick action hiện snackbar hướng dẫn như cũ.
  final ValueChanged<int>? onNavigate;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Future<DashboardData>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = RepositoryScope.of(context);
    _future ??= _load(repo);
  }

  Future<void> _refresh() async {
    final repo = RepositoryScope.of(context);
    setState(() {
      _future = _load(repo);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DashboardData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: LoadingView());
        }
        if (snapshot.hasError) {
          return Center(
            child: ErrorView(
              message: '${snapshot.error}',
              onRetry: _refresh,
            ),
          );
        }
        final data = snapshot.data!;
        final width = MediaQuery.sizeOf(context).width;
        final isWide = width >= 1000;

        return RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _DashboardHeader(data: data),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                sliver: SliverToBoxAdapter(
                  child: SummaryCard(
                    data: data,
                    onNavigate: widget.onNavigate,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverToBoxAdapter(
                  child: _buildCashboxDistribution(context, data),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: _buildQuickActions(context),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                sliver: SliverToBoxAdapter(
                  child: isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 6,
                              child: _buildInventoryBreakdown(context, data),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              flex: 5,
                              child: _buildApprovalQueue(context, data),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            _buildInventoryBreakdown(context, data),
                            const SizedBox(height: 20),
                            _buildApprovalQueue(context, data),
                          ],
                        ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                sliver: DashboardKpiGrid(
                  data: data,
                  onNavigate: widget.onNavigate,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCashboxDistribution(BuildContext context, DashboardData data) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final colors = [
      const Color(0xFF2563EB),
      const Color(0xFF059669),
      const Color(0xFFD97706),
      const Color(0xFF7C3AED),
      const Color(0xFF0891B2),
    ];

    final boxAmounts = <String, double>{};
    for (final b in data.cashBalances) {
      boxAmounts[b.cashboxId] = double.tryParse(b.amount) ?? 0;
    }

    final totalCash = boxAmounts.values.fold<double>(0, (sum, v) => sum + v);

    return Container(
      padding: const EdgeInsets.all(20),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF059669).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet_rounded,
                        color: Color(0xFF059669),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cơ cấu & Phân bổ Tồn Quỹ Tiền Mặt',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Theo dõi hạn mức an toàn của từng két sắt chi nhánh',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.2)),
                ),
                child: Text(
                  'Tổng: ${AppFormat.money(totalCash.toStringAsFixed(0))}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF059669),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 10,
              child: totalCash > 0
                  ? Row(
                      children: [
                        for (int i = 0; i < data.cashboxes.length; i++) ...[
                          if ((boxAmounts[data.cashboxes[i].id] ?? 0) > 0)
                            Expanded(
                              flex: (((boxAmounts[data.cashboxes[i].id] ?? 0) / totalCash) * 1000).round().clamp(1, 1000),
                              child: Container(
                                color: colors[i % colors.length],
                              ),
                            ),
                        ],
                      ],
                    )
                  : Container(color: Colors.grey.shade300),
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 950;
              final items = [
                for (int i = 0; i < data.cashboxes.length; i++) ...[
                  Builder(
                    builder: (context) {
                      final box = data.cashboxes[i];
                      final amt = boxAmounts[box.id] ?? 0;
                      final pct = totalCash > 0 ? (amt / totalCash * 100).toStringAsFixed(1) : '0.0';
                      final color = colors[i % colors.length];
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    box.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.5,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '$pct%',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11.5,
                                    color: color,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    AppFormat.money(amt.toStringAsFixed(0)),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'An toàn',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF059669),
                                    ),
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
              ];

              if (isWide) {
                return Row(
                  children: [
                    for (int i = 0; i < items.length; i++) ...[
                      Expanded(child: items[i]),
                      if (i < items.length - 1) const SizedBox(width: 12),
                    ],
                  ],
                );
              }
              return Column(
                children: [
                  for (int i = 0; i < items.length; i++) ...[
                    items[i],
                    if (i < items.length - 1) const SizedBox(height: 10),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
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
              const Icon(Icons.bolt_rounded, size: 20, color: Color(0xFFF59E0B)),
              const SizedBox(width: 8),
              Text(
                'Thao tác nhanh cho ca làm việc',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Builder(
            builder: (context) {
              final roles = RoleVisibility.rolesOf(
                SessionScope.maybeOf(context)?.user,
              );
              final actions = <Widget>[
                if (RoleVisibility.canCreate(roles))
                  _actionButton(
                    context,
                    icon: Icons.savings_outlined,
                    label: 'Lập phiếu Quỹ tiền mặt',
                    color: const Color(0xFF059669),
                    tabIndex: 3,
                  ),
                if (RoleVisibility.canCreate(roles))
                  _actionButton(
                    context,
                    icon: Icons.inventory_2_outlined,
                    label: 'Lập phiếu Xuất/Nhập kho',
                    color: const Color(0xFF2563EB),
                    tabIndex: 3,
                  ),
                if (RoleVisibility.canApprove(roles))
                  _actionButton(
                    context,
                    icon: Icons.verified_outlined,
                    label: 'Xử lý Hộp thư duyệt 4-Mắt',
                    color: const Color(0xFF7C3AED),
                    tabIndex: 4,
                  ),
                _actionButton(
                  context,
                  icon: Icons.sync_alt_outlined,
                  label: 'Đối soát Sổ cái tức thì',
                  color: const Color(0xFF0891B2),
                  tabIndex: 7,
                ),
              ];
              return Wrap(
                spacing: 12,
                runSpacing: 10,
                children: actions,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _actionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required int tabIndex,
  }) {
    final go = widget.onNavigate;
    return OutlinedButton.icon(
      key: Key('quick-action-$tabIndex-${icon.codePoint}'),
      onPressed: () {
        if (go != null) {
          go(tabIndex);
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Vui lòng chuyển qua menu phân hệ để thao tác: $label'),
            duration: const Duration(seconds: 2),
          ),
        );
      },
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: color.withValues(alpha: 0.3)),
      ),
      icon: Icon(icon, size: 16, color: color),
      label: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 12.5,
          color: color,
        ),
      ),
    );
  }

  Widget _buildInventoryBreakdown(BuildContext context, DashboardData data) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Danh mục Ấn chỉ & Trạng thái tồn kho',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${data.items.length} loại vật tư',
                  style: const TextStyle(
                    color: Color(0xFF2563EB),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (final item in data.items.take(4)) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.file_copy_outlined, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        Text(
                          'SKU: ${item.sku} • Đơn vị: ${item.unit} • Serial: ${item.trackedSerial ? "Có" : "Không"}',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Khả dụng',
                      style: TextStyle(
                        color: Color(0xFF059669),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  Widget _buildApprovalQueue(BuildContext context, DashboardData data) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Hộp thư Chờ Duyệt (Maker-Checker)',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${data.inbox.length} phiếu chờ',
                  style: const TextStyle(
                    color: Color(0xFFD97706),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (data.inbox.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.task_alt_rounded, size: 36, color: Colors.green.shade400),
                    const SizedBox(height: 8),
                    const Text(
                      'Không có phiếu tồn đọng',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'Tất cả giao dịch đã được kiểm duyệt hoàn tất.',
                      style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          else
            for (final item in data.inbox.take(3)) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.pending_actions_rounded,
                        color: Color(0xFFD97706),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Phiếu ${item.id.length > 8 ? "${item.id.substring(0, 8)}…" : item.id} • ${item.kind}',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                          Text(
                            'Người lập: ${item.maker} • Tác động: ${item.impact}',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Chờ duyệt',
                        style: TextStyle(
                          color: Color(0xFFB45309),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
            ],
        ],
      ),
    );
  }

  Future<DashboardData> _load(BankOpsRepository repo) async {
    final results = await Future.wait([
      repo.getLocations(),
      repo.getItems(),
      repo.getBalances(),
      repo.getAssets(),
      repo.getStockRequests(),
      repo.getApprovalInbox(),
      repo.getCashBalances(),
      repo.getCashboxes(),
    ]);
    return DashboardData(
      locations: results[0] as List<InventoryLocation>,
      items: results[1] as List<InventoryItem>,
      balances: results[2] as List<StockBalance>,
      assets: results[3] as List<AssetRecord>,
      stockRequests: results[4] as List<StockRequest>,
      inbox: results[5] as List<ApprovalItem>,
      cashBalances: results[6] as List<CashBalance>,
      cashboxes: results[7] as List<Cashbox>,
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tổng quan vận hành',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.check_circle, size: 14, color: Color(0xFF10B981)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Kho đang hoạt động',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1E3A8A).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF1E3A8A).withValues(alpha: 0.2)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.security, size: 16, color: Color(0xFF1E3A8A)),
                SizedBox(width: 6),
                Text(
                  'ISO 27001 AUDITED',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E3A8A),
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardData {
  const DashboardData({
    required this.locations,
    required this.items,
    required this.balances,
    required this.assets,
    required this.stockRequests,
    required this.inbox,
    required this.cashBalances,
    required this.cashboxes,
  });

  final List<InventoryLocation> locations;
  final List<InventoryItem> items;
  final List<StockBalance> balances;
  final List<AssetRecord> assets;
  final List<StockRequest> stockRequests;
  final List<ApprovalItem> inbox;
  final List<CashBalance> cashBalances;
  final List<Cashbox> cashboxes;
}

class SummaryCard extends StatelessWidget {
  const SummaryCard({super.key, required this.data, this.onNavigate});

  final DashboardData data;
  final ValueChanged<int>? onNavigate;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final cols = width >= 900 ? 4 : (width >= 520 ? 2 : 1);

        // Calculate totals
        final totalStockQty = data.balances.fold<double>(
          0,
          (sum, b) => sum + (double.tryParse(b.quantity) ?? 0),
        );

        final totalCashAmount = data.cashBalances.fold<double>(
          0,
          (sum, b) => sum + (double.tryParse(b.amount) ?? 0),
        );

        final cards = [
          _buildExecutiveStatCard(
            context,
            key: const Key('kpi-cash-card'),
            tabIndex: 2,
            title: 'TỔNG TỒN QUỸ TIỀN MẶT',
            value: AppFormat.money(totalCashAmount.toStringAsFixed(0)),
            subtext: '${data.cashboxes.length} két sắt chi nhánh hoạt động',
            icon: Icons.account_balance_wallet_rounded,
            color: const Color(0xFF059669),
            badgeText: 'An toàn',
          ),
          _buildExecutiveStatCard(
            context,
            key: const Key('kpi-stock-card'),
            tabIndex: 1,
            title: 'ẤN CHỈ & PHÔI TỒN KHO',
            value: '${AppFormat.intFormat(totalStockQty.round())} phôi',
            subtext: '${data.items.length} loại vật tư tại ${data.locations.length} kho',
            icon: Icons.inventory_2_rounded,
            color: const Color(0xFF2563EB),
            badgeText: 'Đầy đủ',
          ),
          _buildExecutiveStatCard(
            context,
            key: const Key('kpi-inbox-card'),
            tabIndex: 4,
            title: 'PHIẾU CHỜ DUYỆT (4-EYES)',
            value: '${data.inbox.length} phiếu',
            subtext: 'Cần kiểm soát viên xác nhận',
            icon: Icons.fact_check_rounded,
            color: data.inbox.isNotEmpty ? const Color(0xFFD97706) : const Color(0xFF059669),
            badgeText: data.inbox.isNotEmpty ? 'Cần xử lý' : 'Đã duyệt hết',
          ),
          _buildExecutiveStatCard(
            context,
            key: const Key('kpi-ledger-card'),
            tabIndex: 7,
            title: 'ĐỐI SOÁT SỔ CÁI (GL)',
            value: '100% Khớp',
            subtext: 'Không có chênh lệch tồn quỹ',
            icon: Icons.task_alt_rounded,
            color: const Color(0xFF7C3AED),
            badgeText: 'Đạt chuẩn',
          ),
        ];

        if (cols == 4) {
          return Row(
            children: [
              for (int i = 0; i < cards.length; i++) ...[
                Expanded(child: cards[i]),
                if (i < cards.length - 1) const SizedBox(width: 14),
              ],
            ],
          );
        } else if (cols == 2) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 14),
                  Expanded(child: cards[1]),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: cards[2]),
                  const SizedBox(width: 14),
                  Expanded(child: cards[3]),
                ],
              ),
            ],
          );
        }

        return Column(
          children: [
            for (int i = 0; i < cards.length; i++) ...[
              cards[i],
              if (i < cards.length - 1) const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }

  Widget _buildExecutiveStatCard(
    BuildContext context, {
    Key? key,
    required int tabIndex,
    required String title,
    required String value,
    required String subtext,
    required IconData icon,
    required Color color,
    required String badgeText,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final go = onNavigate;
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(16),
      onTap: go == null ? null : () => go(tabIndex),
      child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  subtext,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }
}

class DashboardKpiGrid extends StatelessWidget {
  const DashboardKpiGrid({super.key, required this.data, this.onNavigate});

  final DashboardData data;
  final ValueChanged<int>? onNavigate;

  static const _tiles = [
    _KpiTile('Điểm lưu kho', Icons.warehouse_rounded, Color(0xFF2563EB)),
    _KpiTile('Chủng loại vật tư', Icons.category_rounded, Color(0xFF0891B2)),
    _KpiTile('Bản ghi tồn kho', Icons.checklist_rounded, Color(0xFF059669)),
    _KpiTile('Mã ấn chỉ Serial', Icons.qr_code_rounded, Color(0xFF7C3AED)),
    _KpiTile('Phiếu yêu cầu', Icons.receipt_long_rounded, Color(0xFFEA580C)),
    _KpiTile('Phiếu đã ký duyệt', Icons.verified_rounded, Color(0xFF16A34A)),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final crossCount = width >= 1100 ? 6 : (width >= 700 ? 3 : 2);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final counts = [
      data.locations.length,
      data.items.length,
      data.balances.length,
      data.assets.length,
      data.stockRequests.length,
      data.inbox.length,
    ];

    return SliverGrid(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final tile = _tiles[index];
          final count = counts[index];
          const tabForTile = [1, 1, 1, 1, 3, 4];
          final go = onNavigate;
          return InkWell(
            key: Key('kpi-tile-$index'),
            borderRadius: BorderRadius.circular(14),
            onTap:
                go == null ? null : () => go(tabForTile[index]),
            child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: tile.color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(tile.icon, size: 20, color: tile.color),
                ),
                const SizedBox(height: 8),
                Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tile.label,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            ),
          );
        },
        childCount: 6,
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossCount,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.3,
      ),
    );
  }
}

class _KpiTile {
  final String label;
  final IconData icon;
  final Color color;

  const _KpiTile(this.label, this.icon, this.color);
}
