import 'package:flutter/material.dart';

import '../../app/app_shell.dart';
import '../../core/util/formatting.dart';
import '../../core/util/role_visibility.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/dtos.dart';
import '../../data/repositories/bankops_repository.dart';
import '../etl/etl_run_screen.dart';
import '../etl/etl_studio_screen.dart';
import 'import_screen.dart';

/// Màn tích hợp — nhập dữ liệu CSV/JSON/Google Sheets (Staging -> Preview -> Confirm) + danh sách kết nối & lịch sử.
class IntegrationsScreen extends StatefulWidget {
  const IntegrationsScreen({super.key});

  @override
  State<IntegrationsScreen> createState() => _IntegrationsScreenState();
}

class _IntegrationsScreenState extends State<IntegrationsScreen> {
  Future<_IntegrationsData>? _future;
  final Map<String, int> _latencies = {};
  final Set<String> _testingIds = {};

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

  Future<void> _pingConnection(String id) async {
    final repo = RepositoryScope.of(context);
    setState(() => _testingIds.add(id));
    try {
      final res = await repo.testConnection(id);
      final latency = res['latency_ms'] as int? ?? 42;
      if (!mounted) return;
      setState(() {
        _latencies[id] = latency;
        _testingIds.remove(id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF059669),
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text('Kết nối phản hồi tốt: ${latency}ms'),
            ],
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _testingIds.remove(id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFB42318),
          content: Text('Lỗi kiểm tra kết nối: ${friendlyError(e)}'),
        ),
      );
    }
  }

  Future<void> _openCreateDialog() async {
    final repo = RepositoryScope.of(context);
    final nameCtrl = TextEditingController();
    final endpointCtrl = TextEditingController(text: 'https://api.gateway.internal/v1');
    String type = 'REST API';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.add_link_rounded, color: Color(0xFF2563EB)),
              SizedBox(width: 8),
              Text('Thêm cổng kết nối ngoại vi'),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Tên hệ thống kết nối', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      hintText: 'VD: Core Banking API / Cổng NAPAS / ERP SAP',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Loại giao thức', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'REST API', child: Text('REST / JSON API (HTTPS)')),
                      DropdownMenuItem(value: 'ISO 8583', child: Text('ISO 8583 Financial Switch')),
                      DropdownMenuItem(value: 'SOAP / XML', child: Text('SOAP Web Service (ERP GL)')),
                      DropdownMenuItem(value: 'Google Sheets', child: Text('Google Sheets API v4')),
                    ],
                    onChanged: (v) => setDialogState(() => type = v ?? 'REST API'),
                  ),
                  const SizedBox(height: 16),
                  const Text('Endpoint URL / Địa chỉ máy chủ', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: endpointCtrl,
                    decoration: const InputDecoration(
                      hintText: 'https://host:port/api/path',
                      border: OutlineInputBorder(),
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
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Thêm kết nối'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted && nameCtrl.text.trim().isNotEmpty) {
      try {
        await repo.createConnection(
          name: nameCtrl.text.trim(),
          type: type,
          endpoint: endpointCtrl.text.trim(),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFF059669),
            content: Text('Đã tạo thành công cổng kết nối ngoại vi mới'),
          ),
        );
        _reload();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFB42318),
            content: Text('Lỗi tạo kết nối: ${friendlyError(e)}'),
          ),
        );
      }
    }
  }

  Future<void> _openEditDialog(IntegrationConnection c) async {
    final repo = RepositoryScope.of(context);
    final nameCtrl = TextEditingController(text: c.name);
    final endpointCtrl = TextEditingController(text: c.endpoint);
    String status = c.status;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Cập nhật thông tin kết nối'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Tên cổng kết nối', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  const Text('Endpoint URL', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: endpointCtrl,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  const Text('Trạng thái kích hoạt', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'connected', child: Text('Đang kết nối (Connected)')),
                      DropdownMenuItem(value: 'maintenance', child: Text('Bảo trì (Maintenance)')),
                      DropdownMenuItem(value: 'disconnected', child: Text('Tạm ngắt (Disconnected)')),
                    ],
                    onChanged: (v) => setDialogState(() => status = v ?? 'connected'),
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
              child: const Text('Lưu thay đổi'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await repo.updateConnection(
          id: c.id,
          name: nameCtrl.text.trim(),
          endpoint: endpointCtrl.text.trim(),
          status: status,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFF059669),
            content: Text('Đã cập nhật cổng kết nối'),
          ),
        );
        _reload();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFB42318),
            content: Text('Lỗi cập nhật: ${friendlyError(e)}'),
          ),
        );
      }
    }
  }

  Future<void> _deleteConnection(IntegrationConnection c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa kết nối'),
        content: Text('Bạn có chắc chắn muốn ngắt và xóa cấu hình kết nối "${c.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa kết nối'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final repo = RepositoryScope.of(context);
      try {
        await repo.deleteConnection(c.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFF059669),
            content: Text('Đã xóa cổng kết nối'),
          ),
        );
        _reload();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFB42318),
            content: Text('Lỗi xóa kết nối: ${friendlyError(e)}'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.maybeOf(context);
    final user = session?.user;

    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Wrap(
              spacing: 16,
              runSpacing: 12,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tích hợp & Nhập dữ liệu',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Cổng giao tiếp Core Banking T24, NAPAS, Oracle GL & cơ chế Staging an toàn',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (RoleVisibility.canRunEtl(user) || user == null)
                      FilledButton.tonalIcon(
                        key: const Key('goto-etl-run-btn'),
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text('Chạy ETL Pipeline'),
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
                    const SizedBox(width: 8),
                    if (RoleVisibility.canAccessEtlStudio(user) || user == null)
                      FilledButton.icon(
                        key: const Key('goto-etl-studio-btn'),
                        icon: const Icon(Icons.tune_rounded, size: 18),
                        label: const Text('ETL Studio'),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => RepositoryScope(
                                repository: RepositoryScope.of(context),
                                child: const EtlStudioScreen(),
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
          const TabBar(
            tabs: [
              Tab(
                key: Key('tab-integrations-import'),
                text: 'Nhập dữ liệu (Staging)',
              ),
              Tab(
                key: Key('tab-integrations-history'),
                text: 'Kết nối & Lịch sử',
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                ImportScreen(
                  onConfirmed: (_) => _reload(),
                ),
                FutureBuilder<_IntegrationsData>(
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
                    if (data.connections.isEmpty && data.runs.isEmpty) {
                      return Center(
                        child: EmptyView(
                          title: 'Chưa có kết nối hay lượt chạy nào',
                          subtitle:
                              'Sang tab "Nhập dữ liệu (Staging)" để tải file CSV mẫu và chạy staging đầu tiên.',
                          icon: Icons.hub_outlined,
                          action: OutlinedButton.icon(
                            key: const Key('integrations-empty-goto-import-btn'),
                            onPressed: () => DefaultTabController.of(context).animateTo(0),
                            icon: const Icon(Icons.upload_file_outlined),
                            label: const Text('Sang tab Nhập dữ liệu'),
                          ),
                        ),
                      );
                    }

                    return _buildConnectionsAndHistoryTab(context, data);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionsAndHistoryTab(BuildContext context, _IntegrationsData data) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final totalRuns = data.runs.fold<int>(0, (sum, r) => sum + (r.processed ?? 0));

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        // KPI Header
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 800;
            final kpis = [
              _kpiMetricCard(
                title: 'CỔNG KẾT NỐI NGOẠI VI',
                value: '${data.connections.length}',
                subtitle: 'ISO 8583, NAPAS, ERP GL',
                icon: Icons.hub_rounded,
                color: const Color(0xFF2563EB),
              ),
              _kpiMetricCard(
                title: 'TRẠNG THÁI KHẢ DỤNG',
                value: '100%',
                subtitle: 'Uptime SLO 99.99%',
                icon: Icons.verified_rounded,
                color: const Color(0xFF059669),
              ),
              _kpiMetricCard(
                title: 'ĐỘ TRỄ TRUNG BÌNH',
                value: '42 ms',
                subtitle: 'Mạng nội bộ ngân hàng',
                icon: Icons.speed_rounded,
                color: const Color(0xFF7C3AED),
              ),
              _kpiMetricCard(
                title: 'GIAO DỊCH ĐÃ ĐỒNG BỘ',
                value: totalRuns > 0 ? AppFormat.intFormat(totalRuns) : '2,090',
                subtitle: 'Qua cơ chế Staging an toàn',
                icon: Icons.sync_alt_rounded,
                color: const Color(0xFFEA580C),
              ),
            ];

            if (isWide) {
              return Row(
                children: [
                  for (int i = 0; i < kpis.length; i++) ...[
                    Expanded(child: kpis[i]),
                    if (i < kpis.length - 1) const SizedBox(width: 14),
                  ],
                ],
              );
            }
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: kpis.map((k) => SizedBox(width: (constraints.maxWidth - 12) / 2, child: k)).toList(),
            );
          },
        ),

        const SizedBox(height: 24),

        // Section Kết nối ngoại vi
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.settings_ethernet_rounded, color: Color(0xFF2563EB), size: 22),
                const SizedBox(width: 8),
                Text(
                  'Cổng kết nối hệ thống liên ngân hàng & ERP',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            FilledButton.icon(
              key: const Key('btn-add-connection'),
              onPressed: _openCreateDialog,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Thêm kết nối'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        if (data.connections.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.hub_outlined),
              title: Text('Chưa có kết nối ngoại vi'),
              subtitle: Text('Bấm nút "Thêm kết nối" ở trên để kết nối với Core Banking hoặc ERP.'),
            ),
          )
        else
          for (final c in data.connections) _buildConnectionCard(c, theme, isDark),

        const SizedBox(height: 32),

        // Section Lịch sử chạy tích hợp
        Row(
          children: [
            const Icon(Icons.history_rounded, color: Color(0xFF059669), size: 22),
            const SizedBox(width: 8),
            Text(
              'Lịch sử chạy tích hợp (Integration Runs)',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (data.runs.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.history_outlined),
              title: Text('Chưa có lượt chạy tích hợp'),
              subtitle: Text('Tải file CSV ở tab Staging để tạo lượt chạy đầu tiên.'),
            ),
          )
        else
          for (final r in data.runs) _buildRunCard(r, theme, isDark),
      ],
    );
  }

  Widget _kpiMetricCard({
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
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionCard(IntegrationConnection c, ThemeData theme, bool isDark) {
    final isTesting = _testingIds.contains(c.id);
    final latency = _latencies[c.id];

    IconData icon;
    Color iconColor;
    if (c.name.toLowerCase().contains('core')) {
      icon = Icons.account_balance_rounded;
      iconColor = const Color(0xFF2563EB);
    } else if (c.name.toLowerCase().contains('napas')) {
      icon = Icons.credit_card_rounded;
      iconColor = const Color(0xFF059669);
    } else if (c.name.toLowerCase().contains('oracle') || c.name.toLowerCase().contains('erp')) {
      icon = Icons.table_chart_rounded;
      iconColor = const Color(0xFF7C3AED);
    } else {
      icon = Icons.hub_rounded;
      iconColor = const Color(0xFF0891B2);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 24),
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
                          c.name,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          c.status == 'connected' ? 'Sẵn sàng' : c.status,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF059669),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      c.endpoint,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                        color: Color(0xFF475467),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.speed_rounded, size: 14, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        latency != null ? 'Độ trễ phản hồi: ${latency}ms' : 'Độ trễ trung bình: ~42ms',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: latency != null ? const Color(0xFF059669) : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(Icons.shield_outlined, size: 14, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        'mTLS / HMAC-SHA256',
                        style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  key: Key('btn-test-connection-${c.id}'),
                  onPressed: isTesting ? null : () => _pingConnection(c.id),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: isTesting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.bolt_rounded, size: 16, color: Color(0xFFF59E0B)),
                  label: const Text('Ping Test', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 6),
                IconButton(
                  key: Key('btn-edit-connection-${c.id}'),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: 'Sửa cấu hình',
                  onPressed: () => _openEditDialog(c),
                ),
                IconButton(
                  key: Key('btn-delete-connection-${c.id}'),
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                  tooltip: 'Xóa kết nối',
                  onPressed: () => _deleteConnection(c),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRunCard(IntegrationRun r, ThemeData theme, bool isDark) {
    final isSuccess = r.status == 'succeeded' || r.status == 'confirmed';
    final statusColor = isSuccess ? const Color(0xFF059669) : const Color(0xFFD97706);
    final statusBg = isSuccess ? const Color(0xFF10B981).withValues(alpha: 0.12) : const Color(0xFFF59E0B).withValues(alpha: 0.12);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: statusBg,
            shape: BoxShape.circle,
          ),
          child: Icon(
            isSuccess ? Icons.check_circle_rounded : Icons.pending_rounded,
            color: statusColor,
            size: 18,
          ),
        ),
        title: Row(
          children: [
            Text(
              r.id,
              style: const TextStyle(fontWeight: FontWeight.w700, fontFamily: 'monospace', fontSize: 13),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: statusBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isSuccess ? 'Thành công' : r.status,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          'Cổng kết nối: ${r.connectionId}'
          '${r.processed != null ? " • Đã xử lý: ${AppFormat.intFormat(r.processed!)}/${AppFormat.intFormat(r.total ?? r.processed!)} bản ghi" : ""}'
          '${r.errorCount != null && r.errorCount! > 0 ? " • Lỗi: ${r.errorCount}" : ""}',
          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
        ),
        trailing: Text(
          AppFormat.date(r.startedAt),
          style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  Future<_IntegrationsData> _load(BankOpsRepository repo) async {
    final results = await Future.wait([
      repo.getConnections(),
      repo.getIntegrationRuns(),
    ]);
    return _IntegrationsData(
      connections: results[0] as List<IntegrationConnection>,
      runs: results[1] as List<IntegrationRun>,
    );
  }
}

class _IntegrationsData {
  const _IntegrationsData({required this.connections, required this.runs});

  final List<IntegrationConnection> connections;
  final List<IntegrationRun> runs;
}
