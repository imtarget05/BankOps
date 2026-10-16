import 'package:flutter/material.dart';

import '../../app/app_shell.dart';
import '../../core/sync/data_sync_controller.dart';
import '../../core/util/formatting.dart';
import '../../core/util/role_visibility.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/dtos.dart';
import '../../data/repositories/bankops_repository.dart';
import 'shift_stocktake_desk.dart';
import 'import_items_dialog.dart';

/// Chế độ hiển thị của màn hình Kho và Ca làm việc.
enum InventoryTabMode {
  all,
  stock,
  shiftWork,
}

/// Màn quản lý nguyên vật liệu và ca làm việc cho quán trà sữa.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({
    super.key,
    this.mode = InventoryTabMode.all,
    this.onNavigate,
    this.onCreateStockRequest,
  });

  final InventoryTabMode mode;
  final ValueChanged<int>? onNavigate;
  final VoidCallback? onCreateStockRequest;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  Future<_InventoryData>? _future;
  DataSyncController? _syncController;
  bool _isSelectionMode = false;
  final Set<String> _selectedItemIds = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = RepositoryScope.of(context);
    _future ??= _load(repo);

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
    if (last == null ||
        last.topic == SyncTopic.inventory ||
        last.topic == SyncTopic.stocktake ||
        last.topic == SyncTopic.requests ||
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
    setState(() {
      _future = _load(repo);
    });
  }

  String _slugSku(String name) {
    var s = name.trim().toLowerCase();
    const map = {
      'à|á|ạ|ả|ã|â|ầ|ấ|ậ|ẩ|ẫ|ă|ằ|ắ|ặ|ẳ|ẵ': 'a',
      'è|é|ẹ|ẻ|ẽ|ê|ề|ế|ệ|ể|ễ': 'e',
      'ì|í|ị|ỉ|ĩ': 'i',
      'ò|ó|ọ|ỏ|õ|ô|ồ|ố|ộ|ổ|ỗ|ơ|ờ|ớ|ợ|ở|ỡ': 'o',
      'ù|ú|ụ|ủ|ũ|ư|ừ|ứ|ự|ử|ữ': 'u',
      'ỳ|ý|ỵ|ỷ|ỹ': 'y',
      'đ': 'd',
    };
    for (final entry in map.entries) {
      s = s.replaceAll(RegExp(entry.key), entry.value);
    }
    s = s.replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    if (s.isEmpty) {
      s = 'SP-${DateTime.now().millisecondsSinceEpoch % 100000}';
    }
    return s.toUpperCase();
  }

  Future<void> _showCreateItemDialog() async {
    final skuCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final unitCtrl = TextEditingController(text: 'gói');
    final categoryCtrl = TextEditingController(text: 'Nguyên liệu');
    final packagingCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.inventory_2_outlined, color: Color(0xFF2563EB)),
              SizedBox(width: 8),
              Text('Thêm nguyên vật liệu',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: skuCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Mã SKU (tự sinh nếu để trống)',
                    hintText: 'Ví dụ: TRA-OLONG-500G',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tên nguyên vật liệu *',
                    hintText: 'Ví dụ: Trà ô long đặc biệt',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: unitCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Đơn Vị Tính',
                    hintText: 'Gói / Túi / Kg / Hộp / Chai',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: categoryCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Nhóm nguyên liệu',
                      hintText: 'Ví dụ: Nhóm Trà / Topping / Sữa',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: packagingCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Quy cách đóng gói',
                      hintText: 'Ví dụ: 500 g/gói',
                      border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                if (skuCtrl.text.trim().isEmpty) {
                  skuCtrl.text = _slugSku(name);
                }
                Navigator.of(ctx).pop(true);
              },
              child: const Text('Thêm mới'),
            ),
          ],
        ),
      ),
    );

    if (ok == true && mounted) {
      final finalName = nameCtrl.text.trim();
      final finalSku = (skuCtrl.text.trim().isEmpty ? _slugSku(finalName) : skuCtrl.text.trim()).toUpperCase();
      try {
        final repo = RepositoryScope.of(context);
        await repo.createItem(
          sku: finalSku,
          name: finalName,
          unit: unitCtrl.text.trim().isEmpty ? 'gói' : unitCtrl.text.trim(),
          trackedSerial: false,
          category: categoryCtrl.text.trim().isEmpty ? 'Nguyên liệu' : categoryCtrl.text.trim(),
          packaging: packagingCtrl.text.trim(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Đã thêm mặt hàng "$finalName" ($finalSku) thành công!'),
              behavior: SnackBarBehavior.floating,
            ),
          );
          _refresh();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Lỗi: ${friendlyError(e)}'),
                backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _showImportItemsDialog(List<InventoryItem> existingItems) async {
    final result = await showDialog<BatchItemImportResult>(
      context: context,
      builder: (ctx) => ImportItemsDialog(existingItems: existingItems),
    );

    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đã nhập thành công ${result.createdCount} mặt hàng vào kho!'
            '${result.skippedCount > 0 ? " (Bỏ qua ${result.skippedCount} món đã có)" : ""}',
          ),
          backgroundColor: const Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _refresh();
    }
  }

  Future<void> _showEditItemDialog(InventoryItem item) async {
    final nameCtrl = TextEditingController(text: item.name);
    final unitCtrl = TextEditingController(text: item.unit);
    final categoryCtrl = TextEditingController(text: item.category ?? '');
    final packagingCtrl = TextEditingController(text: item.packaging ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.edit_outlined, color: Color(0xFF2563EB)),
            const SizedBox(width: 8),
            Text('Sửa: ${item.sku}',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Tên nguyên vật liệu *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
                controller: categoryCtrl,
                decoration: const InputDecoration(
                    labelText: 'Nhóm nguyên liệu',
                    border: OutlineInputBorder())),
            const SizedBox(height: 14),
            TextField(
                controller: packagingCtrl,
                decoration: const InputDecoration(
                    labelText: 'Quy cách đóng gói',
                    border: OutlineInputBorder())),
            const SizedBox(height: 14),
            TextField(
              controller: unitCtrl,
              decoration: const InputDecoration(
                labelText: 'Đơn Vị Tính',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Lưu thay đổi'),
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      try {
        final repo = RepositoryScope.of(context);
        await repo.updateItem(
          id: item.id,
          name: nameCtrl.text.trim(),
          unit: unitCtrl.text.trim(),
          category: categoryCtrl.text.trim(),
          packaging: packagingCtrl.text.trim(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Đã cập nhật thông tin mặt hàng!'),
                behavior: SnackBarBehavior.floating),
          );
          _refresh();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Lỗi: ${friendlyError(e)}'),
                backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      _selectedItemIds.clear();
    });
  }

  void _toggleItemSelection(String itemId) {
    setState(() {
      if (_selectedItemIds.contains(itemId)) {
        _selectedItemIds.remove(itemId);
      } else {
        _selectedItemIds.add(itemId);
      }
    });
  }

  void _selectAllItems(List<InventoryItem> items) {
    setState(() {
      _selectedItemIds.addAll(items.map((i) => i.id));
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedItemIds.clear();
    });
  }

  Future<void> _confirmDeleteItem(InventoryItem item, [List<StockBalance>? balances]) async {
    // Check if item has remaining stock
    double totalStock = 0;
    if (balances != null) {
      totalStock = balances
          .where((b) => b.itemId == item.id)
          .fold<double>(0, (sum, b) => sum + (double.tryParse(b.quantity) ?? 0));
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Expanded(
              child: Text('Xác nhận xóa mặt hàng',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Bạn có chắc chắn muốn xóa mặt hàng "${item.name}" (SKU: ${item.sku}) không?'),
            if (totalStock > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade700),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 18, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Cảnh báo: Mặt hàng đang còn tồn kho (${AppFormat.intFormat(totalStock.round())} ${item.unit}).',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            key: Key('btn-confirm-delete-${item.sku}'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Xác nhận xóa'),
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      try {
        final repo = RepositoryScope.of(context);
        await repo.deleteItem(item.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Đã xóa mặt hàng "${item.name}"!'),
                behavior: SnackBarBehavior.floating),
          );
          _refresh();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Lỗi: ${friendlyError(e)}'),
                backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _confirmDeleteItemsBatch(
      List<InventoryItem> allItems, List<StockBalance> balances) async {
    final selectedItems =
        allItems.where((i) => _selectedItemIds.contains(i.id)).toList();
    if (selectedItems.isEmpty) return;

    // Check if any selected item has stock > 0
    final itemsWithStock = <String>[];
    for (final item in selectedItems) {
      final totalQty = balances
          .where((b) => b.itemId == item.id)
          .fold<double>(0, (sum, b) => sum + (double.tryParse(b.quantity) ?? 0));
      if (totalQty > 0) {
        itemsWithStock.add(
            '${item.name} (${AppFormat.intFormat(totalQty.round())} ${item.unit})');
      }
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Expanded(
              child: Text('Xác nhận xóa hàng loạt',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Bạn có chắc chắn muốn xóa ${selectedItems.length} mặt hàng đã chọn không?'),
            if (itemsWithStock.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade700),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.orange),
                        SizedBox(width: 6),
                        Text('Lưu ý mặt hàng còn tồn kho:',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    for (final s in itemsWithStock.take(5))
                      Text('• $s', style: const TextStyle(fontSize: 11.5)),
                    if (itemsWithStock.length > 5)
                      Text(
                          '... và ${itemsWithStock.length - 5} mặt hàng khác',
                          style: const TextStyle(
                              fontSize: 11, fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            key: const Key('btn-confirm-batch-delete'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Xác nhận xóa (${selectedItems.length})'),
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      try {
        final repo = RepositoryScope.of(context);
        await repo.deleteItemsBatch(selectedItems.map((i) => i.id).toList());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('Đã xóa thành công ${selectedItems.length} mặt hàng!'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFF059669),
            ),
          );
          setState(() {
            _selectedItemIds.clear();
            _isSelectionMode = false;
          });
          _refresh();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Lỗi xóa mặt hàng: ${friendlyError(e)}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _showAssetLifecycleDialog(
      AssetRecord asset, _InventoryData data) async {
    final repo = RepositoryScope.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final loc = data.locations.cast<InventoryLocation?>().firstWhere(
          (l) => l?.id == asset.locationId,
          orElse: () => null,
        );
    final itm = data.items.cast<InventoryItem?>().firstWhere(
          (it) => it?.id == asset.itemId,
          orElse: () => null,
        );

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlgState) {
            return FutureBuilder<List<AssetLogItem>>(
              future: repo.getAssetHistory(asset.id ?? asset.serial),
              builder: (ctx, snapshot) {
                return AlertDialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  title: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF7C3AED).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.qr_code_2_rounded,
                            color: Color(0xFF7C3AED), size: 22),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Vòng Đời & Bàn Giao: ${asset.serial}',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '${itm?.name ?? "Vật tư"} • Kho hiện tại: ${loc?.name ?? asset.locationId}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  content: SizedBox(
                    width: 600,
                    height: 440,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Summary card
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1E293B)
                                : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: theme.colorScheme.outlineVariant
                                    .withValues(alpha: 0.5)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Người phụ trách',
                                      style: TextStyle(
                                          fontSize: 11, color: Colors.grey)),
                                  const SizedBox(height: 2),
                                  Text(
                                    asset.assignee ?? 'Chưa bàn giao',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Trạng thái',
                                      style: TextStyle(
                                          fontSize: 11, color: Colors.grey)),
                                  const SizedBox(height: 2),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981)
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      asset.status.name.toUpperCase(),
                                      style: const TextStyle(
                                        color: Color(0xFF059669),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              FilledButton.icon(
                                key: const Key('btn-open-handover-dialog'),
                                onPressed: () async {
                                  final done =
                                      await _showHandoverDialog(asset, data);
                                  if (done == true) {
                                    setDlgState(() {});
                                    _refresh();
                                  }
                                },
                                icon: const Icon(Icons.handshake_outlined,
                                    size: 16),
                                label: const Text('Bàn giao nguyên liệu'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF7C3AED),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Sổ Nhật Ký Vòng Đời & Luân Chuyển',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: snapshot.connectionState !=
                                  ConnectionState.done
                              ? const Center(child: CircularProgressIndicator())
                              : (snapshot.data == null ||
                                      snapshot.data!.isEmpty)
                                  ? const Center(
                                      child: Text(
                                          'Chưa có lịch sử luân chuyển cho nguyên liệu này.'))
                                  : ListView.separated(
                                      itemCount: snapshot.data!.length,
                                      separatorBuilder: (_, __) =>
                                          const Divider(height: 12),
                                      itemBuilder: (ctx, idx) {
                                        final log = snapshot.data![idx];
                                        return Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF7C3AED)
                                                    .withValues(alpha: 0.1),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(Icons.timeline,
                                                  size: 14,
                                                  color: Color(0xFF7C3AED)),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      Text(
                                                        log.statusBefore != null
                                                            ? '${log.statusBefore} → ${log.statusAfter}'
                                                            : log.statusAfter,
                                                        style: const TextStyle(
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            fontSize: 12.5),
                                                      ),
                                                      Text(
                                                        AppFormat.dateTime(
                                                            log.createdAt),
                                                        style: const TextStyle(
                                                            fontSize: 11,
                                                            color: Colors.grey),
                                                      ),
                                                    ],
                                                  ),
                                                  if (log.toLocationName !=
                                                          null ||
                                                      log.toAssignee !=
                                                          null) ...[
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      'Kho: ${log.toLocationName ?? "N/A"}${log.toAssignee != null ? " • Người nhận: ${log.toAssignee}" : ""}',
                                                      style: TextStyle(
                                                          fontSize: 11.5,
                                                          color: theme
                                                              .colorScheme
                                                              .onSurfaceVariant),
                                                    ),
                                                  ],
                                                  if (log.notes != null &&
                                                      log.notes!
                                                          .isNotEmpty) ...[
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      'Ghi chú: ${log.notes}',
                                                      style: const TextStyle(
                                                          fontSize: 11.5,
                                                          fontStyle:
                                                              FontStyle.italic,
                                                          color: Colors.grey),
                                                    ),
                                                  ],
                                                  if (log.actorName !=
                                                      null) ...[
                                                    const SizedBox(height: 1),
                                                    Text(
                                                      'Thực hiện bởi: ${log.actorName}',
                                                      style: const TextStyle(
                                                          fontSize: 10.5,
                                                          color: Colors.grey),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Đóng'),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Future<bool?> _showHandoverDialog(
      AssetRecord asset, _InventoryData data) async {
    final repo = RepositoryScope.of(context);
    String? toLocId = asset.locationId;
    final assigneeCtrl = TextEditingController(text: asset.assignee ?? '');
    final notesCtrl = TextEditingController();
    String newStatus = asset.status.name;

    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Bàn Giao / Luân Chuyển: ${asset.serial}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  key: const Key('handover-location-dropdown'),
                  isExpanded: true,
                  initialValue: toLocId,
                  decoration: const InputDecoration(
                      labelText: 'Kho / Vị trí đích',
                      border: OutlineInputBorder()),
                  items: [
                    for (final loc in data.locations)
                      DropdownMenuItem(
                          value: loc.id,
                          child: Text('${loc.code} — ${loc.name}')),
                  ],
                  onChanged: (v) => setDlgState(() => toLocId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('handover-assignee-input'),
                  controller: assigneeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Cán bộ / GDV tiếp nhận *',
                    hintText: 'Nhập tên hoặc mã nhân viên',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const Key('handover-status-dropdown'),
                  isExpanded: true,
                  initialValue: newStatus,
                  decoration: const InputDecoration(
                      labelText: 'Trạng thái sau bàn giao',
                      border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(
                        value: 'available',
                        child: Text('available (Trong kho/Khả dụng)')),
                    DropdownMenuItem(
                        value: 'inUse',
                        child: Text('inUse (Đang sử dụng/Đã bàn giao)')),
                    DropdownMenuItem(
                        value: 'maintenance',
                        child: Text('maintenance (Kiểm kê/Bảo trì)')),
                    DropdownMenuItem(
                        value: 'disposed',
                        child: Text('disposed (Hủy/Mất/Thu hồi)')),
                  ],
                  onChanged: (v) =>
                      setDlgState(() => newStatus = v ?? newStatus),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('handover-notes-input'),
                  controller: notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Nội dung biên bản bàn giao / Ghi chú',
                    hintText: 'Bàn giao phôi séc/thẻ cho GDV quầy...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Huỷ')),
            FilledButton(
              key: const Key('handover-confirm-btn'),
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED)),
              onPressed: () async {
                try {
                  await repo.handoverAsset(
                    asset.id ?? asset.serial,
                    toLocationId: toLocId,
                    toAssignee: assigneeCtrl.text.trim().isNotEmpty
                        ? assigneeCtrl.text.trim()
                        : null,
                    status: newStatus,
                    notes: notesCtrl.text.trim().isNotEmpty
                        ? notesCtrl.text.trim()
                        : null,
                  );
                  if (ctx.mounted) Navigator.of(ctx).pop(true);
                  if (mounted) {
                    AppToast.success(
                        context, 'Bàn giao nguyên liệu thành công!');
                  }
                } catch (e) {
                  if (mounted)
                    AppToast.error(
                        context, 'Lỗi bàn giao: ${friendlyError(e)}');
                }
              },
              child: const Text('Xác nhận bàn giao'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSetStockLevelDialog(
    InventoryItem item,
    List<InventoryLocation> locations,
    List<StockLevelItem> stockLevels,
  ) async {
    if (locations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Chưa có kho lưu trữ để thiết lập định mức.')),
      );
      return;
    }

    String selectedLocId = locations.first.id;
    final existingLevel = stockLevels.cast<StockLevelItem?>().firstWhere(
          (l) => l?.itemId == item.id && l?.locationId == selectedLocId,
          orElse: () => null,
        );

    final minCtrl = TextEditingController(text: existingLevel?.minQty ?? '10');
    final maxCtrl = TextEditingController(text: existingLevel?.maxQty ?? '100');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.tune_rounded, color: Color(0xFF2563EB)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Định Mức Tồn: ${item.name}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Chọn Kho Lưu Trữ:',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: selectedLocId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                    items: locations
                        .map((l) => DropdownMenuItem(
                            value: l.id, child: Text('${l.code} - ${l.name}')))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDlgState(() {
                          selectedLocId = val;
                          final lvl =
                              stockLevels.cast<StockLevelItem?>().firstWhere(
                                    (l) =>
                                        l?.itemId == item.id &&
                                        l?.locationId == selectedLocId,
                                    orElse: () => null,
                                  );
                          minCtrl.text = lvl?.minQty ?? '10';
                          maxCtrl.text = lvl?.maxQty ?? '100';
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: minCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Định mức tối thiểu (Min Qty) *',
                      helperText: 'Cảnh báo thiếu khi tồn kho < mức này',
                      suffixText: item.unit,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: maxCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Định mức tối đa (Max Qty)',
                      helperText: 'Giới hạn lưu trữ an toàn của kho',
                      suffixText: item.unit,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Hủy')),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB)),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Lưu Định Mức'),
              ),
            ],
          );
        },
      ),
    );

    if (ok == true && mounted) {
      try {
        final repo = RepositoryScope.of(context);
        await repo.putStockLevel(
          locationId: selectedLocId,
          itemId: item.id,
          minQty: minCtrl.text.trim(),
          maxQty: maxCtrl.text.trim().isNotEmpty ? maxCtrl.text.trim() : null,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Đã cập nhật định mức tồn kho an toàn!'),
                behavior: SnackBarBehavior.floating),
          );
          _refresh();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Lỗi: ${friendlyError(e)}'),
                backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _showCreateStocktakeDialog(
      List<InventoryLocation> locations) async {
    if (locations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa có kho để mở đợt kiểm kê.')),
      );
      return;
    }
    String selectedLocId = locations.first.id;
    String selectedShift = 'morning';
    final noteCtrl = TextEditingController(text: 'Chốt tồn theo ca');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.fact_check_outlined, color: Color(0xFF0891B2)),
            SizedBox(width: 8),
            Text('Mở Đợt Kiểm Kê Mới',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Kho thực hiện kiểm kê *:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: selectedLocId,
              isExpanded: true,
              decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
              items: locations
                  .map((l) => DropdownMenuItem(
                      value: l.id, child: Text('${l.code} - ${l.name}')))
                  .toList(),
              onChanged: (val) {
                if (val != null) selectedLocId = val;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: selectedShift,
              decoration: const InputDecoration(
                labelText: 'Ca làm việc',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                    value: 'morning', child: Text('Ca Sáng 07:30 – 15:00')),
                DropdownMenuItem(
                    value: 'afternoon', child: Text('Ca Chiều 15:00 – 23:00')),
                DropdownMenuItem(
                    value: 'split', child: Text('Ca Lỡ ngày 07:30 – 18:00')),
              ],
              onChanged: (value) => selectedShift = value ?? 'morning',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Ghi chú chốt ca',
                hintText: 'VD: Chốt tồn cuối Ca Sáng',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Hủy')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0891B2)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Bắt Đầu Kiểm Kê'),
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      try {
        final repo = RepositoryScope.of(context);
        await repo.createStocktake(
          locationId: selectedLocId,
          note: noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : null,
          shiftCode: selectedShift,
          businessDate: DateTime.now().toIso8601String().substring(0, 10),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Đã mở phiên chốt tồn theo ca!'),
                behavior: SnackBarBehavior.floating),
          );
          _refresh();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Lỗi: ${friendlyError(e)}'),
                backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _showStocktakeDetailDialog(
    StocktakeItem stocktake,
    List<InventoryItem> items,
    List<InventoryLocation> locations, {
    List<StockLevelItem>? stockLevels,
  }) async {
    final loc = locations.cast<InventoryLocation?>().firstWhere(
          (l) => l?.id == stocktake.locationId,
          orElse: () => null,
        );
    final locName =
        loc != null ? '${loc.code} - ${loc.name}' : stocktake.locationId;
    final canEdit = stocktake.status == 'open';
    final canApprove = stocktake.status == 'submitted';

    // Map existing counted lines or initialize
    final countCtrls = <String, TextEditingController>{};
    final usedCtrls = <String, TextEditingController>{};
    final reasonCtrls = <String, TextEditingController>{};

    for (final it in items) {
      final existingLine =
          stocktake.lines.cast<StocktakeLineItem?>().firstWhere(
                (l) => l?.itemId == it.id,
                orElse: () => null,
              );
      usedCtrls[it.id] = TextEditingController(
        text: existingLine != null ? existingLine.usedQty : '0',
      );
      countCtrls[it.id] = TextEditingController(
        text: existingLine != null ? existingLine.countedQty : (existingLine?.bookQty ?? '0'),
      );
      reasonCtrls[it.id] = TextEditingController(
        text: existingLine?.reason ?? '',
      );
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.fact_check, color: Color(0xFF0891B2)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${stocktake.shiftCode == 'morning' ? 'Ca Sáng 07:30 – 15:00' : stocktake.shiftCode == 'afternoon' ? 'Ca Chiều 15:00 – 23:00' : stocktake.shiftCode == 'split' ? 'Ca Lỡ ngày 07:30 – 18:00' : 'Kiểm Kê Kho'}: $locName',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Trạng thái: ${stocktake.status == 'open' ? 'Đang kiểm đếm (Open)' : (stocktake.status == 'submitted' ? 'Chờ Checker duyệt (Submitted)' : 'Đã đóng & Điều chỉnh (Closed)')}',
                        style: TextStyle(
                          fontSize: 12,
                          color: stocktake.status == 'open'
                              ? Colors.blue
                              : (stocktake.status == 'submitted'
                                  ? Colors.orange
                                  : Colors.green),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 1100,
              height: 520,
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 1050),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!canEdit)
                          Container(
                            padding: const EdgeInsets.all(10),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: (stocktake.status == 'submitted'
                                      ? Colors.orange
                                      : Colors.green)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: (stocktake.status == 'submitted'
                                          ? Colors.orange
                                          : Colors.green)
                                      .withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  stocktake.status == 'submitted'
                                      ? Icons.hourglass_top
                                      : Icons.lock_outline,
                                  color: stocktake.status == 'submitted'
                                      ? Colors.orange[800]
                                      : Colors.green[800],
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    stocktake.status == 'submitted'
                                        ? 'Ca kiểm kê đang chờ Checker phê duyệt. Dữ liệu đã khóa để đảm bảo tính toàn vẹn.'
                                        : 'Phiên kiểm kê đã đóng sổ & đối soát hoàn tất.',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: stocktake.status == 'submitted'
                                          ? Colors.orange[900]
                                          : Colors.green[900],
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (stocktake.note != null && stocktake.note!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text('Ghi chú: ${stocktake.note}',
                                style:
                                    const TextStyle(fontStyle: FontStyle.italic)),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            'Công thức SRS: Còn lại cuối ca = Tồn đầu ca + Nhập − Sử dụng. Độ lệch = Kiểm thực tế − Còn lại cuối ca.',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.primary),
                          ),
                        ),
                        if (stocktake.adjustmentRequestId != null)
                          Container(
                            padding: const EdgeInsets.all(10),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: Colors.green.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle,
                                    color: Colors.green, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Đã sinh phiếu điều chỉnh kho tự động: #${stocktake.adjustmentRequestId}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: Colors.green,
                                        fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Table(
                          columnWidths: const {
                            0: FixedColumnWidth(45), // STT
                            1: FixedColumnWidth(175), // Nguyên liệu
                            2: FixedColumnWidth(65), // ĐVT
                            3: FixedColumnWidth(80), // Tồn đầu
                            4: FixedColumnWidth(70), // Nhập
                            5: FixedColumnWidth(140), // Sử dụng (+/-)
                            6: FixedColumnWidth(95), // Còn lại cuối ca
                            7: FixedColumnWidth(140), // Kiểm thực tế (+/-)
                            8: FixedColumnWidth(85), // Độ lệch
                            9: FixedColumnWidth(155), // Trạng thái & Lý do
                          },
                          border: TableBorder.all(
                              color: Colors.grey.withValues(alpha: 0.2)),
                          children: [
                            TableRow(
                              decoration: BoxDecoration(
                                  color: Colors.grey.withValues(alpha: 0.1)),
                              children: const [
                                Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Text('STT',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12))),
                                Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Text('Nguyên liệu',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12))),
                                Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Text('ĐVT',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12))),
                                Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Text('Tồn đầu',
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12))),
                                Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Text('Nhập',
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12))),
                                Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Text('Sử dụng (+/-)',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12))),
                                Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Text('Còn lại',
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12))),
                                Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Text('Kiểm thực tế (+/-)',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12))),
                                Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Text('Độ lệch',
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12))),
                                Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Text('Trạng thái & Lý do',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12))),
                              ],
                            ),
                            for (var idx = 0; idx < items.length; idx++)
                              _buildStocktakeRow(
                                index: idx,
                                stocktake: stocktake,
                                item: items[idx],
                                canEdit: canEdit,
                                usedCtrl: usedCtrls[items[idx].id]!,
                                countCtrl: countCtrls[items[idx].id]!,
                                reasonCtrl: reasonCtrls[items[idx].id]!,
                                stockLevels: stockLevels,
                                onChanged: () => setDlgState(() {}),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Đóng')),
              if (canEdit) ...[
                OutlinedButton(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final navigator = Navigator.of(ctx);
                    try {
                      final repo = RepositoryScope.of(context);
                      final linesPayload = items.map((it) {
                        final existingLine = stocktake.lines
                            .cast<StocktakeLineItem?>()
                            .firstWhere(
                              (l) => l?.itemId == it.id,
                              orElse: () => null,
                            );
                        final opening = double.tryParse(existingLine?.openingQty ?? '') ??
                            (double.tryParse(existingLine?.bookQty ?? '') ?? 0.0);
                        final received = double.tryParse(existingLine?.receivedQty ?? '') ?? 0.0;
                        final used = double.tryParse(usedCtrls[it.id]?.text.trim() ?? '0') ?? 0.0;
                        final counted = double.tryParse(countCtrls[it.id]?.text.trim() ?? '0') ?? 0.0;
                        return {
                          'item_id': it.id,
                          'opening_qty': opening.toString(),
                          'received_qty': received.toString(),
                          'used_qty': used.toString(),
                          'counted_qty': counted.toString(),
                          'reason': reasonCtrls[it.id]?.text.trim() ?? '',
                        };
                      }).toList();
                      await repo.updateStocktakeLines(
                          stocktake.id, linesPayload);
                      if (mounted) {
                        messenger.showSnackBar(
                          const SnackBar(
                              content: Text('Đã lưu số kiểm đếm thực tế!'),
                              behavior: SnackBarBehavior.floating),
                        );
                        navigator.pop();
                        _refresh();
                      }
                    } catch (e) {
                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(
                              content: Text('Lỗi: ${friendlyError(e)}'),
                              backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  child: const Text('Lưu Số Đếm'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB)),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final navigator = Navigator.of(ctx);
                    try {
                      final repo = RepositoryScope.of(context);
                      final linesPayload = items.map((it) {
                        final existingLine = stocktake.lines
                            .cast<StocktakeLineItem?>()
                            .firstWhere(
                              (l) => l?.itemId == it.id,
                              orElse: () => null,
                            );
                        final opening = double.tryParse(existingLine?.openingQty ?? '') ??
                            (double.tryParse(existingLine?.bookQty ?? '') ?? 0.0);
                        final received = double.tryParse(existingLine?.receivedQty ?? '') ?? 0.0;
                        final used = double.tryParse(usedCtrls[it.id]?.text.trim() ?? '0') ?? 0.0;
                        final counted = double.tryParse(countCtrls[it.id]?.text.trim() ?? '0') ?? 0.0;
                        return {
                          'item_id': it.id,
                          'opening_qty': opening.toString(),
                          'received_qty': received.toString(),
                          'used_qty': used.toString(),
                          'counted_qty': counted.toString(),
                          'reason': reasonCtrls[it.id]?.text.trim() ?? '',
                        };
                      }).toList();
                      await repo.updateStocktakeLines(
                          stocktake.id, linesPayload);
                      await repo.submitStocktake(stocktake.id);
                      if (mounted) {
                        messenger.showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Đã gửi kiểm kê sang Checker phê duyệt!'),
                              behavior: SnackBarBehavior.floating),
                        );
                        navigator.pop();
                        _refresh();
                      }
                    } catch (e) {
                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(
                              content: Text('Lỗi: ${friendlyError(e)}'),
                              backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  child: const Text('Gửi Duyệt Đối Soát'),
                ),
              ],
              if (canApprove) ...[
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF059669)),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final navigator = Navigator.of(ctx);
                    try {
                      final repo = RepositoryScope.of(context);
                      await repo.approveStocktake(stocktake.id);
                      if (mounted) {
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Đã phê duyệt kiểm kê & tự động sinh phiếu điều chỉnh!'),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: Color(0xFF059669),
                          ),
                        );
                        navigator.pop();
                        _refresh();
                      }
                    } catch (e) {
                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(
                              content: Text('Lỗi: ${friendlyError(e)}'),
                              backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  child: const Text('Phê Duyệt & Sinh Phiếu Điều Chỉnh'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  TableRow _buildStocktakeRow({
    required int index,
    required StocktakeItem stocktake,
    required InventoryItem item,
    required bool canEdit,
    required TextEditingController usedCtrl,
    required TextEditingController countCtrl,
    required TextEditingController reasonCtrl,
    List<StockLevelItem>? stockLevels,
    required VoidCallback onChanged,
  }) {
    final line = stocktake.lines.cast<StocktakeLineItem?>().firstWhere(
          (l) => l?.itemId == item.id,
          orElse: () => null,
        );
    final opening = double.tryParse(line?.openingQty ?? '') ??
        (double.tryParse(line?.bookQty ?? '') ?? 0.0);
    final received = double.tryParse(line?.receivedQty ?? '') ?? 0.0;
    final used = double.tryParse(usedCtrl.text.trim()) ?? 0.0;
    final remaining = opening + received - used;
    final counted = double.tryParse(countCtrl.text.trim()) ?? 0.0;
    final diff = counted - remaining;

    Color diffColor = Colors.grey;
    if (diff > 0.001) diffColor = const Color(0xFF15803D);
    if (diff < -0.001) diffColor = const Color(0xFFDC2626);

    final statusText = diff.abs() < 0.001
        ? '🟢 Khớp'
        : (diff > 0 ? '🟡 Thừa' : '🔴 Thiếu');
    final statusColor = diff.abs() < 0.001
        ? const Color(0xFF15803D)
        : (diff > 0 ? const Color(0xFFB45309) : const Color(0xFFDC2626));
    final statusBg = statusColor.withValues(alpha: 0.12);

    final stockLevel = stockLevels?.cast<StockLevelItem?>().firstWhere(
          (sl) => sl?.itemId == item.id,
          orElse: () => null,
        );
    final minQty = double.tryParse(stockLevel?.minQty ?? '') ?? 0.0;
    final isLowStock = minQty > 0 && counted <= minQty;

    String formatQty(double val) =>
        val == val.roundToDouble() ? val.toInt().toString() : val.toStringAsFixed(1);

    return TableRow(
      children: [
        // 0: STT
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            '${index + 1}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        // 1: Nguyên liệu
        Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13)),
              Text(item.sku,
                  style: const TextStyle(color: Colors.grey, fontSize: 11)),
            ],
          ),
        ),
        // 2: ĐVT
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            item.unit,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
        ),
        // 3: Tồn đầu
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            formatQty(opening),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
        // 4: Nhập
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            formatQty(received),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
        // 5: Sử dụng (+/-)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: _buildQtyTouchField(
            controller: usedCtrl,
            canEdit: canEdit,
            onChanged: onChanged,
          ),
        ),
        // 6: Còn lại cuối ca
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            formatQty(remaining),
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2563EB),
            ),
          ),
        ),
        // 7: Kiểm thực tế (+/-)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: _buildQtyTouchField(
            controller: countCtrl,
            canEdit: canEdit,
            onChanged: onChanged,
          ),
        ),
        // 8: Độ lệch
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            '${diff > 0.001 ? "+" : ""}${formatQty(diff)}',
            textAlign: TextAlign.right,
            style: TextStyle(
                fontWeight: FontWeight.w800, color: diffColor, fontSize: 13),
          ),
        ),
        // 9: Trạng thái & Lý do
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (isLowStock) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '≤ Min',
                        style: TextStyle(
                          color: Color(0xFFDC2626),
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              if (canEdit)
                SizedBox(
                  height: 32,
                  child: TextField(
                    controller: reasonCtrl,
                    style: const TextStyle(fontSize: 11),
                    decoration: const InputDecoration(
                      hintText: 'Lý do lệch...',
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                )
              else
                Text(
                  reasonCtrl.text.isNotEmpty ? reasonCtrl.text : '—',
                  style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQtyTouchField({
    required TextEditingController controller,
    required bool canEdit,
    required VoidCallback onChanged,
  }) {
    if (!canEdit) {
      return Center(
        child: Text(
          controller.text.isEmpty ? '0' : controller.text,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        InkWell(
          onTap: () {
            final cur = double.tryParse(controller.text.trim()) ?? 0.0;
            if (cur > 0) {
              final next = cur - 1;
              controller.text = next == next.roundToDouble()
                  ? next.toInt().toString()
                  : next.toStringAsFixed(1);
              onChanged();
            }
          },
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(Icons.remove, size: 13),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 48,
          height: 32,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            onChanged: (_) => onChanged(),
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 4),
        InkWell(
          onTap: () {
            final cur = double.tryParse(controller.text.trim()) ?? 0.0;
            final next = cur + 1;
            controller.text = next == next.roundToDouble()
                ? next.toInt().toString()
                : next.toStringAsFixed(1);
            onChanged();
          },
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(Icons.add, size: 13),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_InventoryData>(
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
        final canManageCatalog = RoleVisibility.canManageCatalog(
          RoleVisibility.rolesOf(SessionScope.maybeOf(context)?.user),
        );
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;

        final totalQuantity = data.balances.fold<double>(
          0,
          (sum, b) => sum + (double.tryParse(b.quantity) ?? 0),
        );

        final isCompact = MediaQuery.sizeOf(context).width < 720;
        final isShiftOnly = widget.mode == InventoryTabMode.shiftWork;
        final isStockOnly = widget.mode == InventoryTabMode.stock;

        final headerTitle = isShiftOnly
            ? 'Quản Lý Ca Làm Việc & Kiểm Kê Ca Pha Chế'
            : 'Quản Lý Nhập Xuất Tồn Nguyên Vật Liệu';
        final headerSubtitle = isShiftOnly
            ? 'Kiểm kê đầu ca, chốt số liệu cuối ca và đối chiếu chênh lệch định lượng nguyên liệu'
            : 'Theo dõi nguyên liệu theo ca, định mức tồn và chênh lệch kiểm kê';

        final headerActions = <Widget>[
          if (isShiftOnly)
            FilledButton.icon(
              key: const Key('btn-open-shift-stocktake'),
              onPressed: () => _showCreateStocktakeDialog(data.locations),
              icon: const Icon(Icons.add_task_rounded, size: 18),
              label: const Text('Mở Đợt Kiểm Kê Mới'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0891B2),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            )
          else ...[
            if (canManageCatalog) ...[
              OutlinedButton.icon(
                key: const Key('btn-add-item'),
                onPressed: () => _showCreateItemDialog(),
                icon: const Icon(Icons.add_box_outlined, size: 18),
                label: const Text('Thêm mặt hàng'),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              OutlinedButton.icon(
                key: const Key('btn-import-items'),
                onPressed: () => _showImportItemsDialog(data.items),
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: const Text('Import mặt hàng'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF059669),
                  side: const BorderSide(color: Color(0xFF059669)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
            FilledButton.icon(
              key: const Key('btn-create-stock-request'),
              onPressed: () {
                if (widget.onCreateStockRequest != null) {
                  widget.onCreateStockRequest!();
                } else if (widget.onNavigate != null) {
                  widget.onNavigate!(3);
                }
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Lập phiếu kho mới'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ];

        Widget headerWidget = isCompact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    headerTitle,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    headerSubtitle,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                  if (headerActions.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: headerActions,
                    ),
                  ],
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          headerTitle,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          headerSubtitle,
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (headerActions.isNotEmpty) ...[
                    const SizedBox(width: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: headerActions,
                    ),
                  ],
                ],
              );

        final pendingCount = data.stocktakes
            .where((s) => s.status == 'submitted' || s.status == 'open')
            .length;
        final approvedCount = data.stocktakes
            .where((s) => s.status == 'approved' || s.status == 'completed')
            .length;

        final List<Widget> kpiCards;
        if (isShiftOnly) {
          kpiCards = [
            _buildKpiCard(
              context,
              title: 'CA VẬN HÀNH',
              value: 'Sáng • Chiều • Tối',
              subtitle: 'Theo lịch phân bổ quầy',
              icon: Icons.schedule_rounded,
              color: const Color(0xFF2563EB),
            ),
            _buildKpiCard(
              context,
              title: 'TỔNG ĐỢT KIỂM KÊ',
              value: '${data.stocktakes.length} đợt',
              subtitle: 'Đã lập trong hệ thống',
              icon: Icons.checklist_rounded,
              color: const Color(0xFF0891B2),
            ),
            _buildKpiCard(
              context,
              title: 'CHỜ DUYỆT ĐỐI SOÁT',
              value: '$pendingCount phiếu',
              subtitle: 'Maker-Checker kiểm đếm',
              icon: Icons.pending_actions_rounded,
              color: const Color(0xFFF59E0B),
            ),
            _buildKpiCard(
              context,
              title: 'ĐÃ DUYỆT HOÀN TẤT',
              value: '$approvedCount phiếu',
              subtitle: 'Khớp số liệu tồn kho',
              icon: Icons.verified_rounded,
              color: const Color(0xFF059669),
            ),
          ];
        } else {
          kpiCards = [
            _buildKpiCard(
              context,
              title: 'TỔNG LƯỢNG TỒN KHO',
              value: '${AppFormat.intFormat(totalQuantity.round())} đơn vị',
              subtitle: 'Định mức khả dụng an toàn',
              icon: Icons.inventory_2_rounded,
              color: const Color(0xFF2563EB),
            ),
            _buildKpiCard(
              context,
              title: 'CHỦNG LOẠI NGUYÊN LIỆU',
              value: '${data.items.length} loại vật tư',
              subtitle: 'Trà, bột sữa, topping và bao bì',
              icon: Icons.category_rounded,
              color: const Color(0xFF0891B2),
            ),
            _buildKpiCard(
              context,
              title: 'ĐIỂM LƯU KHO',
              value: '${data.locations.length} khu vực kho',
              subtitle: 'Kho quầy và kho trung tâm',
              icon: Icons.warehouse_rounded,
              color: const Color(0xFF059669),
            ),
            _buildKpiCard(
              context,
              title: 'MỤC CẦN KIỂM KÊ',
              value: '${data.items.length} mặt hàng',
              subtitle: 'Đối chiếu tồn lý thuyết và thực tế',
              icon: Icons.qr_code_2_rounded,
              color: const Color(0xFF7C3AED),
            ),
          ];
        }

        Widget kpiWidget = isCompact
            ? Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: kpiCards[0]),
                      const SizedBox(width: 12),
                      Expanded(child: kpiCards[1]),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: kpiCards[2]),
                      const SizedBox(width: 12),
                      Expanded(child: kpiCards[3]),
                    ],
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(child: kpiCards[0]),
                  const SizedBox(width: 14),
                  Expanded(child: kpiCards[1]),
                  const SizedBox(width: 14),
                  Expanded(child: kpiCards[2]),
                  const SizedBox(width: 14),
                  Expanded(child: kpiCards[3]),
                ],
              );

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              headerWidget,
              const SizedBox(height: 20),

              if (!isShiftOnly && data.lowStockAlerts.isNotEmpty) ...[
                _buildLowStockAlertBanner(context, data.lowStockAlerts),
                const SizedBox(height: 20),
              ],

              if (!isShiftOnly && data.expiryAlerts.isNotEmpty) ...[
                _buildExpiryAlertBanner(context, data.expiryAlerts),
                const SizedBox(height: 20),
              ],

              kpiWidget,
              const SizedBox(height: 24),

              if (!isShiftOnly) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Danh mục mặt hàng',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (canManageCatalog && data.items.isNotEmpty)
                      if (!_isSelectionMode)
                        OutlinedButton.icon(
                          key: const Key('btn-toggle-batch-select'),
                          icon: const Icon(Icons.checklist_rounded, size: 16),
                          label: const Text('Chọn nhiều'),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: _toggleSelectionMode,
                        )
                      else
                        TextButton.icon(
                          key: const Key('btn-close-batch-select'),
                          icon: const Icon(Icons.close, size: 16),
                          label: const Text('Hủy chọn'),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: _toggleSelectionMode,
                        ),
                  ],
                ),
                const SizedBox(height: 8),

                if (_isSelectionMode && data.items.isNotEmpty) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF2563EB).withValues(alpha: 0.25),
                      ),
                    ),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              key: const Key('checkbox-select-all'),
                              value: _selectedItemIds.length == data.items.length && data.items.isNotEmpty,
                              onChanged: (val) {
                                if (val == true) {
                                  _selectAllItems(data.items);
                                } else {
                                  _clearSelection();
                                }
                              },
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Đã chọn ${_selectedItemIds.length}/${data.items.length}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            TextButton(
                              key: const Key('btn-select-all-items'),
                              onPressed: () => _selectAllItems(data.items),
                              child: const Text('Chọn tất cả', style: TextStyle(fontSize: 12.5)),
                            ),
                            TextButton(
                              key: const Key('btn-clear-selection'),
                              onPressed: _clearSelection,
                              child: const Text('Bỏ chọn', style: TextStyle(fontSize: 12.5)),
                            ),
                            FilledButton.icon(
                              key: const Key('btn-batch-delete-confirm'),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.red,
                                visualDensity: VisualDensity.compact,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: const Icon(Icons.delete_outline, size: 16),
                              label: Text(
                                _selectedItemIds.isEmpty
                                    ? 'Xóa đã chọn'
                                    : 'Xóa (${_selectedItemIds.length})',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              onPressed: _selectedItemIds.isEmpty
                                  ? null
                                  : () => _confirmDeleteItemsBatch(data.items, data.balances),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],

              if (data.items.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 48,
                            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Chưa có mặt hàng nào trong kho',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            canManageCatalog
                                ? 'Bạn có thể import nhanh 19 mặt hàng mẫu chuẩn quán trà sữa hoặc thêm thủ công từng món.'
                                : 'Người quản lý kho có thể thêm mặt hàng hoặc import danh mục nguyên vật liệu.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (canManageCatalog) ...[
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 12,
                              runSpacing: 10,
                              alignment: WrapAlignment.center,
                              children: [
                                FilledButton.icon(
                                  key: const Key('btn-empty-import-sample'),
                                  onPressed: () => _showImportItemsDialog(data.items),
                                  icon: const Icon(Icons.download_for_offline_outlined, size: 18),
                                  label: const Text('Import 19 mẫu Trà Sữa / File'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF059669),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  key: const Key('btn-empty-add-item'),
                                  onPressed: () => _showCreateItemDialog(),
                                  icon: const Icon(Icons.add, size: 18),
                                  label: const Text('Thêm thủ công'),
                                  style: OutlinedButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (final item in data.items)
                        ListTile(
                          leading: _isSelectionMode
                              ? Checkbox(
                                  key: Key('checkbox-item-${item.sku}'),
                                  value: _selectedItemIds.contains(item.id),
                                  onChanged: (_) => _toggleItemSelection(item.id),
                                )
                              : null,
                          onTap: _isSelectionMode
                              ? () => _toggleItemSelection(item.id)
                              : null,
                          title: Text(item.name),
                          subtitle: Text(
                              '${item.sku} · ${item.category ?? 'Chưa phân nhóm'} · ${item.unit}${item.packaging == null ? '' : ' · ${item.packaging}'}'),
                          trailing: canManageCatalog
                              ? (_isSelectionMode
                                  ? null
                                  : (isCompact
                                      ? PopupMenuButton<String>(
                                          key: Key('menu-item-${item.sku}'),
                                          icon: const Icon(Icons.more_vert, size: 20),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          itemBuilder: (ctx) => [
                                            const PopupMenuItem(
                                              value: 'levels',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.tune_outlined,
                                                      size: 16,
                                                      color: Color(0xFF2563EB)),
                                                  SizedBox(width: 8),
                                                  Text('Định mức tồn'),
                                                ],
                                              ),
                                            ),
                                            const PopupMenuItem(
                                              value: 'edit',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.edit_outlined,
                                                      size: 16),
                                                  SizedBox(width: 8),
                                                  Text('Sửa thông tin'),
                                                ],
                                              ),
                                            ),
                                            PopupMenuItem(
                                              key: Key('btn-delete-item-${item.sku}'),
                                              value: 'delete',
                                              child: const Row(
                                                children: [
                                                  Icon(Icons.delete_outline,
                                                      size: 16,
                                                      color: Colors.red),
                                                  SizedBox(width: 8),
                                                  Text('Xóa mặt hàng',
                                                      style: TextStyle(
                                                          color: Colors.red)),
                                                ],
                                              ),
                                            ),
                                          ],
                                          onSelected: (val) {
                                            if (val == 'levels') {
                                              _showSetStockLevelDialog(
                                                  item,
                                                  data.locations,
                                                  data.stockLevels);
                                            } else if (val == 'edit') {
                                              _showEditItemDialog(item);
                                            } else if (val == 'delete') {
                                              _confirmDeleteItem(
                                                  item, data.balances);
                                            }
                                          },
                                        )
                                      : Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              tooltip:
                                                  'Định mức tồn (Min / Max)',
                                              icon: const Icon(
                                                  Icons.tune_outlined,
                                                  color: Color(0xFF2563EB)),
                                              onPressed: () =>
                                                  _showSetStockLevelDialog(
                                                      item,
                                                      data.locations,
                                                      data.stockLevels),
                                            ),
                                            IconButton(
                                              key: Key(
                                                  'btn-edit-item-${item.sku}'),
                                              tooltip: 'Sửa mặt hàng',
                                              icon: const Icon(
                                                  Icons.edit_outlined),
                                              onPressed: () =>
                                                  _showEditItemDialog(item),
                                            ),
                                            IconButton(
                                              key: Key(
                                                  'btn-delete-item-${item.sku}'),
                                              tooltip: 'Xóa mặt hàng',
                                              icon: const Icon(
                                                  Icons.delete_outline,
                                                  color: Colors.red),
                                              onPressed: () =>
                                                  _confirmDeleteItem(
                                                      item, data.balances),
                                            ),
                                          ],
                                        )))
                              : null,
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),

              // Bảng Tồn kho vật tư
              Text(
                'Chi Tiết Tồn Kho Theo Nguyên Vật Liệu',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color:
                        theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: data.balances.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: Text('Không có dữ liệu tồn kho.')),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: data.balances.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final bal = data.balances[i];
                          // Match Item
                          final item =
                              data.items.cast<InventoryItem?>().firstWhere(
                                    (it) => it?.id == bal.itemId,
                                    orElse: () => null,
                                  );
                          // Match Location
                          final loc = data.locations
                              .cast<InventoryLocation?>()
                              .firstWhere(
                                (l) => l?.id == bal.locationId,
                                orElse: () => null,
                              );

                          final itemName = item?.name ?? 'Vật tư ${bal.itemId}';
                          final locName = loc != null
                              ? '${loc.code} — ${loc.name}'
                              : bal.locationId;
                          final unit = item?.unit ?? 'đơn vị';

                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 14),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2563EB)
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.file_copy_rounded,
                                    size: 20,
                                    color: Color(0xFF2563EB),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        itemName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        'Điểm lưu kho: $locName • SKU: ${item?.sku ?? "N/A"}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Wrap(
                                  spacing: 12,
                                  alignment: WrapAlignment.end,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '${AppFormat.number(bal.quantity)} $unit',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const Text('Sổ sách',
                                            style: TextStyle(
                                                fontSize: 10.5,
                                                color: Colors.grey)),
                                      ],
                                    ),
                                    if (bal.reservedNumber > 0)
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            '${AppFormat.number(bal.reservedQuantity)} $unit',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                              color: Color(0xFFD97706),
                                            ),
                                          ),
                                          const Text('Đặt trước',
                                              style: TextStyle(
                                                  fontSize: 10.5,
                                                  color: Color(0xFFD97706))),
                                        ],
                                      ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '${AppFormat.number(bal.availableNumber.toString())} $unit',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 16,
                                            color: Color(0xFF059669),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF10B981)
                                                .withValues(alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'Khả dụng',
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
                                if (item != null && canManageCatalog) ...[
                                  const SizedBox(width: 8),
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert, size: 18),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    itemBuilder: (ctx) => [
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Row(
                                          children: [
                                            Icon(Icons.edit_outlined, size: 16),
                                            SizedBox(width: 8),
                                            Text('Sửa thông tin'),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete_outline,
                                                size: 16, color: Colors.red),
                                            SizedBox(width: 8),
                                            Text('Xóa mặt hàng',
                                                style: TextStyle(
                                                    color: Colors.red)),
                                          ],
                                        ),
                                      ),
                                    ],
                                    onSelected: (v) {
                                      if (v == 'edit')
                                        _showEditItemDialog(item);
                                      if (v == 'delete')
                                        _confirmDeleteItem(item, data.balances);
                                    },
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 24),

              // Bảng Quản lý Serial & Tài sản bảo mật
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Dải Số Serial Phôi Bảo Mật (Serial Tracking)',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${data.assets.length} bản ghi theo dõi',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color:
                        theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: data.assets.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                            child:
                                Text('Không có dải serial nào được quản lý.')),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: data.assets.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final a = data.assets[i];
                          final loc = data.locations
                              .cast<InventoryLocation?>()
                              .firstWhere(
                                (l) => l?.id == a.locationId,
                                orElse: () => null,
                              );
                          return InkWell(
                            key: Key('btn-asset-detail-${a.serial}'),
                            onTap: () => _showAssetLifecycleDialog(a, data),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              child: Row(
                                children: [
                                  const Icon(Icons.qr_code,
                                      size: 20, color: Color(0xFF7C3AED)),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          a.serial,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13.5,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                        Text(
                                          'Kho: ${loc?.name ?? a.locationId}${a.assignee != null ? " • Người phụ trách: ${a.assignee}" : ""}',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: theme
                                                .colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981)
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      a.status.name.toUpperCase(),
                                      style: const TextStyle(
                                        color: Color(0xFF059669),
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.chevron_right,
                                      size: 18, color: Colors.grey),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 24),
            ],
            if (!isStockOnly) ...[
              _buildStocktakesSection(context, data),
            ],
          ],
          ),
        );
      },
    );
  }

  Widget _buildLowStockAlertBanner(
      BuildContext context, List<LowStockAlertItem> alerts) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF451A1A) : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFDC2626), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cảnh Báo Thiếu Tồn Kho Định Mức (${alerts.length} mặt hàng)',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: Color(0xFFDC2626)),
                    ),
                    Text(
                      'Số lượng tồn thực tế đang dưới định mức an toàn tối thiểu. Đề xuất Maker lập phiếu bổ sung kho kịp thời.',
                      style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Column(
            children: alerts.map((al) {
              final isEmpty = al.status == 'empty';
              final isNarrow = MediaQuery.sizeOf(context).width < 600;

              if (isNarrow) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2D1515) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isEmpty ? Colors.red : Colors.orange,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isEmpty ? 'HẾT HÀNG' : 'SẮP THIẾU',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          FilledButton.tonal(
                            onPressed: () {
                              if (widget.onCreateStockRequest != null) {
                                widget.onCreateStockRequest!();
                              } else if (widget.onNavigate != null) {
                                widget.onNavigate!(3);
                              }
                            },
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('Bổ Sung Ngay',
                                style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('${al.itemName} (${al.sku})',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 2),
                      Text(
                        'Kho: ${al.locationName} • Tồn: ${al.currentQty} ${al.unit} / Định mức: ${al.minQty} (Thiếu: ${al.deficit})',
                        style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                );
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2D1515) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isEmpty ? Colors.red : Colors.orange,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isEmpty ? 'HẾT HÀNG' : 'SẮP THIẾU',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${al.itemName} (${al.sku})',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13)),
                          Text(
                            'Kho: ${al.locationName} • Tồn: ${al.currentQty} ${al.unit} / Định mức: ${al.minQty} (Thiếu: ${al.deficit})',
                            style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonal(
                      onPressed: () {
                        if (widget.onCreateStockRequest != null) {
                          widget.onCreateStockRequest!();
                        } else if (widget.onNavigate != null) {
                          widget.onNavigate!(3);
                        }
                      },
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Bổ Sung Ngay',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildStocktakesSection(BuildContext context, _InventoryData data) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final isCompact = MediaQuery.sizeOf(context).width < 650;
    final header = isCompact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Kiểm Kê Kho Định Kỳ & Đối Soát Chênh Lệch',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Kiểm đếm thực tế, đối chiếu sổ sách và tự động sinh phiếu điều chỉnh Maker-Checker',
                style: TextStyle(
                    fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () => _showCreateStocktakeDialog(data.locations),
                icon: const Icon(Icons.add_task_rounded, size: 16),
                label: const Text('Mở Đợt Kiểm Kê Mới'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0891B2),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kiểm Kê Kho Định Kỳ & Đối Soát Chênh Lệch',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Kiểm đếm thực tế, đối chiếu sổ sách và tự động sinh phiếu điều chỉnh Maker-Checker',
                      style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => _showCreateStocktakeDialog(data.locations),
                icon: const Icon(Icons.add_task_rounded, size: 16),
                label: const Text('Mở Đợt Kiểm Kê Mới'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0891B2),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: 12),
        _buildShiftStocktakeDesk(data),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: data.stocktakes.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                        'Chưa có đợt kiểm kê nào. Bấm "Mở Đợt Kiểm Kê Mới" để bắt đầu kiểm kê.'),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: data.stocktakes.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final st = data.stocktakes[i];
                    final loc =
                        data.locations.cast<InventoryLocation?>().firstWhere(
                              (l) => l?.id == st.locationId,
                              orElse: () => null,
                            );
                    final locName = loc != null
                        ? '${loc.code} — ${loc.name}'
                        : st.locationId;

                    Color badgeColor;
                    String statusText;
                    if (st.status == 'open') {
                      badgeColor = const Color(0xFF2563EB);
                      statusText = 'Đang kiểm đếm (Open)';
                    } else if (st.status == 'submitted') {
                      badgeColor = const Color(0xFFD97706);
                      statusText = 'Chờ Checker duyệt (Submitted)';
                    } else {
                      badgeColor = const Color(0xFF059669);
                      statusText = 'Đã hoàn tất (Closed)';
                    }

                    final contentColumn = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'Kho: $locName',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: badgeColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                statusText,
                                style: TextStyle(
                                    color: badgeColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Ghi chú: ${st.note ?? "Kiểm kê kho"} • Ngày tạo: ${st.createdAt.toLocal().toString().substring(0, 16)}',
                          style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                        if (st.adjustmentRequestId != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '⚡ Phiếu điều chỉnh tự động: #${st.adjustmentRequestId}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF059669)),
                            ),
                          ),
                      ],
                    );

                    final actionBtn = OutlinedButton.icon(
                      onPressed: () => _showStocktakeDetailDialog(
                          st, data.items, data.locations,
                          stockLevels: data.stockLevels),
                      icon: const Icon(Icons.edit_note_rounded, size: 16),
                      label: Text(st.status == 'open'
                          ? 'Nhập Số Đếm'
                          : 'Xem Chi Tiết'),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    );

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      child: isCompact
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: badgeColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(Icons.assignment_outlined,
                                          size: 20, color: badgeColor),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(child: contentColumn),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: actionBtn,
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: badgeColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(Icons.assignment_outlined,
                                      size: 20, color: badgeColor),
                                ),
                                const SizedBox(width: 16),
                                Expanded(child: contentColumn),
                                const SizedBox(width: 12),
                                actionBtn,
                              ],
                            ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildShiftStocktakeDesk(_InventoryData data) {
    final activeStocktake = data.stocktakes.cast<StocktakeItem?>().firstWhere(
          (stocktake) => stocktake?.status == 'open',
          orElse: () => null,
        );
    final lines = data.items.map((item) {
      final balance = data.balances.cast<StockBalance?>().firstWhere(
            (value) => value?.itemId == item.id,
            orElse: () => null,
          );
      final savedLine =
          activeStocktake?.lines.cast<StocktakeLineItem?>().firstWhere(
                (value) => value?.itemId == item.id,
                orElse: () => null,
              );
      final opening = balance?.qtyNumber ?? 0;
      return ShiftStocktakeLine(
        name: item.name,
        unit: item.unit,
        openingQty: opening,
        receivedQty: 0,
        usedQty: double.tryParse(savedLine?.usedQty ?? '') ?? 0,
        countedQty: double.tryParse(savedLine?.countedQty ?? '') ?? opening,
        reason: savedLine?.reason ?? '',
      );
    }).toList();

    return ShiftStocktakeDesk(
      lines: lines,
      onStartShiftStocktake: () {
        if (activeStocktake != null) {
          _showStocktakeDetailDialog(
            activeStocktake,
            data.items,
            data.locations,
            stockLevels: data.stockLevels,
          );
        } else {
          _showCreateStocktakeDialog(data.locations);
        }
      },
    );
  }

  Widget _buildExpiryAlertBanner(
      BuildContext context, List<ExpiryAlertItem> alerts) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final criticalCount = alerts.where((a) => a.daysLeft <= 0).length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF3B2010) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: criticalCount > 0
              ? const Color(0xFFEF4444).withValues(alpha: 0.4)
              : const Color(0xFFF59E0B).withValues(alpha: 0.4),
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
                  color: (criticalCount > 0 ? Colors.red : Colors.amber)
                      .withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  criticalCount > 0
                      ? Icons.warning_rounded
                      : Icons.schedule_rounded,
                  color: criticalCount > 0
                      ? const Color(0xFFDC2626)
                      : const Color(0xFFD97706),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cảnh Báo Hạn Sử Dụng Nguyên Liệu (${alerts.length} lô hàng cận/hết date)',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: criticalCount > 0
                            ? const Color(0xFFDC2626)
                            : const Color(0xFFB45309),
                      ),
                    ),
                    Text(
                      'Kiểm tra và ưu tiên xuất pha chế trước (FEFO) hoặc lập phiếu hủy hỏng nếu đã hết hạn.',
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
          const SizedBox(height: 12),
          Column(
            children: alerts.map((al) {
              final isExpired = al.daysLeft <= 0;
              final isWarning = al.daysLeft <= 3 && !isExpired;
              final isNarrow = MediaQuery.sizeOf(context).width < 600;

              final badgeColor = isExpired
                  ? const Color(0xFFDC2626)
                  : (isWarning
                      ? const Color(0xFFD97706)
                      : const Color(0xFF2563EB));
              final badgeText = isExpired
                  ? (al.daysLeft == 0
                      ? 'HẾT HẠN HÔM NAY'
                      : 'QUÁ HẠN ${-al.daysLeft} NGÀY')
                  : (isWarning
                      ? 'CẬN DATE (CÒN ${al.daysLeft} NGÀY)'
                      : 'THEO DÕI (CÒN ${al.daysLeft} NGÀY)');

              if (isNarrow) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF291B12) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: badgeColor.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: badgeColor,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              badgeText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (isWarning)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Ưu tiên dùng',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFB45309),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${al.itemName} (${al.sku})',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Lô: ${al.lotNo ?? "N/A"} • HSD: ${al.expiryDate} • Số lượng: ${al.quantity} ${al.unit}',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (isExpired) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.tonal(
                            onPressed: () {
                              if (widget.onCreateStockRequest != null) {
                                widget.onCreateStockRequest!();
                              } else if (widget.onNavigate != null) {
                                widget.onNavigate!(3);
                              }
                            },
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              backgroundColor: const Color(0xFFDC2626)
                                  .withValues(alpha: 0.15),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('Lập Phiếu Hủy',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFFDC2626),
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF291B12) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: badgeColor.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        badgeText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${al.itemName} (${al.sku})',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          Text(
                            'Lô: ${al.lotNo ?? "N/A"} • HSD: ${al.expiryDate} • Số lượng: ${al.quantity} ${al.unit}',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isExpired)
                      FilledButton.tonal(
                        onPressed: () {
                          if (widget.onCreateStockRequest != null) {
                            widget.onCreateStockRequest!();
                          } else if (widget.onNavigate != null) {
                            widget.onNavigate!(3);
                          }
                        },
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          backgroundColor:
                              const Color(0xFFDC2626).withValues(alpha: 0.15),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Lập Phiếu Hủy',
                            style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFFDC2626),
                                fontWeight: FontWeight.bold)),
                      )
                    else if (isWarning)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFFF59E0B).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Ưu tiên dùng',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFB45309),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard(
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
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
              fontSize: 18,
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

  Future<_InventoryData> _load(BankOpsRepository repo) async {
    final results = await Future.wait([
      repo.getLocations(),
      repo.getItems(),
      repo.getBalances(),
      repo.getAssets(),
      repo.getLowStockAlerts(),
      repo.getStocktakes(),
      repo.getStockLevels(),
      repo.getExpiryAlerts(days: 7),
    ]);
    return _InventoryData(
      locations: results[0] as List<InventoryLocation>,
      items: results[1] as List<InventoryItem>,
      balances: results[2] as List<StockBalance>,
      assets: results[3] as List<AssetRecord>,
      lowStockAlerts: results[4] as List<LowStockAlertItem>,
      stocktakes: results[5] as List<StocktakeItem>,
      stockLevels: results[6] as List<StockLevelItem>,
      expiryAlerts: results[7] as List<ExpiryAlertItem>,
    );
  }
}

class _InventoryData {
  const _InventoryData({
    required this.locations,
    required this.items,
    required this.balances,
    required this.assets,
    required this.lowStockAlerts,
    required this.stocktakes,
    required this.stockLevels,
    this.expiryAlerts = const [],
  });

  final List<InventoryLocation> locations;
  final List<InventoryItem> items;
  final List<StockBalance> balances;
  final List<AssetRecord> assets;
  final List<LowStockAlertItem> lowStockAlerts;
  final List<StocktakeItem> stocktakes;
  final List<StockLevelItem> stockLevels;
  final List<ExpiryAlertItem> expiryAlerts;
}
