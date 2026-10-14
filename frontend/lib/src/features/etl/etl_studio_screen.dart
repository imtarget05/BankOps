import 'package:flutter/material.dart';

import '../../app/app_shell.dart';
import '../../core/util/role_visibility.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/dtos.dart';
import 'etl_review_screen.dart';
import 'etl_run_screen.dart';

/// Màn hình ETL Studio (Phase 2 & 3).
/// Dành cho Quản trị viên (`etl:admin`) và Kỹ sư tích hợp (`etl:design`) cấu hình
/// kết nối, pipeline, mapping version, lịch chạy và kiểm soát luồng dữ liệu.
class EtlStudioScreen extends StatefulWidget {
  const EtlStudioScreen({super.key});

  @override
  State<EtlStudioScreen> createState() => _EtlStudioScreenState();
}

class _EtlStudioScreenState extends State<EtlStudioScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = true;
  String? _errorMessage;

  List<EtlConnectionDto> _connections = [];
  List<EtlPipelineDto> _pipelines = [];
  List<EtlRunDto> _runs = [];
  final Map<String, List<EtlMappingVersionDto>> _pipelineMappings = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final repo = RepositoryScope.maybeOf(context);
    if (repo == null) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final connsFuture = repo.getEtlConnections();
      final pipesFuture = repo.getEtlPipelines();
      final runsFuture = repo.getEtlRuns();

      final res = await Future.wait([connsFuture, pipesFuture, runsFuture]);

      final conns = res[0] as List<EtlConnectionDto>;
      final pipes = res[1] as List<EtlPipelineDto>;
      final runs = res[2] as List<EtlRunDto>;

      // Load mapping versions for each pipeline
      final mappingMap = <String, List<EtlMappingVersionDto>>{};
      for (final p in pipes) {
        try {
          final versions = await repo.getEtlMappingVersions(p.id);
          mappingMap[p.id] = versions;
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _connections = conns;
          _pipelines = pipes;
          _runs = runs;
          _pipelineMappings.addAll(mappingMap);
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

  // --- Dialogs ---

  Future<void> _openCreateConnectionDialog() async {
    final repo = RepositoryScope.maybeOf(context);
    if (repo == null) return;

    final nameCtrl = TextEditingController();
    String type = 'csv';
    final secretRefCtrl = TextEditingController();
    final sheetsCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.add_link_rounded, color: Color(0xFF2563EB)),
              SizedBox(width: 8),
              Text('Thêm Kết Nối Dữ Liệu ETL'),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    key: const Key('etl-conn-name-input'),
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tên kết nối *',
                      hintText: 'VD: Nguồn Báo Cáo Chi Nhánh HCM',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: type,
                    decoration: const InputDecoration(
                      labelText: 'Định dạng nguồn dữ liệu',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'csv', child: Text('File CSV (.csv)', overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'xlsx', child: Text('File Microsoft Excel (.xlsx)', overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'json', child: Text('Mảng JSON / REST API (.json)', overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'google_sheets', child: Text('Google Sheets', overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setDialogState(() => type = v ?? 'csv'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: secretRefCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Secret Reference (Bảo mật - Tham chiếu bí mật)',
                      hintText: 'VD: env:GDRIVE_SERVICE_ACCOUNT_KEY',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (type == 'google_sheets') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: sheetsCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Allowlist Sheet IDs / Ranges (Phân cách bởi dấu phẩy)',
                        hintText: 'VD: Sheet1!A1:Z500, TonKho!A1:M100',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              key: const Key('etl-confirm-create-conn-btn'),
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) {
                  AppToast.error(ctx, 'Vui lòng nhập tên kết nối');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Tạo Kết Nối'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final allowlist = sheetsCtrl.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();

        await repo.createEtlConnection(
          name: nameCtrl.text.trim(),
          type: type,
          secretRef: secretRefCtrl.text.trim().isEmpty ? null : secretRefCtrl.text.trim(),
          allowlistSheets: allowlist.isEmpty ? null : allowlist,
        );
        if (mounted) {
          AppToast.success(context, 'Đã tạo kết nối ETL mới');
          _loadAll();
        }
      } catch (e) {
        if (mounted) {
          AppToast.error(context, 'Lỗi tạo kết nối: $e');
        }
      }
    }
  }

  Future<void> _openCreatePipelineDialog() async {
    final repo = RepositoryScope.maybeOf(context);
    if (repo == null) return;

    if (_connections.isEmpty) {
      AppToast.error(context, 'Vui lòng tạo ít nhất 1 Kết Nối dữ liệu trước khi tạo Pipeline');
      return;
    }

    final nameCtrl = TextEditingController();
    String target = 'catalog_upsert';
    String connectionId = _connections.first.id;
    final cronCtrl = TextEditingController();

    final targets = [
      {'code': 'catalog_upsert', 'name': 'Cập nhật danh mục ấn chỉ (catalog_upsert)'},
      {'code': 'inventory_receipt', 'name': 'Nhập kho ấn chỉ (inventory_receipt)'},
      {'code': 'inventory_issue', 'name': 'Xuất kho ấn chỉ (inventory_issue)'},
      {'code': 'inventory_transfer', 'name': 'Điều chuyển kho ấn chỉ (inventory_transfer)'},
      {'code': 'stocktake', 'name': 'Kiểm kê kho (stocktake)'},
      {'code': 'balance_adjustment_admin', 'name': 'Điều chỉnh số dư tồn kho (Admin self-approved)'},
    ];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.account_tree_rounded, color: Color(0xFF2563EB)),
              SizedBox(width: 8),
              Text('Thiết Kế Pipeline ETL Mới'),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    key: const Key('etl-pipeline-name-input'),
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tên Pipeline nghiệp vụ *',
                      hintText: 'VD: Nhập tồn kho đầu kỳ chi nhánh HCM',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: target,
                    decoration: const InputDecoration(
                      labelText: 'Mục tiêu nghiệp vụ (Target)',
                      border: OutlineInputBorder(),
                    ),
                    items: targets
                        .map((t) => DropdownMenuItem(
                              value: t['code']!,
                              child: Text(t['name']!, overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (v) => setDialogState(() => target = v ?? 'catalog_upsert'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: connectionId,
                    decoration: const InputDecoration(
                      labelText: 'Nguồn kết nối dữ liệu (Connection)',
                      border: OutlineInputBorder(),
                    ),
                    items: _connections
                        .map((c) => DropdownMenuItem(
                              value: c.id,
                              child: Text('${c.name} (${c.type.toUpperCase()})', overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (v) => setDialogState(() => connectionId = v ?? _connections.first.id),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: cronCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Lịch chạy định kỳ Cron (Tùy chọn)',
                      hintText: 'VD: 0 0 * * * (hàng ngày)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.schedule),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              key: const Key('etl-confirm-create-pipeline-btn'),
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) {
                  AppToast.error(ctx, 'Vui lòng nhập tên Pipeline');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Tạo Pipeline'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await repo.createEtlPipeline(
          name: nameCtrl.text.trim(),
          target: target,
          connectionId: connectionId,
          scheduleCron: cronCtrl.text.trim().isEmpty ? null : cronCtrl.text.trim(),
        );
        if (mounted) {
          AppToast.success(context, 'Đã tạo Pipeline ETL thành công');
          _loadAll();
        }
      } catch (e) {
        if (mounted) {
          AppToast.error(context, 'Lỗi tạo Pipeline: $e');
        }
      }
    }
  }

  Future<void> _openMappingWizard(EtlPipelineDto pipeline) async {
    final repo = RepositoryScope.maybeOf(context);
    if (repo == null) return;

    // Thiết lập trường chuẩn hóa theo target
    final List<Map<String, dynamic>> defaultRules = [];
    switch (pipeline.target) {
      case 'balance_adjustment_admin':
        defaultRules.addAll([
          {'source': 'SKU', 'target': 'sku', 'transform': 'trim', 'required': true, 'is_key': true},
          {'source': 'Location', 'target': 'location_id', 'transform': 'trim', 'required': true, 'is_key': true},
          {'source': 'Quantity', 'target': 'target_quantity', 'transform': 'int', 'required': true},
          {'source': 'Reason', 'target': 'reason', 'transform': 'trim', 'required': false},
        ]);
        break;
      case 'catalog_upsert':
        defaultRules.addAll([
          {'source': 'SKU', 'target': 'sku', 'transform': 'trim', 'required': true, 'is_key': true},
          {'source': 'Name', 'target': 'name', 'transform': 'trim', 'required': true},
          {'source': 'Unit', 'target': 'unit', 'transform': 'trim', 'required': true},
          {'source': 'Category', 'target': 'category', 'transform': 'trim', 'required': false},
          {'source': 'Price', 'target': 'price', 'transform': 'float', 'required': false},
        ]);
        break;
      default:
        defaultRules.addAll([
          {'source': 'SKU', 'target': 'sku', 'transform': 'trim', 'required': true, 'is_key': true},
          {'source': 'Location', 'target': 'location_id', 'transform': 'trim', 'required': true},
          {'source': 'Quantity', 'target': 'quantity', 'transform': 'int', 'required': true},
        ]);
    }

    String duplicatePolicy = 'reject';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.transform_rounded, color: Color(0xFF2563EB)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Thiết kế Mapping Version: ${pipeline.name}'),
              ),
            ],
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Quy tắc ánh xạ trường dữ liệu (Source Header ➔ Canonical Field):',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  ...defaultRules.map((r) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${r['source']} ➔ ${r['target']}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Transform: ${r['transform']}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF2563EB)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (r['required'] == true)
                            const Text('*Bắt buộc', style: TextStyle(fontSize: 11, color: Color(0xFFDC2626))),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                  const Text(
                    'Chính sách xử lý trùng lặp (Duplicate Policy):',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: duplicatePolicy,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'reject', child: Text('Từ chối nếu trùng lặp (Reject)', overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'skip', child: Text('Bỏ qua dòng trùng (Skip)', overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'overwrite', child: Text('Ghi đè dòng mới nhất (Overwrite)', overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setDialogState(() => duplicatePolicy = v ?? 'reject'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Lưu & Xuất bản (Publish)'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final version = await repo.createEtlMappingVersion(
          pipeline.id,
          mappingRules: defaultRules,
          duplicatePolicy: duplicatePolicy,
        );
        // Tự động publish phiên bản này
        await repo.publishEtlMappingVersion(pipeline.id, version.id);
        if (mounted) {
          AppToast.success(context, 'Đã xuất bản Mapping Version ${version.version} thành công');
          _loadAll();
        }
      } catch (e) {
        if (mounted) {
          AppToast.error(context, 'Lỗi tạo mapping version: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.maybeOf(context);
    final user = session?.user;

    if (!RoleVisibility.canAccessEtlStudio(user)) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          constraints: const BoxConstraints(maxWidth: 480),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.gpp_bad_outlined, size: 64, color: Color(0xFFF59E0B)),
              SizedBox(height: 16),
              Text(
                'Từ chối quyền truy cập',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Tài khoản của bạn không có capability etl:admin hoặc etl:design để truy cập ETL Studio.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ETL Studio & Cổng Dữ Liệu',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Cấu hình kết nối, thiết kế pipeline, quản lý phiên bản ánh xạ (Mapping) và kiểm soát nhập liệu an toàn.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('Mở màn chạy nhập liệu'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => RepositoryScope(
                          repository: RepositoryScope.of(context),
                          child: const EtlRunScreen(),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // Tabs
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Pipelines Nghiệp Vụ'),
              Tab(text: 'Kết Nối Dữ Liệu'),
              Tab(text: 'Lịch Sử Lượt Chạy'),
            ],
          ),

          // Tab content
          Expanded(
            child: _loading
                ? const Center(child: LoadingView())
                : _errorMessage != null
                    ? Center(child: ErrorView(message: _errorMessage!, onRetry: _loadAll))
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildPipelinesTab(),
                          _buildConnectionsTab(),
                          _buildRunsTab(),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildPipelinesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Danh sách Pipelines (${_pipelines.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              FilledButton.icon(
                key: const Key('etl-create-pipeline-btn'),
                icon: const Icon(Icons.add),
                label: const Text('Thêm Pipeline mới'),
                onPressed: _openCreatePipelineDialog,
              ),
            ],
          ),
        ),
        Expanded(
          child: _pipelines.isEmpty
              ? const Center(
                  child: EmptyView(
                    title: 'Chưa có Pipeline ETL nào',
                    subtitle: 'Tạo Pipeline đầu tiên để cấu hình luồng nhập dữ liệu an toàn.',
                    icon: Icons.account_tree_outlined,
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _pipelines.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final pipe = _pipelines[index];
                    final versions = _pipelineMappings[pipe.id] ?? [];
                    final activeVersion = versions.where((v) => v.status == 'published').lastOrNull;

                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.route_outlined, color: Color(0xFF2563EB)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        pipe.name,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Mục tiêu: ${pipe.target} · Chi nhánh: ${pipe.branchId ?? "Toàn hệ thống"}',
                                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                      ),
                                    ],
                                  ),
                                ),
                                if (activeVersion != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF0FDF4),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: const Color(0xFF22C55E)),
                                    ),
                                    child: Text(
                                      'Published v${activeVersion.version}',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                                    ),
                                  ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.transform, size: 16),
                                  label: const Text('Thiết kế Mapping'),
                                  onPressed: () => _openMappingWizard(pipe),
                                ),
                                const SizedBox(width: 8),
                                FilledButton.tonalIcon(
                                  icon: const Icon(Icons.play_arrow, size: 16),
                                  label: const Text('Chạy'),
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => RepositoryScope(
                                          repository: RepositoryScope.of(context),
                                          child: EtlRunScreen(initialPipelineId: pipe.id),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildConnectionsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Cổng Kết Nối Dữ Liệu (${_connections.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              FilledButton.icon(
                key: const Key('etl-create-conn-btn'),
                icon: const Icon(Icons.add_link),
                label: const Text('Thêm Kết Nối'),
                onPressed: _openCreateConnectionDialog,
              ),
            ],
          ),
        ),
        Expanded(
          child: _connections.isEmpty
              ? const Center(
                  child: EmptyView(
                    title: 'Chưa có Kết Nối nào',
                    subtitle: 'Tạo cổng kết nối CSV, XLSX hoặc Google Sheets để sử dụng trong Pipeline.',
                    icon: Icons.hub_outlined,
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _connections.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final conn = _connections[index];
                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      child: ListTile(
                        leading: Icon(
                          conn.type == 'google_sheets'
                              ? Icons.table_chart
                              : conn.type == 'xlsx'
                                  ? Icons.table_view
                                  : Icons.description_outlined,
                          color: const Color(0xFF2563EB),
                          size: 32,
                        ),
                        title: Text(conn.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          'Định dạng: ${conn.type.toUpperCase()} · Secret Ref: ${conn.secretRef ?? "Không có"}',
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'HOẠT ĐỘNG',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildRunsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Lịch Sử Lượt Chạy (${_runs.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Tải lại danh sách',
                onPressed: _loadAll,
              ),
            ],
          ),
        ),
        Expanded(
          child: _runs.isEmpty
              ? const Center(
                  child: EmptyView(
                    title: 'Chưa có lượt chạy nào',
                    subtitle: 'Sau khi kích hoạt Pipeline, lịch sử staging và kết quả post sẽ hiển thị tại đây.',
                    icon: Icons.history_rounded,
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _runs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final run = _runs[index];
                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      child: ListTile(
                        leading: Icon(
                          run.isPosted
                              ? Icons.check_circle_rounded
                              : run.isRejected
                                  ? Icons.cancel_rounded
                                  : Icons.hourglass_top_rounded,
                          color: run.isPosted
                              ? const Color(0xFF059669)
                              : run.isRejected
                                  ? const Color(0xFFDC2626)
                                  : const Color(0xFF2563EB),
                        ),
                        title: Row(
                          children: [
                            Text(
                              'Run #${run.id.length >= 8 ? run.id.substring(0, 8) : run.id}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                run.status.toUpperCase(),
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                            if (run.singleAdminOverride) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.security, size: 14, color: Color(0xFFD97706)),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          'Tổng: ${run.totalRows} dòng (${run.validRows} hợp lệ, ${run.invalidRows} lỗi) · Fingerprint: ${run.sourceFingerprint.length >= 8 ? run.sourceFingerprint.substring(0, 8) : run.sourceFingerprint}...',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: FilledButton.tonal(
                          child: const Text('Xem Staging'),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => RepositoryScope(
                                  repository: RepositoryScope.of(context),
                                  child: EtlReviewScreen(
                                    runId: run.id,
                                    onCompleted: _loadAll,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
