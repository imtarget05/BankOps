import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/util/formatting.dart';
import '../../../data/models/dtos.dart';

/// Bộ thẻ chỉ số điều hành cốt lõi (Executive KPI Deck) hiển thị trên đầu tab Báo cáo.
class ExecutiveKpiDeck extends StatelessWidget {
  const ExecutiveKpiDeck({
    super.key,
    required this.cashflowBuckets,
    required this.inventoryBuckets,
    required this.stagnationItems,
    required this.reconciliations,
  });

  final List<CashflowBucket> cashflowBuckets;
  final List<InventoryBucket> inventoryBuckets;
  final List<StagnationItem> stagnationItems;
  final List<ReconciliationRun> reconciliations;

  @override
  Widget build(BuildContext context) {
    final statusColors = context.statusColors;

    // 1. Dòng tiền
    double totalIn = 0;
    double totalOut = 0;
    int totalJournals = 0;
    for (final b in cashflowBuckets) {
      totalIn += b.inValue;
      totalOut += b.outValue;
      totalJournals += b.journalCount;
    }
    final netCash = totalIn - totalOut;

    // 2. Kho
    double totalInbound = 0;
    double totalOutbound = 0;
    int totalReceipts = 0;
    int totalIssues = 0;
    for (final b in inventoryBuckets) {
      totalInbound += b.inboundValue;
      totalOutbound += b.outboundValue;
      totalReceipts += b.receiptCount;
      totalIssues += b.issueCount;
    }
    final netInventory = totalInbound - totalOutbound;

    // 3. Đối soát
    final totalRuns = reconciliations.length;
    final cleanRuns = reconciliations.where((r) => r.exceptions.isEmpty).length;
    final matchRate = totalRuns > 0 ? (cleanRuns / totalRuns * 100).toStringAsFixed(0) : '100';
    final hasExceptions = reconciliations.any((r) => r.exceptions.isNotEmpty);

    // 4. Tồn đọng
    final critical = stagnationItems.where((i) => i.severity == 'critical').length;
    final stagnant = stagnationItems.where((i) => i.severity == 'stagnant').length;
    final watch = stagnationItems.where((i) => i.severity == 'watch').length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        final cardWidth = isWide ? (constraints.maxWidth - 36) / 4 : (constraints.maxWidth - 12) / 2;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: cardWidth.clamp(220, 400),
              child: _KpiCard(
                key: const Key('kpi-cash-liquidity'),
                title: 'DÒNG TIỀN RÒNG (NET)',
                mainValue: '${netCash >= 0 ? '+' : ''}${_compactMoney(netCash)}',
                subtitle: 'Thu: ${_compactMoney(totalIn)} · Chi: ${_compactMoney(totalOut)}',
                badgeText: netCash >= 0 ? 'Thặng dư' : 'Thâm hụt',
                badgeColor: netCash >= 0 ? statusColors.success : statusColors.danger,
                icon: Icons.account_balance_wallet_outlined,
                iconColor: netCash >= 0 ? statusColors.success : statusColors.danger,
                tooltip: 'Tổng số bút toán: $totalJournals',
              ),
            ),
            SizedBox(
              width: cardWidth.clamp(220, 400),
              child: _KpiCard(
                key: const Key('kpi-inventory-movement'),
                title: 'LUÂN CHUYỂN KHO',
                mainValue: '${netInventory >= 0 ? '+' : ''}${AppFormat.quantity(netInventory.toStringAsFixed(0))}',
                subtitle: 'Nhập: ${AppFormat.quantity(totalInbound.toStringAsFixed(0))} · Xuất: ${AppFormat.quantity(totalOutbound.toStringAsFixed(0))}',
                badgeText: '${totalReceipts + totalIssues} phiếu',
                badgeColor: Theme.of(context).colorScheme.primary,
                icon: Icons.inventory_2_outlined,
                iconColor: Theme.of(context).colorScheme.primary,
                tooltip: 'Tổng nhập $totalReceipts phiếu, xuất $totalIssues phiếu',
              ),
            ),
            SizedBox(
              width: cardWidth.clamp(220, 400),
              child: _KpiCard(
                key: const Key('kpi-reconciliation-rate'),
                title: 'KHỚP LỆNH ĐỐI SOÁT',
                mainValue: '$matchRate%',
                subtitle: '$cleanRuns/$totalRuns phiên chuẩn · ${totalRuns - cleanRuns} ngoại lệ',
                badgeText: hasExceptions ? 'Cần rà soát' : 'Hoàn hảo',
                badgeColor: hasExceptions ? statusColors.warning : statusColors.success,
                icon: Icons.verified_user_outlined,
                iconColor: hasExceptions ? statusColors.warning : statusColors.success,
                tooltip: 'Đảm bảo tính toàn vẹn 4 mắt (Dual-control)',
              ),
            ),
            SizedBox(
              width: cardWidth.clamp(220, 400),
              child: _KpiCard(
                key: const Key('kpi-stagnation-risk'),
                title: 'ĐIỂM NÓNG TỒN ĐỌNG',
                mainValue: '$critical mặt hàng',
                subtitle: '>=60d: $stagnant · >=30d: $watch',
                badgeText: critical > 0 ? 'Nguy cơ >=90d' : 'An toàn',
                badgeColor: critical > 0 ? statusColors.danger : statusColors.success,
                icon: Icons.warning_amber_rounded,
                iconColor: critical > 0 ? statusColors.danger : statusColors.success,
                tooltip: 'Hàng không luân chuyển có nguy cơ lỗi thời',
              ),
            ),
          ],
        );
      },
    );
  }

  static String _compactMoney(double amount) {
    final abs = amount.abs();
    if (abs >= 1000000000) {
      return '${(amount / 1000000000).toStringAsFixed(2)} tỷ VND';
    }
    if (abs >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)} tr VND';
    }
    return AppFormat.money(amount.toStringAsFixed(0));
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    super.key,
    required this.title,
    required this.mainValue,
    required this.subtitle,
    required this.badgeText,
    required this.badgeColor,
    required this.icon,
    required this.iconColor,
    required this.tooltip,
  });

  final String title;
  final String mainValue;
  final String subtitle;
  final String badgeText;
  final Color badgeColor;
  final IconData icon;
  final Color iconColor;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: tooltip,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurfaceVariant,
                        letterSpacing: 0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 16, color: iconColor),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      mainValue,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      badgeText,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: badgeColor,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
