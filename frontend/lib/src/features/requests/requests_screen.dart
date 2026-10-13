import 'package:flutter/material.dart';

import '../../app/app_shell.dart';
import '../../core/util/formatting.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/dtos.dart';
import '../../data/repositories/bankops_repository.dart';

/// Màn yêu cầu — tạo mới và gửi duyệt phiếu kho (stock) + phiếu quỹ (cash).
class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key});

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  Future<_RequestsData>? _future;
  bool _busy = false;

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

  Future<void> _submitStock(String id) async {
    final repo = RepositoryScope.of(context);
    setState(() => _busy = true);
    try {
      await repo.submitStockRequest(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
          content: Text('Đã gửi duyệt thành công phiếu kho $id'),
        ),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFB42318),
          behavior: SnackBarBehavior.floating,
          content: Text('Lỗi gửi duyệt: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitCash(String id) async {
    final repo = RepositoryScope.of(context);
    setState(() => _busy = true);
    try {
      await repo.submitCashRequest(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
          content: Text('Đã gửi duyệt thành công phiếu quỹ $id'),
        ),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFB42318),
          behavior: SnackBarBehavior.floating,
          content: Text('Lỗi gửi duyệt: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteStock(String id) async {
    final repo = RepositoryScope.of(context);
    setState(() => _busy = true);
    try {
      await repo.deleteStockRequest(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
          content: Text('Đã xoá phiếu kho nháp $id'),
        ),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFB42318),
          behavior: SnackBarBehavior.floating,
          content: Text('Lỗi xoá phiếu: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteCash(String id) async {
    final repo = RepositoryScope.of(context);
    setState(() => _busy = true);
    try {
      await repo.deleteCashRequest(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
          content: Text('Đã xoá phiếu quỹ nháp $id'),
        ),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFB42318),
          behavior: SnackBarBehavior.floating,
          content: Text('Lỗi xoá phiếu: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openCreateStockDialog(_RequestsData data) async {
    if (data.locations.isEmpty || data.items.isEmpty) return;
    final repo = RepositoryScope.of(context);
    RequestKind kind = RequestKind.receipt;
    String locationId = data.locations.first.id;
    final nonSerialItems = data.items.where((i) => !i.trackedSerial).toList();
    String itemId =
        (nonSerialItems.isNotEmpty ? nonSerialItems.first : data.items.first).id;
    final qtyCtrl = TextEditingController(text: '25');
    final reasonCtrl = TextEditingController(text: 'Bổ sung vật tư định kỳ');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Tạo Phiếu Kho Mới'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<RequestKind>(
                    key: const Key('stock-kind-dropdown'),
                    initialValue: kind,
                    decoration: const InputDecoration(
                      labelText: 'Loại phiếu',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: RequestKind.receipt,
                        child: Text('Nhập kho (receipt)'),
                      ),
                      DropdownMenuItem(
                        value: RequestKind.payment,
                        child: Text('Xuất kho (issue)'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => kind = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: const Key('stock-location-dropdown'),
                    initialValue: locationId,
                    decoration: const InputDecoration(
                      labelText: 'Kho vật lý',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final loc in data.locations)
                        DropdownMenuItem(
                          value: loc.id,
                          child: Text('${loc.code} — ${loc.name}'),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => locationId = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: const Key('stock-item-dropdown'),
                    initialValue: itemId,
                    decoration: const InputDecoration(
                      labelText: 'Chủng loại ấn chỉ',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final item in data.items)
                        DropdownMenuItem(
                          value: item.id,
                          child: Text('${item.sku} — ${item.name} (${item.unit})'),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => itemId = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('stock-qty-input'),
                    controller: qtyCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Số lượng phôi',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('stock-reason-input'),
                    controller: reasonCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Diễn giải / Lý do lập phiếu',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Huỷ'),
            ),
            FilledButton(
              key: const Key('stock-dialog-save-btn'),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Lưu phiếu nháp'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final created = await repo.createStockRequest(
        kind: kind,
        sourceLocationId: kind == RequestKind.payment ? locationId : null,
        destLocationId: kind == RequestKind.receipt ? locationId : null,
        lines: [
          StockRequestLine(
            itemId: itemId,
            quantity: qtyCtrl.text.trim().isEmpty ? '1' : qtyCtrl.text.trim(),
          ),
        ],
        reason: reasonCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
          content: Text('Đã tạo thành công phiếu kho ${created.id}'),
        ),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFB42318),
          behavior: SnackBarBehavior.floating,
          content: Text('Lỗi tạo phiếu kho: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openCreateCashDialog(_RequestsData data) async {
    if (data.cashboxes.isEmpty) return;
    final repo = RepositoryScope.of(context);
    RequestKind kind = RequestKind.receipt;
    String cashboxId = data.cashboxes.first.id;
    final amountCtrl = TextEditingController(text: '500000');
    final reasonCtrl = TextEditingController(text: 'Thu nộp quỹ tiền mặt đầu ca');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Tạo Phiếu Quỹ Tiền Mặt'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<RequestKind>(
                    key: const Key('cash-kind-dropdown'),
                    initialValue: kind,
                    decoration: const InputDecoration(
                      labelText: 'Loại giao dịch',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: RequestKind.receipt,
                        child: Text('Thu nộp quỹ (receipt)'),
                      ),
                      DropdownMenuItem(
                        value: RequestKind.payment,
                        child: Text('Chi xuất quỹ (payment)'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => kind = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: const Key('cash-box-dropdown'),
                    initialValue: cashboxId,
                    decoration: const InputDecoration(
                      labelText: 'Két sắt chi nhánh',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final box in data.cashboxes)
                        DropdownMenuItem(
                          value: box.id,
                          child: Text('${box.code} — ${box.name}'),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => cashboxId = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('cash-amount-input'),
                    controller: amountCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Số tiền (VND)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('cash-reason-input'),
                    controller: reasonCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Diễn giải lý do nộp/rút quỹ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Huỷ'),
            ),
            FilledButton(
              key: const Key('cash-dialog-save-btn'),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF059669)),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Lưu phiếu nháp'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final created = await repo.createCashRequest(
        cashboxId: cashboxId,
        kind: kind,
        amount: amountCtrl.text.trim().isEmpty ? '100000' : amountCtrl.text.trim(),
        reason: reasonCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
          content: Text('Đã tạo thành công phiếu quỹ ${created.id}'),
        ),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFB42318),
          behavior: SnackBarBehavior.floating,
          content: Text('Lỗi tạo phiếu quỹ: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_RequestsData>(
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
                          'Quản Lý & Lập Phiếu Yêu Cầu',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Khởi tạo phiếu kho ấn chỉ và phiếu quỹ tiền mặt, đệ trình lên hòm thư phê duyệt 4 mắt',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Wrap(
                    spacing: 10,
                    children: [
                      FilledButton.icon(
                        key: const Key('btn-create-stock-request'),
                        onPressed: _busy ? null : () => _openCreateStockDialog(data),
                        icon: const Icon(Icons.add_box_outlined, size: 18),
                        label: const Text('Tạo phiếu kho'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      FilledButton.icon(
                        key: const Key('btn-create-cash-request'),
                        onPressed: _busy ? null : () => _openCreateCashDialog(data),
                        icon: const Icon(Icons.payments_outlined, size: 18),
                        label: const Text('Tạo phiếu quỹ'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Phiếu kho
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Phiếu Kho Ấn Chỉ (${data.stockRequests.length})',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Được kiểm duyệt bởi Checker trước khi xuất/nhập',
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final r in data.stockRequests)
                Container(
                  key: Key('stock-request-card-${r.id}'),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.inventory_2_outlined, color: Color(0xFF2563EB), size: 20),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Phiếu kho ${r.id.length > 8 ? "${r.id.substring(0, 8)}…" : r.id}',
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                  ),
                                  const SizedBox(width: 8),
                                  _statusChip(r.status),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Loại: ${r.kind.label} • Người lập: ${r.createdByName} • Lý do: ${r.reason.isEmpty ? "Xuất nhập kho định kỳ" : r.reason}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (r.status == RequestStatus.draft)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                key: Key('btn-delete-stock-${r.id}'),
                                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                tooltip: 'Xoá phiếu nháp',
                                onPressed: _busy ? null : () => _deleteStock(r.id),
                              ),
                              const SizedBox(width: 4),
                              FilledButton.icon(
                                key: Key('btn-submit-stock-${r.id}'),
                                onPressed: _busy ? null : () => _submitStock(r.id),
                                icon: const Icon(Icons.send_rounded, size: 16),
                                label: const Text('Gửi duyệt'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF2563EB),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ],
                          )
                        else
                          _statusBadge(r.status),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),

              // Phiếu quỹ
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Phiếu Quỹ Tiền Mặt (${data.cashRequests.length})',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Ảnh hưởng số dư két sau khi được phê duyệt',
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final r in data.cashRequests)
                Container(
                  key: Key('cash-request-card-${r.id}'),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF059669).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.savings_outlined, color: Color(0xFF059669), size: 20),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Phiếu quỹ ${r.id.length > 8 ? "${r.id.substring(0, 8)}…" : r.id}',
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                  ),
                                  const SizedBox(width: 8),
                                  _statusChip(r.status),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Số tiền: ${AppFormat.money(r.amount, currency: r.currency)} • Người lập: ${r.createdByName} • Lý do: ${r.reason.isEmpty ? "Giao dịch quỹ thường kỳ" : r.reason}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (r.status == RequestStatus.draft)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                key: Key('btn-delete-cash-${r.id}'),
                                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                tooltip: 'Xoá phiếu nháp',
                                onPressed: _busy ? null : () => _deleteCash(r.id),
                              ),
                              const SizedBox(width: 4),
                              FilledButton.icon(
                                key: Key('btn-submit-cash-${r.id}'),
                                onPressed: _busy ? null : () => _submitCash(r.id),
                                icon: const Icon(Icons.send_rounded, size: 16),
                                label: const Text('Gửi duyệt'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF059669),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ],
                          )
                        else
                          _statusBadge(r.status),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _statusChip(RequestStatus status) {
    Color bg;
    Color fg;
    String text;

    switch (status) {
      case RequestStatus.draft:
        bg = const Color(0xFFF1F5F9);
        fg = const Color(0xFF475467);
        text = 'Bản nháp';
        break;
      case RequestStatus.pending:
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFFB45309);
        text = 'Chờ duyệt';
        break;
      case RequestStatus.approved:
        bg = const Color(0xFFD1FAE5);
        fg = const Color(0xFF065F46);
        text = 'Đã duyệt';
        break;
      case RequestStatus.posted:
        bg = const Color(0xFFCCFBF1);
        fg = const Color(0xFF0F766E);
        text = 'Đã ghi sổ';
        break;
      case RequestStatus.rejected:
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFF991B1B);
        text = 'Bị từ chối';
        break;
      default:
        bg = const Color(0xFFF1F5F9);
        fg = const Color(0xFF475467);
        text = status.name;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _statusBadge(RequestStatus status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: status == RequestStatus.posted || status == RequestStatus.approved
            ? const Color(0xFF059669).withValues(alpha: 0.12)
            : const Color(0xFF64748B).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.name.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: status == RequestStatus.posted || status == RequestStatus.approved
              ? const Color(0xFF059669)
              : const Color(0xFF475467),
        ),
      ),
    );
  }

  Future<_RequestsData> _load(BankOpsRepository repo) async {
    final results = await Future.wait([
      repo.getStockRequests(),
      repo.getCashRequests(),
      repo.getLocations(),
      repo.getItems(),
      repo.getCashboxes(),
    ]);
    return _RequestsData(
      stockRequests: results[0] as List<StockRequest>,
      cashRequests: results[1] as List<CashRequest>,
      locations: results[2] as List<InventoryLocation>,
      items: results[3] as List<InventoryItem>,
      cashboxes: results[4] as List<Cashbox>,
    );
  }
}

class _RequestsData {
  const _RequestsData({
    required this.stockRequests,
    required this.cashRequests,
    required this.locations,
    required this.items,
    required this.cashboxes,
  });

  final List<StockRequest> stockRequests;
  final List<CashRequest> cashRequests;
  final List<InventoryLocation> locations;
  final List<InventoryItem> items;
  final List<Cashbox> cashboxes;
}
