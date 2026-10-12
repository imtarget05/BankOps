import 'package:flutter/material.dart';

import '../../app/app_shell.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/dtos.dart';

/// Màn duyệt — approval inbox (Maker != Checker) chuẩn ngân hàng 4-Eyes Principle.
class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  Future<List<ApprovalItem>>? _future;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = RepositoryScope.of(context);
    _future ??= repo.getApprovalInbox();
  }

  void _reload() {
    final repo = RepositoryScope.of(context);
    setState(() {
      _future = repo.getApprovalInbox();
    });
  }

  bool _isCash(ApprovalItem item) =>
      item.kind.toLowerCase() == 'cash' ||
      item.kind.toLowerCase().contains('quỹ');

  Future<void> _approve(ApprovalItem item) async {
    final repo = RepositoryScope.of(context);
    setState(() => _busy = true);
    try {
      if (_isCash(item)) {
        await repo.approveCashRequest(item.id);
      } else {
        await repo.approveStockRequest(item.id);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('Đã duyệt & ghi sổ thành công phiếu ${item.id}')),
            ],
          ),
        ),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFB42318),
          behavior: SnackBarBehavior.floating,
          content: Text('Không thể duyệt: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject(ApprovalItem item) async {
    final repo = RepositoryScope.of(context);
    final reasonCtrl = TextEditingController(text: 'Chưa đủ chứng từ đối chiếu');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Từ chối phiếu ${item.id}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Vui lòng nhập lý do từ chối để thông báo lại cho Giao dịch viên (Maker):',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('reject-reason-input'),
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Lý do từ chối',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            key: const Key('reject-dialog-confirm-btn'),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Xác nhận từ chối'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final reason = reasonCtrl.text.trim().isEmpty
          ? 'Từ chối khi kiểm duyệt'
          : reasonCtrl.text.trim();
      if (_isCash(item)) {
        await repo.rejectCashRequest(item.id, reason);
      } else {
        await repo.rejectStockRequest(item.id, reason);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFD97706),
          behavior: SnackBarBehavior.floating,
          content: Text('Đã từ chối phiếu ${item.id}'),
        ),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFB42318),
          behavior: SnackBarBehavior.floating,
          content: Text('Không thể từ chối: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ApprovalItem>>(
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
        final items = snapshot.data!;
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hộp Thư Phê Duyệt 4 Mắt (Dual Control)',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Kiểm soát viên độc lập thẩm định chứng từ và quyết định phê duyệt ghi sổ',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.shield_outlined, size: 16, color: Color(0xFFD97706)),
                        const SizedBox(width: 6),
                        Text(
                          '${items.length} YÊU CẦU CHỜ DUYỆT',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFD97706),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Principle Banner
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E3A8A).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF1E3A8A).withValues(alpha: 0.2)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 20, color: Color(0xFF1E3A8A)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Nguyên tắc bất biến: Người lập lệnh (Maker) không được tự duyệt lệnh của chính mình. Mọi thao tác phê duyệt hoặc từ chối đều được lưu trữ vào vết kiểm toán.',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E3A8A),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              if (items.isEmpty)
                Container(
                  padding: const EdgeInsets.all(48),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_circle_rounded,
                            size: 40,
                            color: Color(0xFF10B981),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Hộp thư phê duyệt hoàn toàn trống',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tất cả các phiếu xuất/nhập kho và nạp/rút quỹ đã được kiểm soát xử lý xong.',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                for (final item in items)
                  Builder(
                    builder: (context) {
                      final isCash = _isCash(item);
                      final accentColor = isCash ? const Color(0xFF059669) : const Color(0xFF2563EB);

                      return Container(
                        key: Key('approval-card-${item.id}'),
                        margin: const EdgeInsets.only(bottom: 14),
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
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(color: accentColor, width: 4),
                              ),
                            ),
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: accentColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            isCash ? Icons.savings_outlined : Icons.inventory_2_outlined,
                                            size: 14,
                                            color: accentColor,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            isCash ? 'QUỸ TIỀN MẶT' : 'KHO ẤN CHỈ',
                                            style: TextStyle(
                                              color: accentColor,
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Mã phiếu: ${item.id}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: theme.colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'CHỜ CHECKER DUYỆT',
                                        style: TextStyle(
                                          color: Color(0xFFB45309),
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text.rich(
                                            TextSpan(
                                              children: [
                                                WidgetSpan(
                                                  alignment: PlaceholderAlignment.middle,
                                                  child: Padding(
                                                    padding: const EdgeInsets.only(right: 6),
                                                    child: Icon(
                                                      Icons.person_outline,
                                                      size: 16,
                                                      color: theme.colorScheme.onSurfaceVariant,
                                                    ),
                                                  ),
                                                ),
                                                TextSpan(
                                                  text: 'Người lập lệnh (Maker): ',
                                                  style: TextStyle(
                                                    fontSize: 12.5,
                                                    color: theme.colorScheme.onSurfaceVariant,
                                                  ),
                                                ),
                                                TextSpan(
                                                  text: item.maker,
                                                  style: const TextStyle(
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 6),
                                          Text.rich(
                                            TextSpan(
                                              children: [
                                                WidgetSpan(
                                                  alignment: PlaceholderAlignment.middle,
                                                  child: Padding(
                                                    padding: const EdgeInsets.only(right: 6),
                                                    child: Icon(
                                                      Icons.trending_up_rounded,
                                                      size: 16,
                                                      color: accentColor,
                                                    ),
                                                  ),
                                                ),
                                                TextSpan(
                                                  text: 'Tác động số dư: ',
                                                  style: TextStyle(
                                                    fontSize: 12.5,
                                                    color: theme.colorScheme.onSurfaceVariant,
                                                  ),
                                                ),
                                                TextSpan(
                                                  text: item.impact,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w900,
                                                    color: accentColor,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (item.detail.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              'Chi tiết: ${item.detail}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: theme.colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    Wrap(
                                      spacing: 8,
                                      children: [
                                        OutlinedButton.icon(
                                          key: Key('btn-reject-${item.id}'),
                                          onPressed: _busy ? null : () => _reject(item),
                                          icon: const Icon(Icons.close_rounded, size: 16, color: Color(0xFFDC2626)),
                                          label: const Text(
                                            'Từ chối',
                                            style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.w700),
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            side: const BorderSide(color: Color(0xFFFCA5A5)),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                          ),
                                        ),
                                        FilledButton.icon(
                                          key: Key('btn-approve-${item.id}'),
                                          onPressed: _busy ? null : () => _approve(item),
                                          icon: const Icon(Icons.verified_rounded, size: 16),
                                          label: const Text(
                                            'Phê duyệt & Ghi sổ',
                                            style: TextStyle(fontWeight: FontWeight.w700),
                                          ),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: const Color(0xFF059669),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
            ],
          ),
        );
      },
    );
  }
}
