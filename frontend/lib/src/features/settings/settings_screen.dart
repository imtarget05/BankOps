import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/app_shell.dart';
import '../../app/theme_mode_controller.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/section_header.dart';
import '../../data/repositories/bankops_repository.dart';
import '../../core/widgets/user_avatar.dart';
import '../auth/auth_service.dart';
import 'widgets/change_password_dialog.dart';
import 'widgets/change_pin_dialog.dart';
import 'widgets/edit_profile_dialog.dart';

/// Màn Cài đặt (standalone, không phụ thuộc shell nav):
/// chọn theme + sức khoẻ hệ thống + dữ liệu demo + đăng xuất.
class SettingsScreen extends StatefulWidget {
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

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<HealthStatus>? _healthFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = RepositoryScope.maybeOf(context);
    if (repo != null) {
      _healthFuture ??= repo.getHealth();
    }
  }

  void _refreshHealth() {
    final repo = RepositoryScope.maybeOf(context);
    if (repo != null) {
      setState(() {
        _healthFuture = repo.getHealth();
      });
    }
  }

  Future<void> _copy(String label, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    AppToast.success(context, 'Đã sao chép $label');
  }

  @override
  Widget build(BuildContext context) {
    final sc = Theme.of(context);
    final auth = context.watch<AuthService>();
    final themeController = context.watch<ThemeModeController>();
    final isDark = sc.brightness == Brightness.dark;
    final user = auth.user;
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
          const SectionHeader(title: 'Hồ Sơ Của Tôi', showCount: false),
          const SizedBox(height: AppSpacing.md),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        children: [
                          UserAvatar(
                            name: user?.displayName ?? 'Khách',
                            size: 56,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isDark
                                      ? const Color(0xFF1E293B)
                                      : Colors.white,
                                  width: 2.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.displayName ?? 'Khách vãng lai',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '@${user?.username ?? 'guest'} · Mã NV: ${user?.effectiveEmployeeCode ?? 'BO-8892'}',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: isDark
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                for (final role in _uniqueDisplayRoles(
                                    user?.roles ?? ['staff']))
                                  _RoleBadge(role: role),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981)
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: const Color(0xFF10B981)
                                          .withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.check_circle_rounded,
                                          size: 12, color: Color(0xFF059669)),
                                      SizedBox(width: 4),
                                      Text(
                                        'Hoạt động',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF059669),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        key: const Key('settings-edit-profile-btn'),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Chỉnh sửa hồ sơ'),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                        ),
                        onPressed: () async {
                          final updated = await EditProfileDialog.show(
                            context,
                            user: user,
                          );
                          if (updated == true && context.mounted) {
                            AppToast.success(
                              context,
                              'Cập nhật hồ sơ cá nhân thành công!',
                            );
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 24,
                    runSpacing: 16,
                    children: [
                      _ProfileInfoItem(
                        icon: Icons.email_outlined,
                        label: 'Email liên hệ',
                        value: user?.effectiveEmail ?? 'demo@bankops.vn',
                      ),
                      _ProfileInfoItem(
                        icon: Icons.phone_outlined,
                        label: 'Số điện thoại',
                        value: user?.effectivePhone ?? '0901 234 567',
                      ),
                      _ProfileInfoItem(
                        icon: Icons.business_outlined,
                        label: 'Chi nhánh công tác',
                        value: user?.effectiveBranch ??
                            'Chi nhánh Bến Thành (Hội sở)',
                      ),
                      const _ProfileInfoItem(
                        icon: Icons.shield_outlined,
                        label: 'Tiêu chuẩn bảo mật',
                        value: 'ISO 27001 · Dual Control Active',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Tài khoản & Bảo mật', showCount: false),
          const SizedBox(height: AppSpacing.md),
          Card(
            child: Column(
              children: [
                ListTile(
                  key: const Key('settings-change-password-tile'),
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Đổi mật khẩu đăng nhập'),
                  subtitle: const Text('Cập nhật mật khẩu tài khoản hiện tại'),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () async {
                    final updated = await ChangePasswordDialog.show(context);
                    if (updated == true && context.mounted) {
                      AppToast.success(context, 'Đổi mật khẩu thành công!');
                    }
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  key: const Key('settings-change-pin-tile'),
                  leading: const Icon(Icons.pin_outlined),
                  title: const Text('Đổi mã PIN kiểm soát viên'),
                  subtitle: const Text(
                      'Mã PIN 6 số dùng để duyệt phiếu quỹ và kho'),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () async {
                    final updated = await ChangePinDialog.show(context);
                    if (updated == true && context.mounted) {
                      AppToast.success(
                          context, 'Đổi mã PIN kiểm soát viên thành công!');
                    }
                  },
                ),
              ],
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
                const ListTile(
                  leading: Icon(Icons.group_outlined),
                  title: Text('Tài khoản demo'),
                  subtitle: Text(
                    'Mật khẩu chung: ${SettingsScreen._demoPassword} — bấm icon để sao chép tên đăng nhập.',
                  ),
                ),
                for (final account in SettingsScreen._demoAccounts)
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
                          _copy('tên đăng nhập', account.$1),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Hệ thống', showCount: false),
          const SizedBox(height: AppSpacing.md),
          Card(
            child: Column(
              children: [
                FutureBuilder<HealthStatus>(
                  future: _healthFuture,
                  builder: (context, snapshot) {
                    final apiUrl = auth.apiBaseUrl;
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const ListTile(
                        leading: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        title: Text('Đang kiểm tra kết nối API…'),
                      );
                    }
                    final health = snapshot.data;
                    final alive = health?.alive ?? false;
                    final dotColor = alive
                        ? const Color(0xFF10B981)
                        : const Color(0xFFB42318);
                    final statusText = alive
                        ? 'API hoạt động · v${health!.version} · ${health.latencyMs}ms'
                        : 'Không kết nối được API';
                    return ListTile(
                      leading: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: dotColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      title: Text(statusText),
                      subtitle: Text(
                        alive
                            ? apiUrl
                            : '${health?.error ?? 'Lỗi không xác định'} · $apiUrl',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            key: const Key('settings-copy-api-url-btn'),
                            icon: const Icon(
                                Icons.content_copy_outlined,
                                size: 20),
                            tooltip: 'Sao chép địa chỉ API',
                            onPressed: () =>
                                _copy('địa chỉ API', apiUrl),
                          ),
                          IconButton(
                            key: const Key('settings-health-refresh-btn'),
                            icon: const Icon(Icons.refresh_rounded, size: 20),
                            tooltip: 'Kiểm tra lại',
                            onPressed: _refreshHealth,
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.restart_alt_outlined),
                  title: const Text('Reset demo về dữ liệu gốc'),
                  subtitle: const SelectableText(
                    SettingsScreen.resetCommand,
                    style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                  trailing: IconButton(
                    key: const Key('settings-copy-reset-cmd-btn'),
                    icon: const Icon(Icons.content_copy_outlined),
                    tooltip: 'Sao chép lệnh reset',
                    onPressed: () => _copy(
                        'lệnh reset', SettingsScreen.resetCommand),
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

  static List<String> _uniqueDisplayRoles(List<String> roles) {
    final result = <String>[];
    final seen = <String>{};
    for (final r in roles) {
      final label = _RoleBadge.roleLabel(r);
      if (seen.add(label)) {
        result.add(r);
      }
    }
    return result;
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});

  final String role;

  static String roleLabel(String role) => switch (role.toUpperCase()) {
        'MAKER' || 'STAFF' => 'GIAO DỊCH VIÊN (MAKER)',
        'CHECKER' || 'APPROVER' => 'KIỂM SOÁT VIÊN (CHECKER)',
        'AUDITOR' => 'KIỂM TOÁN VIÊN (AUDITOR)',
        'INVENTORY_CUSTODIAN' => 'THỦ KHO ẤN CHỈ',
        'CASH_SIMULATED_CUSTODIAN' => 'THỦ QUỸ',
        _ => role.toUpperCase(),
      };

  @override
  Widget build(BuildContext context) {
    final lower = role.toLowerCase();
    final isChecker = lower.contains('checker') || lower.contains('approver');
    final isAuditor = lower.contains('auditor') || lower.contains('audit');
    final isMaker = lower.contains('maker') || lower.contains('staff');

    final color = isChecker
        ? const Color(0xFF7C3AED)
        : isAuditor
            ? const Color(0xFF059669)
            : isMaker
                ? const Color(0xFF2563EB)
                : const Color(0xFF475569);

    final label = roleLabel(role);


    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _ProfileInfoItem extends StatelessWidget {
  const _ProfileInfoItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: 260,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color:
                  isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: const Color(0xFF0284C7)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
