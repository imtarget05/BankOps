import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_shell.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/dtos.dart';

/// Màn hình Review Staging và Post vào sổ cái (Ledger Posting) cho lượt chạy ETL.
class EtlReviewScreen extends StatefulWidget {
  const EtlReviewScreen({
    super.key,
    required this.runId,
    this.onCompleted,
  });

  final String runId;
  final VoidCallback? onCompleted;

  @override
  State<EtlReviewScreen> createState() => _EtlReviewScreenState();
}

class _EtlReviewScreenState extends State<EtlReviewScreen> {
  bool _loading = true;
  String? _errorMessage;
  EtlRunDto? _run;
  List<EtlRunRowDto> _rows = [];

  // Filter
  bool? _filterValid;
  final TextEditingController _searchCtrl = TextEditingController();
  final int _page = 1;
  final int _pageSize = 50;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadRunData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRunData() async {
    final repo = RepositoryScope.maybeOf(context);
    if (repo == null) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final run = await repo.getEtlRun(widget.runId);
      final rowsData = await repo.getEtlRunRows(
        widget.runId,
        valid: _filterValid,
        search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
        page: _page,
        pageSize: _pageSize,
      );

      final rowList = (rowsData['items'] as List?)
              ?.map((e) => EtlRunRowDto.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];

        if (mounted) {
        setState(() {
          _run = run;
          _rows = rowList;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _downloadErrorReport() async {
    final repo = RepositoryScope.maybeOf(context);
    if (repo == null) return;

    try {
      final csv = await repo.getEtlErrorReport(widget.runId);
      await Clipboard.setData(ClipboardData(text: csv));
      if (!mounted) return;
      AppToast.success(context, 'Đã sao chép nội dung báo cáo lỗi CSV vào bộ nhớ tạm');
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Lỗi tải báo cáo lỗi: $e');
      }
    }
  }

  Future<void> _reviewRun(String decision) async {
    final repo = RepositoryScope.maybeOf(context);
    if (repo == null) return;

    final noteCtrl = TextEditingController();
    final isApprove = decision == 'approved';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isApprove ? Icons.check_circle_outline : Icons.cancel_outlined,
              color: isApprove ? const Color(0xFF059669) : const Color(0xFFDC2626),
            ),
            const SizedBox(width: 8),
            Text(isApprove ? 'Phê duyệt Staging ETL' : 'Từ chối lượt chạy ETL'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isApprove
                  ? 'Bạn có chắc chắn muốn phê duyệt kết quả staging này? Sau khi duyệt, người vận hành có thể đẩy dữ liệu vào sổ cái.'
                  : 'Xác nhận từ chối kết quả lượt chạy này. Lượt chạy sẽ bị hủy và không thể post vào sổ cái.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Ghi chú thẩm tra (Tùy chọn)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: isApprove ? const Color(0xFF059669) : const Color(0xFFDC2626),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isApprove ? 'Duyệt Staging' : 'Từ chối'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await repo.reviewEtlRun(
          widget.runId,
          decision: decision,
          note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
        );
        if (mounted) {
          AppToast.success(context, isApprove ? 'Đã duyệt Staging' : 'Đã từ chối lượt chạy');
          _loadRunData();
          widget.onCompleted?.call();
        }
      } catch (e) {
        if (mounted) {
          AppToast.error(context, 'Lỗi thẩm tra: $e');
        }
      }
    }
  }

  Future<void> _postToLedger() async {
    final repo = RepositoryScope.maybeOf(context);
    if (repo == null) return;

    final run = _run;
    final isOverride = run?.singleAdminOverride == true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.inventory_2_rounded, color: Color(0xFF2563EB)),
            SizedBox(width: 8),
            Text('Đẩy dữ liệu vào Sổ Cái (Ledger Post)'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Xác nhận đẩy các dòng hợp lệ vào sổ sách kế toán/kho vận.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Hệ thống sẽ:\n'
              '• Sinh chứng từ điều chỉnh / nhập xuất (Movement & InventoryRequest)\n'
              '• Cập nhật số dư tồn kho bất biến theo nguyên tắc kế toán kép\n'
              '• Ghi nhận vết kiểm toán AuditEvent & OutboxEvent đầy đủ.',
              style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
            ),
            if (isOverride) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFF59E0B)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.security_rounded, color: Color(0xFFD97706), size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Áp dụng cơ chế Single-Admin Override: Admin tự phê duyệt và đẩy số dư.',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFB45309)),
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
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton.icon(
            key: const Key('etl-confirm-post-btn'),
            icon: const Icon(Icons.send_rounded),
            label: const Text('Xác nhận Post Sổ Cái'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final res = await repo.postEtlRun(widget.runId);
        if (mounted) {
          final refId = res['reference_id'] ?? res['generated_reference_id'] ?? '';
          AppToast.success(context, 'Đã ghi nhận vào sổ cái thành công! Mã chứng từ: $refId');
          _loadRunData();
          widget.onCompleted?.call();
        }
      } catch (e) {
        if (mounted) {
          AppToast.error(context, 'Lỗi post sổ cái: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: LoadingView()));
    }
    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chi tiết lượt chạy ETL')),
        body: Center(child: ErrorView(message: _errorMessage!, onRetry: _loadRunData)),
      );
    }

    final run = _run!;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.fact_check_outlined, size: 22),
            const SizedBox(width: 8),
            Text('Review Staging: Run #${run.id.substring(0, 8)}'),
          ],
        ),
        actions: [
          if (run.invalidRows > 0)
            TextButton.icon(
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Tải báo cáo lỗi (CSV)'),
              onPressed: _downloadErrorReport,
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner thông tin lượt chạy
          _buildRunSummaryBanner(run),

          // Search & Filter rows bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Tìm kiếm dòng dữ liệu (SKU, kho, ghi chú)...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                _loadRunData();
                              },
                            )
                          : null,
                    ),
                    onSubmitted: (_) => _loadRunData(),
                  ),
                ),
                const SizedBox(width: 12),
                SegmentedButton<bool?>(
                  segments: const [
                    ButtonSegment(value: null, label: Text('Tất cả')),
                    ButtonSegment(value: true, label: Text('Hợp lệ')),
                    ButtonSegment(value: false, label: Text('Có lỗi')),
                  ],
                  selected: {_filterValid},
                  onSelectionChanged: (val) {
                    setState(() => _filterValid = val.first);
                    _loadRunData();
                  },
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Rows Data Table
          Expanded(
            child: _rows.isEmpty
                ? const Center(
                    child: Text(
                      'Không có dòng dữ liệu nào phù hợp với bộ lọc.',
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final row = _rows[index];
                      return _buildRowCard(row);
                    },
                  ),
          ),

          // Bottom Action Bar
          _buildBottomActionBar(run),
        ],
      ),
    );
  }

  Widget _buildRunSummaryBanner(EtlRunDto run) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  _buildStatusChip(run.status),
                  const SizedBox(width: 8),
                  Text(
                    'Mapping v${run.mappingVersionNum}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  if (run.singleAdminOverride) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFF59E0B)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified_user_rounded, size: 14, color: Color(0xFFD97706)),
                          SizedBox(width: 4),
                          Text(
                            'Single-Admin Override',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFB45309)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                'Fingerprint: ${run.sourceFingerprint.substring(0, 10)}...',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildMetric('Tổng số dòng', '${run.totalRows}', const Color(0xFF2563EB)),
              const SizedBox(width: 16),
              _buildMetric('Hợp lệ', '${run.validRows}', const Color(0xFF059669)),
              const SizedBox(width: 16),
              _buildMetric('Dòng lỗi', '${run.invalidRows}', const Color(0xFFDC2626)),
              const SizedBox(width: 16),
              if (run.postedAt != null)
                _buildMetric(
                  'Đã post vào',
                  '${run.generatedReferenceType?.toUpperCase()}: ${run.generatedReferenceId ?? ''}',
                  const Color(0xFF7C3AED),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRowCard(EtlRunRowDto row) {
    final isValid = row.valid;
    final hasErrors = row.errorsJson.isNotEmpty;
    final action = row.actionPreview;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isValid ? const Color(0xFFE2E8F0) : const Color(0xFFFCA5A5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Dòng #${row.rowNumber}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isValid ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isValid ? 'HỢP LỆ' : 'KHÔNG HỢP LỆ',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isValid ? const Color(0xFF15803D) : const Color(0xFFDC2626),
                    ),
                  ),
                ),
                const Spacer(),
                if (action.isNotEmpty) ...[
                  if (action.containsKey('current_quantity') && action.containsKey('target_quantity')) ...[
                    Text(
                      'Tồn: ${action['current_quantity']} ➔ ${action['target_quantity']} (Delta: ${action['delta_quantity']})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: action['direction'] == 'in' ? const Color(0xFFEFF6FF) : const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        (action['direction'] as String? ?? 'in').toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: action['direction'] == 'in' ? const Color(0xFF2563EB) : const Color(0xFFEA580C),
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Dữ liệu chuẩn hóa (Canonical):',
                        style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        row.canonicalDataJson?.entries.map((e) => '${e.key}: ${e.value}').join(', ') ?? 'Chưa mapping',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Dữ liệu gốc (Source):',
                        style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        row.rawDataJson.entries.map((e) => '${e.key}: ${e.value}').join(', '),
                        style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (hasErrors) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, size: 16, color: Color(0xFFDC2626)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        row.errorsJson.join('; '),
                        style: const TextStyle(fontSize: 12, color: Color(0xFFDC2626), fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBottomActionBar(EtlRunDto run) {
    final canPost = run.validRows > 0 && !run.isPosted && !run.isRejected;
    final isStaged = run.isStaged;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            run.isPosted
                ? '✅ Lượt chạy này đã được đẩy vào sổ cái (Posted).'
                : run.isRejected
                    ? '❌ Lượt chạy này đã bị từ chối.'
                    : 'Sẵn sàng kiểm tra và xử lý ${run.validRows} dòng hợp lệ.',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Row(
            children: [
              if (isStaged) ...[
                OutlinedButton(
                  onPressed: () => _reviewRun('rejected'),
                  child: const Text('Từ chối Staging'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: () => _reviewRun('approved'),
                  child: const Text('Duyệt Staging'),
                ),
                const SizedBox(width: 8),
              ],
              if (canPost)
                FilledButton.icon(
                  key: const Key('etl-post-to-ledger-btn'),
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('Đẩy vào sổ cái (Post Ledger)'),
                  onPressed: _postToLedger,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetric(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
        Text(
          value,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  Widget _buildStatusChip(String status) {
    Color bg = const Color(0xFFF1F5F9);
    Color fg = const Color(0xFF475569);

    switch (status) {
      case 'posted':
      case 'completed':
        bg = const Color(0xFFF0FDF4);
        fg = const Color(0xFF15803D);
        break;
      case 'staged':
      case 'reviewing':
        bg = const Color(0xFFEFF6FF);
        fg = const Color(0xFF2563EB);
        break;
      case 'rejected':
      case 'failed':
        bg = const Color(0xFFFEF2F2);
        fg = const Color(0xFFDC2626);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }
}
