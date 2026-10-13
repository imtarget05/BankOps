import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/theme_mode_controller.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/section_header.dart';
import '../auth/auth_service.dart';

/// Màn Cài đặt (standalone, không phụ thuộc shell nav):
/// chọn theme + thông tin bản demo + reset demo + đăng xuất.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  /// Lệnh reset toàn bộ dữ liệu demo về seed ban đầu (chạy ở thư mục repo).
  static const resetCommand =
      'docker compose down -v && docker compose up -d --build';

  static const _demoAccounts = <(String, String, String)>[
    ('demo_maker', 'Maker', 'Tạo & gửi duyệt phiếu'),
    ('demo_checker', 'Checker', 'Duyệt / từ chối phiếu'),
    ('demo_auditor', 'Auditor', 'Xem báo cáo & đối soát'),
  ];
  static const _demoPassword = 'DemoPass123!';

  Future<void> _copy(BuildContext context, String label, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    AppToast.success(context, 'Đã sao chép $label');
  }

  @override
  Widget build(BuildContext context) {
    final sc = Theme.of(context);
    final auth = context.watch<AuthService>();
    final themeController = context.watch<ThemeModeController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cài đặt'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          const SectionHeader(title: 'Giao diện', showCount: false),
          const SizedBox(height: AppSpacing.md),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Chế độ hiển thị', style: sc.textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.settings_suggest_outlined, size: 18),
                        label: Text('Hệ thống'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode_outlined, size: 18),
                        label: Text('Sáng'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode_outlined, size: 18),
                        label: Text('Tối'),
                      ),
                    ],
                    selected: {themeController.mode},
                    onSelectionChanged: (modes) =>
                        themeController.setMode(modes.first),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Tài khoản', showCount: false),
          const SizedBox(height: AppSpacing.md),
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(auth.user?.displayName ?? 'Khách'),
              subtitle: Text((auth.user?.roles ?? const []).join(', ')),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Dữ liệu demo', showCount: false),
          const SizedBox(height: AppSpacing.md),
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.science_outlined),
                  title: Text('Môi trường giả lập'),
                  subtitle: Text(
                    'Mọi tiền, quỹ, phiếu và danh tính đều là giả lập '
                    '(simulation: true). Không kết nối core banking.',
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.restart_alt_outlined),
                  title: const Text('Reset demo về dữ liệu gốc'),
                  subtitle: const SelectableText(
                    resetCommand,
                    style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                  trailing: IconButton(
                    key: const Key('settings-copy-reset-cmd-btn'),
                    icon: const Icon(Icons.content_copy_outlined),
                    tooltip: 'Sao chép lệnh reset',
                    onPressed: () =>
                        _copy(context, 'lệnh reset', resetCommand),
                  ),
                ),
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.group_outlined),
                  title: Text('Tài khoản demo'),
                  subtitle: Text(
                    'Mật khẩu chung: $_demoPassword — bấm icon để sao chép tên đăng nhập.',
                  ),
                ),
                for (final account in _demoAccounts)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.person_outline, size: 20),
                    title: Text(account.$1),
                    subtitle: Text('${account.$2} — ${account.$3}'),
                    trailing: IconButton(
                      key: Key('settings-copy-${account.$1}-btn'),
                      icon: const Icon(Icons.content_copy_outlined, size: 20),
                      tooltip: 'Sao chép ${account.$1}',
                      onPressed: () =>
                          _copy(context, 'tên đăng nhập', account.$1),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Ứng dụng', showCount: false),
          const SizedBox(height: AppSpacing.md),
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('BankOps 0.1.0+1'),
                  subtitle: Text('Bản demo — mọi dữ liệu là giả lập.'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.exit_to_app),
                  title: const Text('Đăng xuất'),
                  onTap: () async {
                    await context.read<AuthService>().signOut();
                    if (context.mounted) {
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
