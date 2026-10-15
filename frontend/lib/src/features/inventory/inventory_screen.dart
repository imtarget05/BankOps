import 'package:flutter/material.dart';

import '../../app/app_shell.dart';
import '../../core/util/formatting.dart';
import '../../core/util/role_visibility.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/dtos.dart';
import '../../data/repositories/bankops_repository.dart';

/// Màn quản lý nguyên vật liệu cho quán trà sữa.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({
    super.key,
    this.onNavigate,
    this.onCreateStockRequest,
  });

  final ValueChanged<int>? onNavigate;
  final VoidCallback? onCreateStockRequest;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  Future<_InventoryData>? _future;

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

  Future<void> _showCreateItemDialog() async {
    final skuCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final unitCtrl = TextEditingController(text: 'Gói');
    final categoryCtrl = TextEditingController();
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
                    labelText: 'Mã SKU *',
                    hintText: 'Ví dụ: TRA-OLONG-500G',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tên nguyên vật liệu *',
                    hintText: 'Ví dụ: Trà ô long',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: unitCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Đơn Vị Tính',
                    hintText: 'Gói / Túi / Kg / Hộp / Viên',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: categoryCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Nhóm nguyên liệu',
                      hintText: 'Ví dụ: Nhóm Trà',
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
                if (skuCtrl.text.trim().isEmpty || nameCtrl.text.trim().isEmpty)
                  return;
                Navigator.of(ctx).pop(true);
              },
              child: const Text('Thêm mới'),
            ),
          ],
        ),
      ),
    );

    if (ok == true && mounted) {
      try {
        final repo = RepositoryScope.of(context);
        await repo.createItem(
          sku: skuCtrl.text.trim(),
          name: nameCtrl.text.trim(),
          unit: unitCtrl.text.trim().isEmpty ? 'Cái' : unitCtrl.text.trim(),
          trackedSerial: false,
          category: categoryCtrl.text.trim(),
          packaging: packagingCtrl.text.trim(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Đã thêm mặt hàng "${nameCtrl.text.trim()}" thành công!'),
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

  Future<void> _confirmDeleteItem(InventoryItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Xác nhận xóa mặt hàng',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
            'Bạn có chắc chắn muốn xóa mặt hàng "${item.name}" (SKU: ${item.sku}) không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Xóa vĩnh viễn'),
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
                                label: const Text('Bàn giao ấn chỉ'),
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
                                          'Chưa có lịch sử luân chuyển cho ấn chỉ này.'))
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
                    AppToast.success(context, 'Bàn giao ấn chỉ thành công!');
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
    List<InventoryLocation> locations,
  ) async {
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
    final reasonCtrls = <String, TextEditingController>{};

    for (final it in items) {
      final existingLine =
          stocktake.lines.cast<StocktakeLineItem?>().firstWhere(
                (l) => l?.itemId == it.id,
                orElse: () => null,
              );
      countCtrls[it.id] = TextEditingController(
        text: existingLine != null ? existingLine.countedQty : '0',
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
                        '${stocktake.shiftCode == 'morning' ? 'Ca Sáng 07:30 – 15:00' : stocktake.shiftCode == 'afternoon' ? 'Ca Chiều 15:00 – 23:00' : stocktake.shiftCode == 'split' ? 'Ca Lỡ ngày 07:30 – 18:00' : 'Kiểm kê kho'}: $locName',
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
              width: 700,
              height: 480,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (stocktake.note != null && stocktake.note!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text('Ghi chú: ${stocktake.note}',
                            style:
                                const TextStyle(fontStyle: FontStyle.italic)),
                      ),
                    if (stocktake.shiftCode != null)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Còn lại cuối ca = (Tồn đầu ca + Nhập hàng) − Sử dụng. Độ lệch = Kiểm kê thực tế − Còn lại cuối ca.',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600),
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
                        0: FlexColumnWidth(3),
                        1: FlexColumnWidth(1.5),
                        2: FlexColumnWidth(1.8),
                        3: FlexColumnWidth(1.5),
                        4: FlexColumnWidth(2.5),
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
                                child: Text('Mặt hàng',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12))),
                            Padding(
                                padding: EdgeInsets.all(8),
                                child: Text('Sổ sách',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12))),
                            Padding(
                                padding: EdgeInsets.all(8),
                                child: Text('Thực đếm',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12))),
                            Padding(
                                padding: EdgeInsets.all(8),
                                child: Text('Chênh lệch',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12))),
                            Padding(
                                padding: EdgeInsets.all(8),
                                child: Text('Lý do',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12))),
                          ],
                        ),
                        for (final it in items)
                          _buildStocktakeRow(
                            stocktake: stocktake,
                            item: it,
                            canEdit: canEdit,
                            countCtrl: countCtrls[it.id]!,
                            reasonCtrl: reasonCtrls[it.id]!,
                            onChanged: () => setDlgState(() {}),
                          ),
                      ],
                    ),
                  ],
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
                      final linesPayload = items
                          .map((it) => {
                                'item_id': it.id,
                                'counted_qty':
                                    countCtrls[it.id]?.text.trim() ?? '0',
                                'reason': reasonCtrls[it.id]?.text.trim() ?? '',
                              })
                          .toList();
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
                      final linesPayload = items
                          .map((it) => {
                                'item_id': it.id,
                                'counted_qty':
                                    countCtrls[it.id]?.text.trim() ?? '0',
                                'reason': reasonCtrls[it.id]?.text.trim() ?? '',
                              })
                          .toList();
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
    required StocktakeItem stocktake,
    required InventoryItem item,
    required bool canEdit,
    required TextEditingController countCtrl,
    required TextEditingController reasonCtrl,
    required VoidCallback onChanged,
  }) {
    final line = stocktake.lines.cast<StocktakeLineItem?>().firstWhere(
          (l) => l?.itemId == item.id,
          orElse: () => null,
        );
    final bookQty = double.tryParse(line?.bookQty ?? '0') ?? 0.0;
    final countedQty = double.tryParse(countCtrl.text) ?? 0.0;
    final diff = countedQty - bookQty;

    Color diffColor = Colors.grey;
    if (diff > 0) diffColor = Colors.green;
    if (diff < 0) diffColor = Colors.red;

    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
              Text(item.sku,
                  style: const TextStyle(color: Colors.grey, fontSize: 11)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text('${line?.bookQty ?? '0'} ${item.unit}',
              style: const TextStyle(fontSize: 13)),
        ),
        Padding(
          padding: const EdgeInsets.all(6),
          child: canEdit
              ? SizedBox(
                  height: 36,
                  child: TextField(
                    controller: countCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => onChanged(),
                    decoration: const InputDecoration(
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      border: OutlineInputBorder(),
                    ),
                  ),
                )
              : Text('${countCtrl.text} ${item.unit}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold)),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            '${diff > 0 ? "+" : ""}${diff.toStringAsFixed(0)}',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: diffColor, fontSize: 13),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(6),
          child: canEdit
              ? SizedBox(
                  height: 36,
                  child: TextField(
                    controller: reasonCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Lý do lệch...',
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      border: OutlineInputBorder(),
                    ),
                  ),
                )
              : Text(reasonCtrl.text.isNotEmpty ? reasonCtrl.text : '—',
                  style: const TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_InventoryData>(
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
        final canManageCatalog = RoleVisibility.canManageCatalog(
          RoleVisibility.rolesOf(SessionScope.maybeOf(context)?.user),
        );
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;

        final totalQuantity = data.balances.fold<double>(
          0,
          (sum, b) => sum + (double.tryParse(b.quantity) ?? 0),
        );

        return RefreshIndicator(
          onRefresh: _refresh,
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
                          'Quản Lý Nhập Xuất Tồn Nguyên Vật Liệu',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Theo dõi nguyên liệu theo ca, định mức tồn và chênh lệch kiểm kê',
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
                    runSpacing: 8,
                    children: [
                      if (canManageCatalog)
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
                  ),
                ],
              ),
              const SizedBox(height: 20),

              if (data.lowStockAlerts.isNotEmpty) ...[
                _buildLowStockAlertBanner(context, data.lowStockAlerts),
                const SizedBox(height: 20),
              ],

              // KPI Strip
              Row(
                children: [
                  Expanded(
                    child: _buildKpiCard(
                      context,
                      title: 'TỔNG LƯỢNG TỒN KHO',
                      value:
                          '${AppFormat.intFormat(totalQuantity.round())} đơn vị',
                      subtitle: 'Định mức khả dụng an toàn',
                      icon: Icons.inventory_2_rounded,
                      color: const Color(0xFF2563EB),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildKpiCard(
                      context,
                      title: 'CHỦNG LOẠI NGUYÊN LIỆU',
                      value: '${data.items.length} loại vật tư',
                      subtitle: 'Trà, bột sữa, topping và bao bì',
                      icon: Icons.category_rounded,
                      color: const Color(0xFF0891B2),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildKpiCard(
                      context,
                      title: 'ĐIỂM LƯU KHO',
                      value: '${data.locations.length} kho quỹ',
                      subtitle: 'Kho quầy và kho trung tâm',
                      icon: Icons.warehouse_rounded,
                      color: const Color(0xFF059669),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildKpiCard(
                      context,
                      title: 'MỤC CẦN KIỂM KÊ',
                      value: '${data.items.length} mặt hàng',
                      subtitle: 'Đối chiếu tồn lý thuyết và thực tế',
                      icon: Icons.qr_code_2_rounded,
                      color: const Color(0xFF7C3AED),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              Text('Danh mục mặt hàng',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (data.items.isEmpty)
                const Card(
                    child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                            'Chưa có mặt hàng. Người quản lý kho có thể thêm mặt hàng mới.')))
              else
                Card(
                  child: Column(
                    children: [
                      for (final item in data.items)
                        ListTile(
                          title: Text(item.name),
                          subtitle: Text(
                              '${item.sku} · ${item.category ?? 'Chưa phân nhóm'} · ${item.unit}${item.packaging == null ? '' : ' · ${item.packaging}'}'),
                          trailing: canManageCatalog
                              ? Wrap(spacing: 4, children: [
                                  IconButton(
                                    tooltip: 'Định mức tồn (Min / Max)',
                                    icon: const Icon(Icons.tune_outlined,
                                        color: Color(0xFF2563EB)),
                                    onPressed: () => _showSetStockLevelDialog(
                                        item, data.locations, data.stockLevels),
                                  ),
                                  IconButton(
                                      tooltip: 'Sửa mặt hàng',
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () =>
                                          _showEditItemDialog(item)),
                                  IconButton(
                                      tooltip: 'Ngừng sử dụng mặt hàng',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () =>
                                          _confirmDeleteItem(item)),
                                ])
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
                                        _confirmDeleteItem(item);
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
              _buildStocktakesSection(context, data),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
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
              ],
            ),
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
        ),
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

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      child: Row(
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
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        'Kho: $locName',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color:
                                            badgeColor.withValues(alpha: 0.12),
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
                                      color:
                                          theme.colorScheme.onSurfaceVariant),
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
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _showStocktakeDetailDialog(
                                st, data.items, data.locations),
                            icon: const Icon(Icons.edit_note_rounded, size: 16),
                            label: Text(st.status == 'open'
                                ? 'Nhập Số Đếm'
                                : 'Xem Chi Tiết'),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
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
    ]);
    return _InventoryData(
      locations: results[0] as List<InventoryLocation>,
      items: results[1] as List<InventoryItem>,
      balances: results[2] as List<StockBalance>,
      assets: results[3] as List<AssetRecord>,
      lowStockAlerts: results[4] as List<LowStockAlertItem>,
      stocktakes: results[5] as List<StocktakeItem>,
      stockLevels: results[6] as List<StockLevelItem>,
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
  });

  final List<InventoryLocation> locations;
  final List<InventoryItem> items;
  final List<StockBalance> balances;
  final List<AssetRecord> assets;
  final List<LowStockAlertItem> lowStockAlerts;
  final List<StocktakeItem> stocktakes;
  final List<StockLevelItem> stockLevels;
}
