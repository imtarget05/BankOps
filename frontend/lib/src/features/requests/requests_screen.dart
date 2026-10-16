import 'package:flutter/material.dart';

import '../../app/app_shell.dart';
import '../../core/util/approval_pdf.dart';
import '../../core/util/formatting.dart';
import '../../core/util/report_share.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/dtos.dart';
import '../../data/repositories/bankops_repository.dart';
import '../ai/ai_voucher_audit.dart';
import 'request_timeline.dart';
import 'widgets/denomination_breakdown_dialog.dart';

/// Màn yêu cầu — tạo mới và gửi duyệt phiếu kho (stock) + phiếu quỹ (cash).
class RequestsScreen extends StatefulWidget {
  const RequestsScreen({
    super.key,
    this.initialOpenCreateStock = false,
    this.initialOpenCreateCash = false,
    this.onInitialOpenHandled,
  });

  final bool initialOpenCreateStock;
  final bool initialOpenCreateCash;
  final VoidCallback? onInitialOpenHandled;

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  Future<_RequestsData>? _future;
  bool _busy = false;
  bool _handledInitialOpen = false;
  RequestStatus? _statusFilter;

  void _checkInitialOpen(_RequestsData data) {
    if (_handledInitialOpen) return;
    if (widget.initialOpenCreateStock) {
      _handledInitialOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onInitialOpenHandled?.call();
          _openCreateStockDialog(data);
        }
      });
    } else if (widget.initialOpenCreateCash) {
      _handledInitialOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onInitialOpenHandled?.call();
          _openCreateCashDialog(data);
        }
      });
    }
  }

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

  void _showHistory(String requestId) {
    // Lấy repo TRƯỚC khi mở sheet: context trong bottom-sheet overlay
    // không còn nằm dưới RepositoryScope.
    final repo = RepositoryScope.of(context);
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => RequestTimeline(requestId: requestId, repo: repo),
    );
  }

  Future<void> _printCashWithAiCheck(CashRequest r) async {
    final audit = AiVoucherAuditor.checkCashRequest(r, null);
    final item = ApprovalItem(
      id: r.id,
      kind: 'Tiền mặt (${r.kind == RequestKind.receipt ? "Thu" : "Chi"})',
      maker: r.createdByName,
      impact: AppFormat.money(r.amount, currency: r.currency),
      detail: r.reason,
      status: r.status.name,
    );

    if (audit.hasErrors) {
      if (!mounted) return;
      final proceed = await AiVoucherAuditDialog.show(
        context,
        item: item,
        result: audit,
      );
      if (!proceed) {
        if (mounted) {
          AppToast.info(
              context, 'Đã hủy in để rà soát lại thông tin chứng từ.');
        }
        return;
      }
    } else {
      if (mounted) {
        AppToast.success(context,
            'AI kiểm tra: Chứng từ hợp lệ 100%, không phát hiện sai sót.');
      }
    }

    if (!mounted) return;
    await ReportShare.printPdf(
      context,
      filename: 'phieu-quy-${r.id}.pdf',
      build: () => ApprovalPdf.encode(
        item,
        auditWarnings: audit.hasErrors ? audit.warnings : null,
      ),
    );
  }

  Future<void> _printStockWithAiCheck(StockRequest r) async {
    final audit = AiVoucherAuditor.checkStockRequest(r, null);
    final totalQty = r.items.fold<double>(
      0,
      (sum, l) => sum + (double.tryParse(l.quantity) ?? 0),
    );
    final item = ApprovalItem(
      id: r.id,
      kind: 'Kho nguyên liệu (${r.kind.name})',
      maker: r.createdByName,
      impact: '${totalQty.toInt()} đơn vị nguyên liệu',
      detail: r.reason,
      status: r.status.name,
    );

    if (audit.hasErrors) {
      if (!mounted) return;
      final proceed = await AiVoucherAuditDialog.show(
        context,
        item: item,
        result: audit,
      );
      if (!proceed) {
        if (mounted) {
          AppToast.info(
              context, 'Đã hủy in để rà soát lại thông tin chứng từ.');
        }
        return;
      }
    } else {
      if (mounted) {
        AppToast.success(context,
            'AI kiểm tra: Chứng từ hợp lệ 100%, không phát hiện sai sót.');
      }
    }

    if (!mounted) return;
    await ReportShare.printPdf(
      context,
      filename: 'phieu-kho-${r.id}.pdf',
      build: () => ApprovalPdf.encode(
        item,
        auditWarnings: audit.hasErrors ? audit.warnings : null,
      ),
    );
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
          content: Text('Lỗi gửi duyệt: ${friendlyError(e)}'),
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
          content: Text('Lỗi gửi duyệt: ${friendlyError(e)}'),
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
          content: Text('Lỗi xoá phiếu: ${friendlyError(e)}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const List<String> _stockReasonSuggestions = [
    'Bổ sung vật tư định kỳ',
    'Thay mới',
    'Bảo trì',
    'Tái lạp',
    'Hao mòn',
    'Thiệt hại',
    'Chuyển kho',
    'Trùng khớp',
  ];

  static const List<String> _cashReasonSuggestions = [
    'Ghi nhận nguyên liệu đầu ca',
    'Chi chi phí vận hành',
    'Chi trả nhà cung cấp',
    'Thanh toán công việc',
    'Hoàn trả khách hàng',
    'Rút về két trung tâm',
    'Phụ cấp nhân sự',
    'Chi dự án',
  ];

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
          content: Text('Lỗi xoá phiếu: ${friendlyError(e)}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openCreateStockDialog(
    _RequestsData data, {
    RequestKind defaultKind = RequestKind.receipt,
    bool isSpoilage = false,
  }) async {
    if (data.locations.isEmpty || data.items.isEmpty) return;
    final repo = RepositoryScope.of(context);
    RequestKind kind = defaultKind;
    String locationId = data.locations.first.id;
    final nonSerialItems = data.items.where((i) => !i.trackedSerial).toList();
    String itemId =
        (nonSerialItems.isNotEmpty ? nonSerialItems.first : data.items.first)
            .id;
    final qtyCtrl = TextEditingController(text: isSpoilage ? '1' : '25');
    final reasonCtrl = TextEditingController(
      text: isSpoilage
          ? '[Báo cáo hư hỏng] Nguyên liệu bị hư hỏng/đổ vỡ trong ca'
          : (kind == RequestKind.receipt
              ? 'Nhập hàng từ nhà cung cấp'
              : 'Bổ sung vật tư định kỳ'),
    );
    final supplierCtrl = TextEditingController(
        text: 'Công ty Cung ứng Nguyên liệu Trà Sữa Phúc Long');
    final priceCtrl = TextEditingController(text: '65000');
    final lotCtrl = TextEditingController(
      text:
          'LOT-${DateTime.now().year}${DateTime.now().month.toString().padLeft(2, '0')}${DateTime.now().day.toString().padLeft(2, '0')}-01',
    );
    DateTime expiryDate = DateTime.now().add(const Duration(days: 60));

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final currentItem = data.items.cast<InventoryItem?>().firstWhere(
                (it) => it?.id == itemId,
                orElse: () => null,
              );
          final qtyVal = double.tryParse(qtyCtrl.text.trim()) ?? 0.0;
          final priceVal = double.tryParse(priceCtrl.text.trim()) ?? 0.0;
          final totalVal = qtyVal * priceVal;

          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(
                  isSpoilage
                      ? Icons.report_problem_outlined
                      : (kind == RequestKind.receipt
                          ? Icons.add_business_outlined
                          : Icons.outbox_outlined),
                  color: isSpoilage
                      ? const Color(0xFFD97706)
                      : (kind == RequestKind.receipt
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF059669)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(isSpoilage
                      ? 'Báo Cáo Hư Hỏng Nguyên Liệu'
                      : 'Tạo Phiếu Kho Mới'),
                ),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isSpoilage) ...[
                      DropdownButtonFormField<RequestKind>(
                        key: const Key('stock-kind-dropdown'),
                        isExpanded: true,
                        initialValue: kind,
                        decoration: const InputDecoration(
                          labelText: 'Loại phiếu',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: RequestKind.receipt,
                            child: Text('Nhập kho (receipt) — Nhà cung cấp / Kho trung tâm'),
                          ),
                          DropdownMenuItem(
                            value: RequestKind.payment,
                            child: Text('Xuất kho (issue) — Sử dụng / Tiêu hao'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setDialogState(() {
                              kind = v;
                              if (kind == RequestKind.receipt) {
                                reasonCtrl.text = 'Nhập hàng từ nhà cung cấp';
                              } else {
                                reasonCtrl.text = 'Xuất nguyên liệu sử dụng tại quầy';
                              }
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (kind == RequestKind.receipt) ...[
                      TextField(
                        key: const Key('stock-supplier-input'),
                        controller: supplierCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nhà cung cấp / Nguồn giao hàng *',
                          hintText: 'VD: NCC Trà Phúc Long, Sữa Barista Milk...',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.business_outlined, size: 20),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    DropdownButtonFormField<String>(
                      key: const Key('stock-location-dropdown'),
                      isExpanded: true,
                      initialValue: locationId,
                      decoration: InputDecoration(
                        labelText: kind == RequestKind.receipt
                            ? 'Kho nhập đến (Quầy / Kho trung tâm) *'
                            : 'Kho xuất từ (Quầy / Kho trung tâm) *',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.warehouse_outlined, size: 20),
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
                      isExpanded: true,
                      initialValue: itemId,
                      decoration: const InputDecoration(
                        labelText: 'Nguyên vật liệu *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.local_cafe_outlined, size: 20),
                      ),
                      items: [
                        for (final item in data.items)
                          DropdownMenuItem(
                            value: item.id,
                            child: Text(
                                '${item.name} (${item.sku} · ${item.unit})'),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) setDialogState(() => itemId = v);
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            key: const Key('stock-qty-input'),
                            controller: qtyCtrl,
                            decoration: InputDecoration(
                              labelText: 'Số lượng (${currentItem?.unit ?? "đơn vị"}) *',
                              border: const OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            onChanged: (_) => setDialogState(() {}),
                          ),
                        ),
                        if (kind == RequestKind.receipt) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 3,
                            child: TextField(
                              key: const Key('stock-price-input'),
                              controller: priceCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Đơn giá nhập (VND) *',
                                border: OutlineInputBorder(),
                                suffixText: 'đ',
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setDialogState(() {}),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (kind == RequestKind.receipt) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: const Color(0xFF2563EB)
                                  .withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Thành tiền tạm tính:',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                            Text(
                              AppFormat.money(totalVal.toStringAsFixed(0),
                                  currency: 'VND'),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF2563EB),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: const Key('stock-lot-input'),
                              controller: lotCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Số lô sản xuất (Lot No) *',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                final now = DateTime.now();
                                final picked = await showDatePicker(
                                  context: ctx,
                                  initialDate: expiryDate.isBefore(now)
                                      ? now.add(const Duration(days: 30))
                                      : expiryDate,
                                  firstDate: now,
                                  lastDate: now.add(const Duration(days: 730)),
                                );
                                if (picked != null) {
                                  setDialogState(() => expiryDate = picked);
                                }
                              },
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Hạn sử dụng (Expiry) *',
                                  border: OutlineInputBorder(),
                                  suffixIcon: Icon(Icons.calendar_month, size: 18),
                                ),
                                child: Text(
                                  '${expiryDate.day.toString().padLeft(2, '0')}/${expiryDate.month.toString().padLeft(2, '0')}/${expiryDate.year}',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    Autocomplete<String>(
                      key: const Key('stock-reason-autocomplete'),
                      initialValue: TextEditingValue(text: reasonCtrl.text),
                      optionsBuilder: (TextEditingValue text) {
                        final query = text.text.trim();
                        if (query.isEmpty) return _stockReasonSuggestions;
                        return _stockReasonSuggestions.where((s) =>
                            s.toLowerCase().contains(query.toLowerCase()));
                      },
                      onSelected: (value) => reasonCtrl.text = value,
                      fieldViewBuilder: (ctx, ctrl, focus, onFieldSubmitted) {
                        return TextField(
                          key: const Key('stock-reason-input'),
                          controller: ctrl,
                          focusNode: focus,
                          onChanged: (val) {
                            reasonCtrl.text = val;
                          },
                          decoration: const InputDecoration(
                            labelText: 'Diễn giải / Lý do lập phiếu *',
                            hintText: 'Gõ hoặc chọn gợi ý...',
                            border: OutlineInputBorder(),
                          ),
                        );
                      },
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
                style: FilledButton.styleFrom(
                  backgroundColor: isSpoilage
                      ? const Color(0xFFD97706)
                      : const Color(0xFF2563EB),
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(isSpoilage ? 'Gửi báo cáo hư hỏng' : 'Lưu phiếu nháp'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final qty = double.tryParse(qtyCtrl.text.trim()) ?? 1.0;
      final price = double.tryParse(priceCtrl.text.trim());
      final total = price != null ? (qty * price).toStringAsFixed(0) : null;
      final expiryIso =
          '${expiryDate.year}-${expiryDate.month.toString().padLeft(2, '0')}-${expiryDate.day.toString().padLeft(2, '0')}';

      final created = await repo.createStockRequest(
        kind: kind,
        sourceLocationId: kind == RequestKind.payment ? locationId : null,
        destLocationId: kind == RequestKind.receipt ? locationId : null,
        supplier: kind == RequestKind.receipt ? supplierCtrl.text.trim() : null,
        lines: [
          StockRequestLine(
            itemId: itemId,
            quantity: qtyCtrl.text.trim().isEmpty ? '1' : qtyCtrl.text.trim(),
            unitPrice: kind == RequestKind.receipt ? priceCtrl.text.trim() : null,
            lineTotal: kind == RequestKind.receipt ? total : null,
            lotNo: kind == RequestKind.receipt ? lotCtrl.text.trim() : null,
            expiryDate: kind == RequestKind.receipt ? expiryIso : null,
          ),
        ],
        reason: reasonCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
          content: Text(isSpoilage
              ? 'Đã ghi nhận báo cáo hư hỏng #${created.id} chờ quản lý xác nhận!'
              : 'Đã tạo thành công phiếu kho ${created.id}'),
        ),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFB42318),
          behavior: SnackBarBehavior.floating,
          content: Text('Lỗi tạo phiếu kho: ${friendlyError(e)}'),
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
    final reasonCtrl =
        TextEditingController(text: _cashReasonSuggestions.first);
    final reasonFocus = FocusNode();
    Map<int, int>? denominationCounts;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Tạo Phiếu Nhập Nguyên Liệu'),
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
                    isExpanded: true,
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('cash-amount-input'),
                          controller: amountCtrl,
                          decoration: InputDecoration(
                            labelText: 'Số tiền (VND)',
                            border: const OutlineInputBorder(),
                            helperText: amountCtrl.text.isNotEmpty
                                ? '${AppFormat.number(amountCtrl.text)} đ'
                                : null,
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setDialogState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'Mở Bảng kê kiểm đếm mệnh giá',
                        child: OutlinedButton.icon(
                          key: const Key('open-denomination-btn'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 15),
                            side: const BorderSide(color: Color(0xFF059669)),
                          ),
                          icon: const Icon(Icons.calculate_outlined,
                              color: Color(0xFF059669)),
                          label: const Text('Bảng kê',
                              style: TextStyle(
                                  color: Color(0xFF059669), fontSize: 13)),
                          onPressed: () async {
                            final res = await showDialog<DenominationResult>(
                              context: ctx,
                              builder: (_) => DenominationBreakdownDialog(
                                  initialCounts: denominationCounts),
                            );
                            if (res != null) {
                              denominationCounts = res.counts;
                              setDialogState(() {
                                amountCtrl.text = res.totalAmount.toString();
                                if (reasonCtrl.text.trim().isEmpty) {
                                  reasonCtrl.text = res.breakdownSummary;
                                } else if (!reasonCtrl.text
                                    .contains('Bảng kê:')) {
                                  reasonCtrl.text =
                                      '${reasonCtrl.text.trim()} · ${res.breakdownSummary}';
                                }
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Autocomplete<String>(
                    key: const Key('cash-reason-autocomplete'),
                    optionsBuilder: (TextEditingValue text) {
                      final query = text.text.trim();
                      if (query.isEmpty) return _cashReasonSuggestions;
                      return _cashReasonSuggestions.where(
                          (s) => s.toLowerCase().contains(query.toLowerCase()));
                    },
                    onSelected: (value) => reasonCtrl.text = value,
                    fieldViewBuilder: (ctx, ctrl, focus, onFieldSubmitted) {
                      return TextField(
                        key: const Key('cash-reason-input'),
                        controller: ctrl,
                        focusNode: focus,
                        decoration: const InputDecoration(
                          labelText: 'Diễn giải lý do nộp/rút quỹ',
                          hintText: 'Gõ hoặc chọn gợi ý...',
                          border: OutlineInputBorder(),
                        ),
                      );
                    },
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
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF059669)),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Lưu phiếu nháp'),
            ),
          ],
        ),
      ),
    );
    reasonFocus.dispose();

    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final created = await repo.createCashRequest(
        cashboxId: cashboxId,
        kind: kind,
        amount:
            amountCtrl.text.trim().isEmpty ? '100000' : amountCtrl.text.trim(),
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
          content: Text('Lỗi tạo phiếu quỹ: ${friendlyError(e)}'),
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
        _checkInitialOpen(data);
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
                          'Khởi tạo phiếu nhập, xuất và điều chỉnh nguyên liệu để quản lý phê duyệt',
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
                        onPressed:
                            _busy ? null : () => _openCreateStockDialog(data),
                        icon: const Icon(Icons.add_box_outlined, size: 18),
                        label: const Text('Nhập/Xuất kho'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      FilledButton.icon(
                        key: const Key('btn-create-spoilage-request'),
                        onPressed: _busy
                            ? null
                            : () => _openCreateStockDialog(
                                  data,
                                  defaultKind: RequestKind.payment,
                                  isSpoilage: true,
                                ),
                        icon: const Icon(Icons.broken_image_outlined, size: 18),
                        label: const Text('Báo cáo hư hỏng'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFD97706),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      FilledButton.icon(
                        key: const Key('btn-create-cash-request'),
                        onPressed:
                            _busy ? null : () => _openCreateCashDialog(data),
                        icon: const Icon(Icons.payments_outlined, size: 18),
                        label: const Text('Tạo phiếu quỹ'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Bộ lọc trạng thái
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      selected: _statusFilter == null,
                      label: Text(
                          'Tất cả (${data.stockRequests.length + data.cashRequests.length})'),
                      onSelected: (_) => setState(() => _statusFilter = null),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      selected: _statusFilter == RequestStatus.returned,
                      avatar: const Icon(Icons.assignment_return_outlined,
                          size: 16, color: Color(0xFFD97706)),
                      label: Text(
                        'Cần chỉnh sửa (${data.stockRequests.where((r) => r.status == RequestStatus.returned).length + data.cashRequests.where((r) => r.status == RequestStatus.returned).length})',
                        style: TextStyle(
                          color: _statusFilter == RequestStatus.returned
                              ? null
                              : const Color(0xFFD97706),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onSelected: (_) => setState(
                          () => _statusFilter = RequestStatus.returned),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      selected: _statusFilter == RequestStatus.pending,
                      label: Text(
                          'Chờ duyệt (${data.stockRequests.where((r) => r.status == RequestStatus.pending).length + data.cashRequests.where((r) => r.status == RequestStatus.pending).length})'),
                      onSelected: (_) =>
                          setState(() => _statusFilter = RequestStatus.pending),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      selected: _statusFilter == RequestStatus.draft,
                      label: Text(
                          'Bản nháp (${data.stockRequests.where((r) => r.status == RequestStatus.draft).length + data.cashRequests.where((r) => r.status == RequestStatus.draft).length})'),
                      onSelected: (_) =>
                          setState(() => _statusFilter = RequestStatus.draft),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      selected: _statusFilter == RequestStatus.posted,
                      label: Text(
                          'Đã ghi sổ (${data.stockRequests.where((r) => r.status == RequestStatus.posted).length + data.cashRequests.where((r) => r.status == RequestStatus.posted).length})'),
                      onSelected: (_) =>
                          setState(() => _statusFilter = RequestStatus.posted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Phiếu kho
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Phiếu Kho Nguyên Liệu (${_statusFilter == null ? data.stockRequests.length : data.stockRequests.where((r) => r.status == _statusFilter).length})',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Kiểm soát viên duyệt trước khi ghi nhận nhập/xuất',
                    style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final r in (_statusFilter == null
                  ? data.stockRequests
                  : data.stockRequests
                      .where((r) => r.status == _statusFilter)
                      .toList()))
                Container(
                  key: Key('stock-request-card-${r.id}'),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.5),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF2563EB).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.inventory_2_outlined,
                              color: Color(0xFF2563EB), size: 20),
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
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14),
                                  ),
                                  const SizedBox(width: 8),
                                  _statusChip(r.status),
                                  const Spacer(),
                                  IconButton(
                                    key: Key('print-stock-${r.id}'),
                                    icon: const Icon(Icons.print_outlined,
                                        size: 20),
                                    tooltip: 'In phiếu ${r.id} (AI Kiểm Duyệt)',
                                    onPressed: () => _printStockWithAiCheck(r),
                                  ),
                                  IconButton(
                                    key: Key('request-history-stock-${r.id}'),
                                    icon: const Icon(Icons.history_outlined,
                                        size: 20),
                                    tooltip: 'Lịch sử phiếu ${r.id}',
                                    onPressed: () => _showHistory(r.id),
                                  ),
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
                              if (r.status == RequestStatus.returned &&
                                  (r.returnReason?.isNotEmpty ?? false)) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFFBEB),
                                    border: Border.all(
                                        color: const Color(0xFFFDE68A)),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                          Icons.assignment_return_outlined,
                                          size: 16,
                                          color: Color(0xFFD97706)),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          'Ý kiến KSV: ${r.returnReason}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF92400E),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (r.status == RequestStatus.draft)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                key: Key('btn-delete-stock-${r.id}'),
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.red, size: 20),
                                tooltip: 'Xoá phiếu nháp',
                                onPressed:
                                    _busy ? null : () => _deleteStock(r.id),
                              ),
                              const SizedBox(width: 4),
                              FilledButton.icon(
                                key: Key('btn-submit-stock-${r.id}'),
                                onPressed:
                                    _busy ? null : () => _submitStock(r.id),
                                icon: const Icon(Icons.send_rounded, size: 16),
                                label: const Text('Gửi duyệt'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF2563EB),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ],
                          )
                        else if (r.status == RequestStatus.returned)
                          FilledButton.icon(
                            key: Key('btn-resubmit-stock-${r.id}'),
                            onPressed: _busy ? null : () => _submitStock(r.id),
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text('Gửi duyệt lại'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFD97706),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
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
                    'Phiếu Điều Chỉnh Kho (${_statusFilter == null ? data.cashRequests.length : data.cashRequests.where((r) => r.status == _statusFilter).length})',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Ảnh hưởng số dư két sau khi được phê duyệt',
                    style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final r in (_statusFilter == null
                  ? data.cashRequests
                  : data.cashRequests
                      .where((r) => r.status == _statusFilter)
                      .toList()))
                Container(
                  key: Key('cash-request-card-${r.id}'),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.5),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF059669).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.savings_outlined,
                              color: Color(0xFF059669), size: 20),
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
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14),
                                  ),
                                  const SizedBox(width: 8),
                                  _statusChip(r.status),
                                  const Spacer(),
                                  IconButton(
                                    key: Key('print-cash-${r.id}'),
                                    icon: const Icon(Icons.print_outlined,
                                        size: 20),
                                    tooltip: 'In phiếu ${r.id} (AI Kiểm Duyệt)',
                                    onPressed: () => _printCashWithAiCheck(r),
                                  ),
                                  IconButton(
                                    key: Key('request-history-cash-${r.id}'),
                                    icon: const Icon(Icons.history_outlined,
                                        size: 20),
                                    tooltip: 'Lịch sử phiếu ${r.id}',
                                    onPressed: () => _showHistory(r.id),
                                  ),
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
                              if (r.status == RequestStatus.returned &&
                                  (r.returnReason?.isNotEmpty ?? false)) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFFBEB),
                                    border: Border.all(
                                        color: const Color(0xFFFDE68A)),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                          Icons.assignment_return_outlined,
                                          size: 16,
                                          color: Color(0xFFD97706)),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          'Ý kiến KSV: ${r.returnReason}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF92400E),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (r.status == RequestStatus.draft)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                key: Key('btn-delete-cash-${r.id}'),
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.red, size: 20),
                                tooltip: 'Xoá phiếu nháp',
                                onPressed:
                                    _busy ? null : () => _deleteCash(r.id),
                              ),
                              const SizedBox(width: 4),
                              FilledButton.icon(
                                key: Key('btn-submit-cash-${r.id}'),
                                onPressed:
                                    _busy ? null : () => _submitCash(r.id),
                                icon: const Icon(Icons.send_rounded, size: 16),
                                label: const Text('Gửi duyệt'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF059669),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ],
                          )
                        else if (r.status == RequestStatus.returned)
                          FilledButton.icon(
                            key: Key('btn-resubmit-cash-${r.id}'),
                            onPressed: _busy ? null : () => _submitCash(r.id),
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text('Gửi duyệt lại'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFD97706),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
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
      case RequestStatus.returned:
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFFD97706);
        text = 'Cần chỉnh sửa';
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
    Color bg = const Color(0xFF64748B).withValues(alpha: 0.12);
    Color fg = const Color(0xFF475467);
    String label = status.name.toUpperCase();
    if (status == RequestStatus.posted || status == RequestStatus.approved) {
      bg = const Color(0xFF059669).withValues(alpha: 0.12);
      fg = const Color(0xFF059669);
    } else if (status == RequestStatus.returned) {
      bg = const Color(0xFFD97706).withValues(alpha: 0.12);
      fg = const Color(0xFFD97706);
      label = 'CẦN SỬA';
    } else if (status == RequestStatus.rejected) {
      bg = const Color(0xFFDC2626).withValues(alpha: 0.12);
      fg = const Color(0xFFDC2626);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: fg,
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
