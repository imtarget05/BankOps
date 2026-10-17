import 'package:flutter/material.dart';

import '../../app/app_shell.dart';
import '../../core/util/formatting.dart';
import '../../core/util/error_text.dart';
import '../../core/util/role_visibility.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/dtos.dart';
import '../../data/repositories/bankops_repository.dart';

/// Màn quản lý quỹ tiền mặt chuẩn ngân hàng:
/// Hiển thị chi tiết từng két sắt (Vaults), số dư thực tế, số dư đầu ngày, và sổ nhật ký giao dịch (Journals).
class CashScreen extends StatefulWidget {
  const CashScreen({
    super.key,
    this.onNavigate,
    this.onCreateCashRequest,
  });

  final ValueChanged<int>? onNavigate;
  final VoidCallback? onCreateCashRequest;

  @override
  State<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends State<CashScreen> {
  Future<_CashData>? _future;
  String? _selectedCashboxId;
  bool _showAllJournals = false;

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

  Future<void> _showCreateCashboxDialog() async {
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final balanceCtrl = TextEditingController(text: '0');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.savings_rounded, color: Color(0xFF059669)),
            SizedBox(width: 8),
            Text('Thêm Két Sắt Mới', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codeCtrl,
              decoration: const InputDecoration(
                labelText: 'Mã Két Quầy / Ngăn Kéo *',
                hintText: 'Ví dụ: POS-01',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Tên Két Quầy / Ngăn Kéo *',
                hintText: 'Ví dụ: Két Quầy Thu Ngân 1',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: balanceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Số Dư Ban Đầu (VND)',
                hintText: '0',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Hủy')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF059669)),
            onPressed: () {
              if (codeCtrl.text.trim().isEmpty || nameCtrl.text.trim().isEmpty) return;
              Navigator.of(ctx).pop(true);
            },
            child: const Text('Thêm két'),
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      try {
        final repo = RepositoryScope.of(context);
        await repo.createCashbox(
          code: codeCtrl.text.trim(),
          name: nameCtrl.text.trim(),
          openingBalance: balanceCtrl.text.trim().isEmpty ? '0.00' : balanceCtrl.text.trim(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Đã thêm két sắt "${nameCtrl.text.trim()}"!'), behavior: SnackBarBehavior.floating),
          );
          _refresh();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi: ${friendlyError(e)}'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _showCashboxDetailSheet({
    required Cashbox box,
    required double currentAmount,
    required List<JournalEntry> journals,
    required bool isAdmin,
  }) async {
    final relatedJournals = journals.where((j) =>
      j.cashboxId == box.id ||
      j.reason.toLowerCase().contains(box.code.toLowerCase()) ||
      j.reason.toLowerCase().contains(box.name.toLowerCase())
    ).toList();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final isDark = theme.brightness == Brightness.dark;
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollCtrl) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: ListView(
                controller: scrollCtrl,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF059669).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.savings_rounded, color: Color(0xFF059669), size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              box.name,
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            Text(
                              'Mã két: ${box.code} • Đang hoạt động',
                              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      if (isAdmin)
                        FilledButton.tonalIcon(
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: const Text('Chỉnh sửa'),
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _showEditCashboxDialog(box, currentAmount);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'SỐ DƯ THỰC TẾ HIỆN TẠI',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              AppFormat.money(currentAmount.toStringAsFixed(0)),
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF059669)),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'SỐ DƯ BAN ĐẦU',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              AppFormat.money(box.openingBalance),
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: theme.colorScheme.onSurface),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Lịch Sử Bút Toán Phát Sinh (${relatedJournals.length})',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (relatedJournals.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Chưa có bút toán nào phát sinh cho két này.',
                        style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                      ),
                    )
                  else
                    ...relatedJournals.take(10).map((j) {
                      final isDeposit = j.kind.toLowerCase() == 'deposit' || j.kind.toLowerCase() == 'in';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isDeposit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                              color: isDeposit ? const Color(0xFF059669) : const Color(0xFFDC2626),
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    j.reason.isEmpty ? 'Giao dịch két quỹ' : j.reason,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    AppFormat.dateTime(j.createdAt),
                                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${isDeposit ? '+' : '-'}${AppFormat.money(j.amount, currency: j.currency)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: isDeposit ? const Color(0xFF059669) : const Color(0xFFDC2626),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showEditCashboxDialog(Cashbox box, [double? currentAmount]) async {
    final nameCtrl = TextEditingController(text: box.name);
    final initialBal = currentAmount != null ? currentAmount.toStringAsFixed(0) : box.openingBalance;
    final balanceCtrl = TextEditingController(text: initialBal);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.edit_outlined, color: Color(0xFF059669)),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Chỉnh Sửa Két: ${box.code}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Tên Két Sắt *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: balanceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Điều Chỉnh Số Dư Quỹ (VND) *',
                helperText: 'Dành cho Quản lý / Admin cập nhật tiền quỹ',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Hủy')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF059669)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Lưu thay đổi'),
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      try {
        final repo = RepositoryScope.of(context);
        await repo.updateCashbox(
          id: box.id,
          name: nameCtrl.text.trim(),
          balance: balanceCtrl.text.trim().isEmpty ? '0' : balanceCtrl.text.trim(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã cập nhật thông tin két sắt thành công!'), behavior: SnackBarBehavior.floating),
          );
          _refresh();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi: ${friendlyError(e)}'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _confirmDeleteCashbox(Cashbox box) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Xác nhận đóng két sắt', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text('Bạn có chắc chắn muốn xóa két sắt "${box.name}" (${box.code}) khỏi hệ thống?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Hủy')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Đóng & Xóa'),
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      try {
        final repo = RepositoryScope.of(context);
        await repo.deleteCashbox(box.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Đã xóa két sắt "${box.name}"!'), behavior: SnackBarBehavior.floating),
          );
          _refresh();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi: ${friendlyError(e)}'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_CashData>(
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
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;

        // Calculate total amount across all cashboxes
        final totalCash = data.balances.fold<double>(
          0,
          (sum, b) => sum + (double.tryParse(b.amount) ?? 0),
        );

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Header Panel
              LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 780;
                  final titleWidget = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quản Lý Quỹ Tiền Mặt & Két Sắt',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Kiểm soát hạn mức tồn quỹ chi nhánh, tiền mặt tại quầy và nhật ký bút toán',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  );

                  final buttonsWidget = Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        key: const Key('btn-add-cashbox'),
                        onPressed: () => _showCreateCashboxDialog(),
                        icon: const Icon(Icons.add_box_outlined, size: 18),
                        label: const Text('Thêm két sắt mới'),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      FilledButton.icon(
                        key: const Key('btn-create-cash-request'),
                        onPressed: () {
                          if (widget.onCreateCashRequest != null) {
                            widget.onCreateCashRequest!();
                          } else if (widget.onNavigate != null) {
                            widget.onNavigate!(3);
                          }
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Lập phiếu quỹ mới'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  );

                  if (isCompact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        titleWidget,
                        const SizedBox(height: 12),
                        buttonsWidget,
                      ],
                    );
                  }

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: titleWidget),
                      const SizedBox(width: 16),
                      buttonsWidget,
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),

              // Metric Overview Strip
              LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 780;
                  final box1 = _buildMetricBox(
                    context,
                    title: 'TỔNG TỒN QUỸ KHẢ DỤNG',
                    value: AppFormat.money(totalCash.toStringAsFixed(0)),
                    subtitle: 'Đã khóa sổ ca giao dịch gần nhất',
                    icon: Icons.account_balance_wallet_rounded,
                    color: const Color(0xFF059669),
                  );
                  final box2 = _buildMetricBox(
                    context,
                    title: 'SỐ LƯỢNG KÉT QUỸ CHI NHÁNH',
                    value: '${data.cashboxes.length} két sắt',
                    subtitle: '100% két đang sẵn sàng hoạt động',
                    icon: Icons.lock_clock_rounded,
                    color: const Color(0xFF2563EB),
                  );
                  final box3 = _buildMetricBox(
                    context,
                    title: 'BÚT TOÁN ĐÃ GHI SỔ',
                    value: '${data.journals.length} giao dịch',
                    subtitle: 'Đã đối chiếu sổ cái (GL) khớp 100%',
                    icon: Icons.receipt_long_rounded,
                    color: const Color(0xFF7C3AED),
                  );

                  if (isCompact) {
                    return Column(
                      children: [
                        box1,
                        const SizedBox(height: 10),
                        box2,
                        const SizedBox(height: 10),
                        box3,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: box1),
                      const SizedBox(width: 14),
                      Expanded(child: box2),
                      const SizedBox(width: 14),
                      Expanded(child: box3),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),

              // Section: Két sắt & Số dư
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Danh Sách Két Sắt & Số Dư Vật Lý',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Nhấn vào từng két để xem sổ bút toán & điều chỉnh số dư bên dưới',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final box in data.cashboxes) ...[
                Builder(
                  builder: (context) {
                    final balance = data.balances.cast<CashBalance?>().firstWhere(
                          (b) => b?.cashboxId == box.id,
                          orElse: () => null,
                        );
                    final currentAmountStr = balance?.amount ?? box.openingBalance;
                    final currentAmount = double.tryParse(currentAmountStr) ?? 0.0;
                    final currency = balance?.currency ?? 'VND';
                    final user = SessionScope.maybeOf(context)?.user;
                    final roles = RoleVisibility.rolesOf(user);
                    final isAdmin = RoleVisibility.isAdmin(roles);
                    final effectiveSelectedId = _selectedCashboxId ??
                        (data.cashboxes.isNotEmpty ? data.cashboxes.first.id : null);
                    final isSelected = box.id == effectiveSelectedId;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? (isDark
                                ? const Color(0xFF0F2E23)
                                : const Color(0xFFF0FDF4))
                            : (isDark ? const Color(0xFF1E293B) : Colors.white),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF059669)
                              : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                          width: isSelected ? 2 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            setState(() => _selectedCashboxId = box.id);
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Hàng 1: Mã két, Tên két, Trạng thái, Menu
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? const Color(0xFF059669).withValues(alpha: 0.2)
                                            : const Color(0xFF1E3A8A).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        box.code,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12,
                                          color: isSelected
                                              ? const Color(0xFF059669)
                                              : const Color(0xFF1E3A8A),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        box.name,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                          color: isSelected
                                              ? const Color(0xFF059669)
                                              : null,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'ĐANG MỞ',
                                        style: TextStyle(
                                          color: Color(0xFF059669),
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    if (isAdmin) ...[
                                      const SizedBox(width: 4),
                                      PopupMenuButton<String>(
                                        icon: const Icon(Icons.more_vert, size: 18),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        itemBuilder: (ctx) => [
                                          const PopupMenuItem(
                                            value: 'detail',
                                            child: Row(
                                              children: [
                                                Icon(Icons.info_outline_rounded, size: 16),
                                                SizedBox(width: 8),
                                                Text('Xem chi tiết dạng sheet'),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: 'edit',
                                            child: Row(
                                              children: [
                                                Icon(Icons.edit_outlined, size: 16),
                                                SizedBox(width: 8),
                                                Text('Điều chỉnh số dư (Admin)'),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: 'delete',
                                            child: Row(
                                              children: [
                                                Icon(Icons.delete_outline, size: 16, color: Colors.red),
                                                SizedBox(width: 8),
                                                Text('Đóng & Xóa két', style: TextStyle(color: Colors.red)),
                                              ],
                                            ),
                                          ),
                                        ],
                                        onSelected: (v) {
                                          if (v == 'detail') {
                                            _showCashboxDetailSheet(
                                              box: box,
                                              currentAmount: currentAmount,
                                              journals: data.journals,
                                              isAdmin: isAdmin,
                                            );
                                          }
                                          if (v == 'edit') _showEditCashboxDialog(box, currentAmount);
                                          if (v == 'delete') _confirmDeleteCashbox(box);
                                        },
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 12),
                                // Hàng 2: Số dư ban đầu bên trái, Số dư thực tế bên phải (cân đối, không bị chèn ép)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Số dư ban đầu',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: theme.colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          AppFormat.money(box.openingBalance, currency: currency),
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          'SỐ DƯ THỰC TẾ',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.5,
                                            color: theme.colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          AppFormat.money(currentAmountStr, currency: currency),
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w900,
                                            color: Color(0xFF059669),
                                            letterSpacing: -0.5,
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
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 16),

              // KHUNG CHI TIẾT KÉT ĐANG CHỌN & NÚT ADMIN ĐIỀU CHỈNH SỐ DƯ (Hiển thị ngay bên dưới)
              Builder(
                builder: (context) {
                  final effectiveSelectedId = _selectedCashboxId ??
                      (data.cashboxes.isNotEmpty ? data.cashboxes.first.id : null);
                  final selectedBox = data.cashboxes.cast<Cashbox?>().firstWhere(
                        (b) => b?.id == effectiveSelectedId,
                        orElse: () => data.cashboxes.isNotEmpty ? data.cashboxes.first : null,
                      );
                  final user = SessionScope.maybeOf(context)?.user;
                  final roles = RoleVisibility.rolesOf(user);
                  final isAdmin = RoleVisibility.isAdmin(roles);

                  if (selectedBox == null) return const SizedBox.shrink();

                  final balance = data.balances.cast<CashBalance?>().firstWhere(
                        (b) => b?.cashboxId == selectedBox.id,
                        orElse: () => null,
                      );
                  final currentAmountStr = balance?.amount ?? selectedBox.openingBalance;
                  final currentAmount = double.tryParse(currentAmountStr) ?? 0.0;
                  final currency = balance?.currency ?? 'VND';

                  final boxJournals = data.journals.where((j) =>
                      j.cashboxId == selectedBox.id ||
                      j.reason.toLowerCase().contains(selectedBox.code.toLowerCase()) ||
                      j.reason.toLowerCase().contains(selectedBox.name.toLowerCase())).toList();

                  final displayedJournals = _showAllJournals ? data.journals : boxJournals;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header chi tiết của két đang chọn
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF059669).withValues(alpha: 0.35),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.tune_rounded, color: Color(0xFF059669), size: 18),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              'Két Đang Chọn: ${selectedBox.name}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 14,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Mã két: ${selectedBox.code} • Số dư thực tế: ${AppFormat.money(currentAmountStr, currency: currency)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isAdmin) ...[
                                  const SizedBox(width: 8),
                                  FilledButton.icon(
                                    key: const Key('btn-admin-adjust-cashbox'),
                                    icon: const Icon(Icons.edit_note_rounded, size: 16),
                                    label: const Text('Điều chỉnh số dư'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF059669),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: () => _showEditCashboxDialog(selectedBox, currentAmount),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 12),
                            // Filter toggle: Chỉ két này vs Toàn bộ
                            Row(
                              children: [
                                ChoiceChip(
                                  label: Text('Bút toán két này (${boxJournals.length})'),
                                  selected: !_showAllJournals,
                                  onSelected: (val) {
                                    if (val) setState(() => _showAllJournals = false);
                                  },
                                ),
                                const SizedBox(width: 8),
                                ChoiceChip(
                                  label: Text('Tất cả bút toán (${data.journals.length})'),
                                  selected: _showAllJournals,
                                  onSelected: (val) {
                                    if (val) setState(() => _showAllJournals = true);
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Sổ nhật ký giao dịch hiển thị bên dưới
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _showAllJournals
                                ? 'Sổ Nhật Ký Bút Toán Quỹ (Toàn Hệ Thống)'
                                : 'Sổ Nhật Ký Giao Dịch: ${selectedBox.name}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '${displayedJournals.length} bút toán',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        child: displayedJournals.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(32),
                                child: Center(
                                  child: Column(
                                    children: [
                                      Icon(Icons.receipt_long_outlined,
                                          size: 36, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Chưa có bút toán nào phát sinh cho két "${selectedBox.name}".',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                    : ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: displayedJournals.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final j = displayedJournals[i];
                          final isReceipt = j.kind.toLowerCase() == 'receipt' ||
                              j.kind.toLowerCase().contains('thu') ||
                              j.kind.toLowerCase().contains('inbound');

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: (isReceipt ? const Color(0xFF059669) : const Color(0xFFDC2626))
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    isReceipt ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                                    size: 18,
                                    color: isReceipt ? const Color(0xFF059669) : const Color(0xFFDC2626),
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
                                            isReceipt ? 'Thu nộp quỹ tiền mặt' : 'Chi xuất quỹ tiền mặt',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13.5,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: theme.colorScheme.surfaceContainerHighest,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              j.id.length > 8 ? '${j.id.substring(0, 8)}…' : j.id,
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: theme.colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Lý do: ${j.reason.isEmpty ? "Giao dịch kho quỹ thường kỳ" : j.reason} • ${AppFormat.dateTime(j.createdAt)}',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '${isReceipt ? "+" : "-"}${AppFormat.money(j.amount, currency: j.currency)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    color: isReceipt ? const Color(0xFF059669) : const Color(0xFFDC2626),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                ),
              ],
            );
          },
        ),
      ],
    ),
  );
        },
      );
  }

  Widget _buildMetricBox(
    BuildContext context, {
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(18),
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
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Future<_CashData> _load(BankOpsRepository repo) async {
    final results = await Future.wait([
      repo.getCashboxes(),
      repo.getCashBalances(),
      repo.getJournals(),
    ]);
    return _CashData(
      cashboxes: results[0] as List<Cashbox>,
      balances: results[1] as List<CashBalance>,
      journals: results[2] as List<JournalEntry>,
    );
  }
}

class _CashData {
  const _CashData({
    required this.cashboxes,
    required this.balances,
    required this.journals,
  });

  final List<Cashbox> cashboxes;
  final List<CashBalance> balances;
  final List<JournalEntry> journals;
}
