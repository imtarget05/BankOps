import 'package:flutter/material.dart';

import '../../app/app_shell.dart';
import '../../core/sync/data_sync_controller.dart';
import '../../core/util/formatting.dart';
import '../../core/util/role_visibility.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/dtos.dart';
import '../../data/repositories/bankops_repository.dart';
import 'dashboard_trust_metrics.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.onNavigate});

  /// Điều hướng sang tab AppShell (full index). `null` = chế độ xem tĩnh
  /// (test/widget độc lập): quick action hiện snackbar hướng dẫn như cũ.
  final ValueChanged<int>? onNavigate;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static DashboardData? _cachedData;
  Future<DashboardData>? _future;
  DataSyncController? _syncController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = RepositoryScope.of(context);
    final user = SessionScope.maybeOf(context)?.user;
    if (_cachedData != null) {
      _future = Future.value(_cachedData);
      _revalidateSilently(repo, user);
    } else {
      _future ??= _load(repo, user);
    }

    final sync = SyncScope.maybeOf(context);
    if (sync != _syncController) {
      _syncController?.removeListener(_onSyncUpdate);
      _syncController = sync;
      _syncController?.addListener(_onSyncUpdate);
    }
  }

  void _onSyncUpdate() {
    if (!mounted) return;
    final last = _syncController?.lastEvent;
    // Bỏ qua heartbeat_poll định kỳ để không làm giật/reset giao diện nếu không có sự kiện thay đổi
    if (last?.action == 'heartbeat_poll') {
      return;
    }
    if (last == null ||
        last.topic == SyncTopic.dashboard ||
        last.topic == SyncTopic.inventory ||
        last.topic == SyncTopic.stocktake ||
        last.topic == SyncTopic.approvals ||
        last.topic == SyncTopic.all) {
      _refresh();
    }
  }

  @override
  void dispose() {
    _syncController?.removeListener(_onSyncUpdate);
    super.dispose();
  }

  Future<void> _refresh() async {
    final repo = RepositoryScope.of(context);
    final user = SessionScope.maybeOf(context)?.user;
    setState(() {
      _future = _load(repo, user);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DashboardData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError && !snapshot.hasData) {
          return Center(
            child: ErrorView(
              message: '${snapshot.error}',
              onRetry: _refresh,
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: LoadingView());
        }
        final data = snapshot.data!;

        final width = MediaQuery.sizeOf(context).width;
        final isWide = width >= 1000;
        final user = SessionScope.maybeOf(context)?.user;
        final roles = RoleVisibility.rolesOf(user);
        final canApprove = RoleVisibility.canApprove(roles);

        return RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _DashboardHeader(data: data, canApprove: canApprove),
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
              if (data.lowStockAlerts.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  sliver: SliverToBoxAdapter(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color:
                                const Color(0xFFEF4444).withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              color: Color(0xFFDC2626), size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Cảnh báo vận hành: ${data.lowStockAlerts.length} nguyên liệu đang thấp hơn định mức an toàn',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: Color(0xFFDC2626)),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Cần lập phiếu nhập hoặc chuyển kho bổ sung để bảo đảm giao dịch quầy không bị gián đoạn.',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.tonal(
                            onPressed: () => widget.onNavigate?.call(1),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFDC2626)
                                  .withValues(alpha: 0.15),
                              foregroundColor: const Color(0xFFDC2626),
                              visualDensity: VisualDensity.compact,
                            ),
                            child: const Text('Xem Chi Tiết Kho',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ],
                      ),
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
                              child: canApprove
                                  ? _buildApprovalQueue(context, data)
                                  : _buildMakerRequestQueue(context, data),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            _buildInventoryBreakdown(context, data),
                            const SizedBox(height: 20),
                            canApprove
                                ? _buildApprovalQueue(context, data)
                                : _buildMakerRequestQueue(context, data),
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
    // Pilot trà sữa: ẩn card phân bổ quỹ khỏi dashboard quản lý.
    // Giữ nguyên hàm để dễ bật lại khi phục vụ module Cash.
    return const SizedBox.shrink();

    // ignore: dead_code
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
    final hasCashSource = data.cashboxes.isNotEmpty;

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
                            'Cơ cấu & phân bổ tồn nguyên liệu',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Tỷ trọng được tính từ số dư đã đồng bộ của từng két',
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: const Color(0xFF059669).withValues(alpha: 0.2)),
                ),
                child: Text(
                  hasCashSource
                      ? 'Tổng: ${AppFormat.money(totalCash.toStringAsFixed(0))}'
                      : 'Chưa có dữ liệu quỹ',
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
          if (!hasCashSource)
            const _DashboardEmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Chưa có két sắt hoặc số dư để phân bổ',
              message:
                  'Thanh tỷ trọng sẽ chỉ xuất hiện sau khi hệ thống nhận được dữ liệu quỹ.',
            )
          else ...[
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
                                flex:
                                    (((boxAmounts[data.cashboxes[i].id] ?? 0) /
                                                totalCash) *
                                            1000)
                                        .round()
                                        .clamp(1, 1000),
                                child:
                                    Container(color: colors[i % colors.length]),
                              ),
                          ],
                        ],
                      )
                    : Container(color: theme.colorScheme.outlineVariant),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              totalCash > 0
                  ? 'Tỷ trọng được tính từ số dư hiện có của từng két.'
                  : 'Đã nhận dữ liệu ${data.cashboxes.length} két, nhưng chưa phát sinh số dư.',
              style: TextStyle(
                  fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
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
                        final hasBalance = data.cashBalances.any(
                          (balance) => balance.cashboxId == box.id,
                        );
                        final pct = totalCash > 0
                            ? (amt / totalCash * 100).toStringAsFixed(1)
                            : '0.0';
                        final color = colors[i % colors.length];
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF0F172A)
                                : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.4),
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
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: (hasBalance
                                              ? const Color(0xFF10B981)
                                              : const Color(0xFFD97706))
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      hasBalance
                                          ? 'Đã nhận số dư'
                                          : 'Chưa có số dư',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: hasBalance
                                            ? const Color(0xFF059669)
                                            : const Color(0xFFB45309),
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
              const Icon(Icons.bolt_rounded,
                  size: 20, color: Color(0xFFF59E0B)),
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
                    label: 'Lập phiếu nhập nguyên liệu',
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
                    label: 'Phê duyệt Kiểm Soát Kép',
                    color: const Color(0xFF7C3AED),
                    tabIndex: 4,
                  )
                else
                  _actionButton(
                    context,
                    icon: Icons.fact_check_outlined,
                    label: 'Theo dõi Yêu cầu của tôi',
                    color: const Color(0xFFD97706),
                    tabIndex: 3,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
            content:
                Text('Vui lòng chuyển qua menu phân hệ để thao tác: $label'),
            duration: const Duration(seconds: 2),
          ),
        );
      },
      style: OutlinedButton.styleFrom(
        backgroundColor: color.withValues(alpha: isDark ? 0.12 : 0.05),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: color.withValues(alpha: 0.3)),
      ),
      icon: Icon(icon, size: 17, color: color),
      label: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w700,
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
                  'Danh mục nguyên liệu & trạng thái tồn kho',
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
            InkWell(
              onTap: () => widget.onNavigate?.call(1),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
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
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
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
                    Icon(Icons.task_alt_rounded,
                        size: 36, color: Colors.green.shade400),
                    const SizedBox(height: 8),
                    const Text(
                      'Không có phiếu tồn đọng',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'Tất cả giao dịch đã được kiểm duyệt hoàn tất.',
                      style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          else
            for (final item in data.inbox.take(3)) ...[
              InkWell(
                onTap: () => widget.onNavigate?.call(4),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
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
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 13),
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFFF59E0B).withValues(alpha: 0.15),
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
              ),
              const Divider(height: 1),
            ],
        ],
      ),
    );
  }

  Widget _buildMakerRequestQueue(BuildContext context, DashboardData data) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final myPending = data.stockRequests
        .where((r) => r.status == RequestStatus.pending)
        .toList();

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
                  'Yêu Cầu Của Bạn Đang Chờ Phê Duyệt',
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
                  color: (myPending.isNotEmpty
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFF10B981))
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${myPending.length} phiếu chờ duyệt',
                  style: TextStyle(
                    color: myPending.isNotEmpty
                        ? const Color(0xFFD97706)
                        : const Color(0xFF059669),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (myPending.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.task_alt_rounded,
                        size: 36, color: Colors.green.shade400),
                    const SizedBox(height: 8),
                    const Text(
                      'Tất cả yêu cầu đã được xử lý',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Hiện không có phiếu nào đang chờ kiểm soát viên phê duyệt.',
                      style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: () => widget.onNavigate?.call(3),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Lập Yêu Cầu Mới',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold)),
                      style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            for (final item in myPending.take(3)) ...[
              InkWell(
                onTap: () => widget.onNavigate?.call(3),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.assignment_turned_in_rounded,
                          color: Color(0xFF2563EB),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Phiếu ${item.id.length > 8 ? "${item.id.substring(0, 8)}…" : item.id} • ${item.kind.name.toUpperCase()}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                            Text(
                              item.reason.trim().isNotEmpty
                                  ? 'Lý do: ${item.reason}'
                                  : 'Số dòng: ${item.items.length} mặt hàng',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFFF59E0B).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Chờ KSV duyệt',
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
              ),
              const Divider(height: 1),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => widget.onNavigate?.call(3),
                icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                label: const Text('Xem tất cả yêu cầu của tôi',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<DashboardData> _load(BankOpsRepository repo, AppUser? user) async {
    final roles = RoleVisibility.rolesOf(user);
    final canApprove = RoleVisibility.canApprove(roles);

    final summaryDto = await repo.getDashboardSummary(canApprove: canApprove);
    final data = DashboardData.fromDto(summaryDto);
    _cachedData = data;
    return data;
  }

  Future<void> _revalidateSilently(BankOpsRepository repo, AppUser? user) async {
    try {
      final roles = RoleVisibility.rolesOf(user);
      final canApprove = RoleVisibility.canApprove(roles);
      final summaryDto = await repo.getDashboardSummary(canApprove: canApprove);
      final data = DashboardData.fromDto(summaryDto);
      _cachedData = data;
      if (mounted) {
        setState(() {
          _future = Future.value(data);
        });
      }
    } catch (_) {
      // Background revalidation silently ignored; cached data remains visible
    }
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.data, this.canApprove = true});

  final DashboardData data;
  final bool canApprove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final screenWidth = MediaQuery.sizeOf(context).width;
    final isVeryNarrow = screenWidth < 420;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(isVeryNarrow ? 16 : 24, 20, isVeryNarrow ? 16 : 24, 16),
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
                  canApprove
                      ? 'Tổng quan vận hành'
                      : 'Bàn vận hành Giao dịch viên',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.check_circle,
                        size: 14, color: Color(0xFF10B981)),
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: (canApprove
                      ? const Color(0xFF1E3A8A)
                      : const Color(0xFF059669))
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: (canApprove
                          ? const Color(0xFF1E3A8A)
                          : const Color(0xFF059669))
                      .withValues(alpha: 0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(canApprove ? Icons.security : Icons.account_balance,
                    size: 16,
                    color: canApprove
                        ? const Color(0xFF1E3A8A)
                        : const Color(0xFF059669)),
                if (!isVeryNarrow) ...[
                  const SizedBox(width: 6),
                  Text(
                    canApprove
                        ? (screenWidth < 680
                            ? 'KIỂM SOÁT KÉP'
                            : 'KIỂM SOÁT KÉP (MAKER–CHECKER)')
                        : (screenWidth < 680
                            ? 'GIAO DỊCH VIÊN'
                            : 'QUẦY GIAO DỊCH VIÊN'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: canApprove
                          ? const Color(0xFF1E3A8A)
                          : const Color(0xFF059669),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
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
    required this.lowStockAlerts,
    required this.reconciliations,
  });

  factory DashboardData.fromDto(DashboardSummaryDto dto) {
    return DashboardData(
      locations: dto.locations,
      items: dto.items,
      balances: dto.balances,
      assets: dto.assets,
      stockRequests: dto.stockRequests,
      inbox: dto.inbox,
      cashBalances: dto.cashBalances,
      cashboxes: dto.cashboxes,
      lowStockAlerts: dto.lowStockAlerts,
      reconciliations: dto.reconciliations,
    );
  }

  final List<InventoryLocation> locations;
  final List<InventoryItem> items;
  final List<StockBalance> balances;
  final List<AssetRecord> assets;
  final List<StockRequest> stockRequests;
  final List<ApprovalItem> inbox;
  final List<CashBalance> cashBalances;
  final List<Cashbox> cashboxes;
  final List<LowStockAlertItem> lowStockAlerts;
  final List<ReconciliationRun> reconciliations;

  DashboardTrustMetrics get trustMetrics => DashboardTrustMetrics.fromData(
        cashboxes: cashboxes,
        cashBalances: cashBalances,
        locations: locations,
        items: items,
        balances: balances,
        reconciliations: reconciliations,
      );
}

class SummaryCard extends StatelessWidget {
  const SummaryCard({super.key, required this.data, this.onNavigate});

  final DashboardData data;
  final ValueChanged<int>? onNavigate;

  @override
  Widget build(BuildContext context) {
    final roles = RoleVisibility.rolesOf(SessionScope.maybeOf(context)?.user);
    final canApprove = RoleVisibility.canApprove(roles);
    final pendingMyCount = data.stockRequests
        .where((r) => r.status == RequestStatus.pending)
        .length;
    final trust = data.trustMetrics;

    Color stateColor(DashboardDataTone tone, Color fallback) => switch (tone) {
          DashboardDataTone.good => const Color(0xFF059669),
          DashboardDataTone.warning => const Color(0xFFD97706),
          DashboardDataTone.neutral => fallback,
        };

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
            title: 'TỔNG TỒN NGUYÊN LIỆU',
            value: data.cashboxes.isEmpty
                ? '—'
                : AppFormat.money(totalCashAmount.toStringAsFixed(0)),
            subtext: data.cashboxes.isEmpty
                ? 'Chưa cấu hình két sắt hoặc nhận số dư'
                : '${data.cashboxes.length} két • ${data.cashBalances.length} số dư nhận được',
            icon: Icons.account_balance_wallet_rounded,
            color: stateColor(trust.cashState.tone, const Color(0xFF059669)),
            badgeText: trust.cashState.label,
            trendText: trust.cashCoverage == null
                ? 'Không hiển thị tiến độ khi chưa có nguồn dữ liệu'
                : '${(trust.cashCoverage! * 100).round()}% két có số dư đối chiếu',
            progressRatio: trust.cashCoverage,
          ),
          _buildExecutiveStatCard(
            context,
            key: const Key('kpi-stock-card'),
            tabIndex: 1,
            title: 'NGUYÊN LIỆU TỒN KHO',
            value: data.items.isEmpty || data.locations.isEmpty
                ? '—'
                : '${AppFormat.intFormat(totalStockQty.round())} phôi',
            subtext: data.lowStockAlerts.isNotEmpty
                ? '⚠️ ${data.lowStockAlerts.length} mặt hàng dưới định mức'
                : '${data.items.length} loại vật tư tại ${data.locations.length} kho',
            icon: Icons.inventory_2_rounded,
            color: data.lowStockAlerts.isNotEmpty
                ? const Color(0xFFDC2626)
                : stateColor(trust.stockState.tone, const Color(0xFF2563EB)),
            badgeText: data.lowStockAlerts.isNotEmpty
                ? 'Thiếu hàng'
                : trust.stockState.label,
            trendText: data.lowStockAlerts.isNotEmpty
                ? '${data.lowStockAlerts.length} mặt hàng dưới định mức'
                : trust.stockCoverage == null
                    ? 'Không hiển thị tiến độ khi chưa có danh mục/kho'
                    : '${(trust.stockCoverage! * 100).round()}% tổ hợp kho–vật tư có bản ghi',
            progressRatio: trust.stockCoverage,
          ),
          canApprove
              ? _buildExecutiveStatCard(
                  context,
                  key: const Key('kpi-inbox-card'),
                  tabIndex: 4,
                  title: 'HÀNG ĐỢI PHÊ DUYỆT (KIỂM SOÁT KÉP)',
                  value: '${data.inbox.length} phiếu',
                  subtext: 'Cần kiểm soát viên xác nhận',
                  icon: Icons.fact_check_rounded,
                  color: data.inbox.isNotEmpty
                      ? const Color(0xFFD97706)
                      : const Color(0xFF059669),
                  badgeText:
                      data.inbox.isNotEmpty ? 'Cần xử lý' : 'Đã duyệt hết',
                  trendText: data.inbox.isNotEmpty
                      ? '${data.inbox.length} chờ'
                      : '0 tồn',
                  progressRatio: data.inbox.isNotEmpty ? 0.45 : 1.0,
                )
              : _buildExecutiveStatCard(
                  context,
                  key: const Key('kpi-inbox-card'),
                  tabIndex: 3,
                  title: 'YÊU CẦU ĐANG CHỜ DUYỆT',
                  value: '$pendingMyCount phiếu',
                  subtext: 'Đã gửi Kiểm soát viên chờ duyệt',
                  icon: Icons.pending_actions_rounded,
                  color: pendingMyCount > 0
                      ? const Color(0xFFD97706)
                      : const Color(0xFF059669),
                  badgeText: pendingMyCount > 0 ? 'Đang duyệt' : 'Hoàn tất',
                  trendText:
                      pendingMyCount > 0 ? '$pendingMyCount chờ' : '0 tồn',
                  progressRatio: pendingMyCount > 0 ? 0.45 : 1.0,
                ),
          _buildExecutiveStatCard(
            context,
            key: const Key('kpi-ledger-card'),
            tabIndex: 7,
            title: 'ĐỐI SOÁT SỔ CÁI (GL)',
            value: trust.ledgerState.tone == DashboardDataTone.good
                ? 'Đã khớp'
                : '—',
            subtext: data.reconciliations.isEmpty
                ? 'Chưa có phiên đối soát để xác nhận số liệu'
                : trust.ledgerState.tone == DashboardDataTone.warning
                    ? 'Phát hiện ngoại lệ; cần kiểm tra trước khi xác nhận'
                    : 'Kết quả lấy từ phiên đối soát gần nhất',
            icon: Icons.task_alt_rounded,
            color: stateColor(trust.ledgerState.tone, const Color(0xFF7C3AED)),
            badgeText: trust.ledgerState.label,
            trendText: data.reconciliations.isEmpty
                ? 'Chưa có căn cứ tính tỷ lệ khớp'
                : 'Xem chi tiết phiên đối soát',
            progressRatio:
                trust.ledgerState.tone == DashboardDataTone.good ? 1 : null,
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
    String? trendText,
    double? progressRatio,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
            const SizedBox(height: 12),
            if (progressRatio != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progressRatio,
                  backgroundColor: color.withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: 3.5,
                ),
              )
            else
              Container(
                height: 3.5,
                decoration: BoxDecoration(
                  color:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DashboardEmptyState extends StatelessWidget {
  const _DashboardEmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('dashboard-empty-cash-distribution'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: TextStyle(
                      fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardKpiGrid extends StatelessWidget {
  const DashboardKpiGrid({super.key, required this.data, this.onNavigate});

  final DashboardData data;
  final ValueChanged<int>? onNavigate;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final crossCount = width >= 1100 ? 6 : (width >= 700 ? 3 : 2);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final roles = RoleVisibility.rolesOf(SessionScope.maybeOf(context)?.user);
    final canApprove = RoleVisibility.canApprove(roles);
    final approvedCount = data.stockRequests
        .where((r) => r.status == RequestStatus.approved)
        .length;

    final counts = [
      data.locations.length,
      data.items.length,
      data.balances.length,
      data.assets.length,
      data.stockRequests.length,
      canApprove ? data.inbox.length : approvedCount,
    ];

    final tiles = [
      const _KpiTile(
          'Điểm lưu kho', Icons.warehouse_rounded, Color(0xFF2563EB)),
      const _KpiTile(
          'Chủng loại vật tư', Icons.category_rounded, Color(0xFF0891B2)),
      const _KpiTile(
          'Bản ghi tồn kho', Icons.checklist_rounded, Color(0xFF059669)),
      const _KpiTile(
          'Mã nguyên liệu', Icons.qr_code_rounded, Color(0xFF7C3AED)),
      const _KpiTile(
          'Phiếu yêu cầu', Icons.receipt_long_rounded, Color(0xFFEA580C)),
      canApprove
          ? const _KpiTile(
              'Hàng đợi duyệt', Icons.verified_rounded, Color(0xFF16A34A))
          : const _KpiTile(
              'Phiếu đã duyệt', Icons.verified_rounded, Color(0xFF16A34A)),
    ];

    final tabForTile = [1, 1, 1, 1, 3, canApprove ? 4 : 3];

    return SliverGrid(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final tile = tiles[index];
          final count = counts[index];
          final go = onNavigate;
          return InkWell(
            key: Key('kpi-tile-$index'),
            borderRadius: BorderRadius.circular(14),
            onTap: go == null ? null : () => go(tabForTile[index]),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
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
