import 'dart:convert';
import 'package:flutter/material.dart';

import '../../app/app_shell.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/dtos.dart';
import 'etl_review_screen.dart';

/// Màn hình Chạy Nhập Liệu ETL (Phase 2 & 3).
/// Dành cho nhân viên được cấp quyền `etl:run`.
class EtlRunScreen extends StatefulWidget {
  const EtlRunScreen({
    super.key,
    this.initialPipelineId,
  });

  final String? initialPipelineId;

  @override
  State<EtlRunScreen> createState() => _EtlRunScreenState();
}

class _EtlRunScreenState extends State<EtlRunScreen> {
  bool _loading = true;
  String? _errorMessage;
  List<EtlPipelineDto> _pipelines = [];
  EtlPipelineDto? _selectedPipeline;

  final TextEditingController _jsonCtrl = TextEditingController();
  final TextEditingController _externalEventIdCtrl = TextEditingController();
  bool _isSubmitting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadPipelines();
  }

  @override
  void dispose() {
    _jsonCtrl.dispose();
    _externalEventIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPipelines() async {
    final repo = RepositoryScope.maybeOf(context);
    if (repo == null) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final pipelines = await repo.getEtlPipelines();
      if (mounted) {
        setState(() {
          _pipelines = pipelines;
          if (_pipelines.isNotEmpty) {
            if (widget.initialPipelineId != null) {
              _selectedPipeline = _pipelines.firstWhere(
                (p) => p.id == widget.initialPipelineId,
                orElse: () => _pipelines.first,
              );
            } else {
              _selectedPipeline = _pipelines.first;
            }
            _populateSampleJson();
          }
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

  void _populateSampleJson() {
    if (_selectedPipeline == null) return;
    final target = _selectedPipeline!.target;
    String sample = '';

    switch (target) {
      case 'balance_adjustment_admin':
        sample = jsonEncode([
          {
            "sku": "CHQ-SB-100",
            "location_id": "loc-hcm-primary",
            "target_quantity": 250,
            "reason": "Điều chỉnh số dư kiểm kê định kỳ"
          },
          {
            "sku": "CHQ-GOLD-200",
            "location_id": "loc-hcm-primary",
            "target_quantity": 120,
            "reason": "Bổ sung ấn chỉ đặc biệt"
          }
        ]);
        break;
      case 'catalog_upsert':
        sample = jsonEncode([
          {
            "sku": "NEW-ITEM-001",
            "name": "Sổ Tiết Kiệm Kỳ Hạn Mới 2026",
            "unit": "cuốn",
            "category": "passbook",
            "price": 15000
          }
        ]);
        break;
      case 'inventory_receipt':
        sample = jsonEncode([
          {
            "sku": "CHQ-SB-100",
            "location_id": "loc-hcm-primary",
            "quantity": 500,
            "source_type": "supplier"
          }
        ]);
        break;
      default:
        sample = jsonEncode([
          {
            "sku": "CHQ-SB-100",
            "location_id": "loc-hcm-primary",
            "quantity": 50
          }
        ]);
    }

    _jsonCtrl.text = sample;
  }

  Future<void> _submitRun() async {
    final repo = RepositoryScope.maybeOf(context);
    if (repo == null || _selectedPipeline == null) return;

    final rawText = _jsonCtrl.text.trim();
    if (rawText.isEmpty) {
      AppToast.error(context, 'Vui lòng nhập dữ liệu nguồn');
      return;
    }

    List<Map<String, dynamic>> rows;
    try {
      final decoded = jsonDecode(rawText);
      if (decoded is List) {
        rows = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } else {
        AppToast.error(context, 'Dữ liệu JSON phải là danh sách (Array)');
        return;
      }
    } catch (e) {
      AppToast.error(context, 'Cú pháp JSON không hợp lệ: ${friendlyError(e)}');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final run = await repo.triggerEtlRun(
        _selectedPipeline!.id,
        rawRows: rows,
        externalEventId: _externalEventIdCtrl.text.trim().isEmpty
            ? null
            : _externalEventIdCtrl.text.trim(),
      );

      if (!mounted) return;
      setState(() => _isSubmitting = false);
      AppToast.success(context, 'Đã khởi tạo Staging thành công! Đang chuyển đến màn Review...');

      // Chuyển tới màn hình review run
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RepositoryScope(
            repository: repo,
            child: EtlReviewScreen(runId: run.id),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        AppToast.error(context, 'Lỗi kích hoạt ETL: ${friendlyError(e)}');
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
        body: Center(child: ErrorView(message: _errorMessage!, onRetry: _loadPipelines)),
      );
    }

    if (_pipelines.isEmpty) {
      return const Scaffold(
        body: Center(
          child: EmptyView(
            title: 'Chưa có Pipeline nào được cấu hình',
            subtitle: 'Liên hệ quản trị viên để tạo và cấp phát Pipeline ETL cho chi nhánh của bạn.',
            icon: Icons.account_tree_outlined,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chạy Nhập Liệu ETL'),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pipeline selector card
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.route_rounded, color: Color(0xFF2563EB), size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Chọn Pipeline ETL được cấp quyền',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<EtlPipelineDto>(
                      key: const Key('etl-select-pipeline-dropdown'),
                      isExpanded: true,
                      initialValue: _selectedPipeline,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Pipeline nghiệp vụ',
                      ),
                      items: _pipelines.map((p) {
                        return DropdownMenuItem(
                          value: p,
                          child: Text(
                            '${p.name} [Mục tiêu: ${p.target}]',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (p) {
                        setState(() {
                          _selectedPipeline = p;
                          _populateSampleJson();
                        });
                      },
                    ),
                    if (_selectedPipeline != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, size: 16, color: Color(0xFF64748B)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Mục tiêu: ${_selectedPipeline!.target} · Chi nhánh: ${_selectedPipeline!.branchId ?? "Toàn hệ thống"} · Kho: ${_selectedPipeline!.locationId ?? "Tất cả kho"}',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Input Data Card
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Dữ liệu nguồn (Source Payload)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.restore, size: 16),
                          label: const Text('Nạp dữ liệu mẫu'),
                          onPressed: _populateSampleJson,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const Key('etl-json-data-input'),
                      controller: _jsonCtrl,
                      maxLines: 10,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Nhập mảng JSON dữ liệu các dòng...',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _externalEventIdCtrl,
                      decoration: const InputDecoration(
                        labelText: 'External Event ID / Khóa chống lặp (Tùy chọn)',
                        hintText: 'VD: BATCH-2026-HCM-001',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.fingerprint_outlined),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Trigger Run Action
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                key: const Key('etl-trigger-staging-btn'),
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                label: Text(
                  _isSubmitting
                      ? 'Đang phân tích & Staging...'
                      : 'Khởi tạo & Xem trước Staging (Run Staging)',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                onPressed: _isSubmitting ? null : _submitRun,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
