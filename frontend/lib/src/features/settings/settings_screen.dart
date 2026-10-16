import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:qr_flutter/qr_flutter.dart';

import '../../app/app_shell.dart';
import '../../app/theme_mode_controller.dart';
import '../../core/i18n/locale_controller.dart';
import '../../core/theme/app_ui_settings_controller.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/util/web_helpers.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/section_header.dart';
import '../../core/util/role_visibility.dart';
import '../../data/repositories/bankops_repository.dart';
import '../../core/widgets/user_avatar.dart';
import '../admin/employee_management_screen.dart';
import '../auth/auth_service.dart';
import '../etl/etl_run_screen.dart';
import '../etl/etl_studio_screen.dart';
import 'widgets/change_password_dialog.dart';
import 'widgets/change_pin_dialog.dart';
import 'widgets/edit_profile_dialog.dart';

/// Màn Cài đặt: chọn giao diện, hồ sơ cá nhân, bảo mật tài khoản & kiểm soát viên,
/// kiểm tra kết nối API hệ thống và đăng xuất.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

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
    final themeController = context.watch<ThemeModeController?>();
    final uiSettings = context.watch<AppUiSettingsController?>();
    final localeController = context.watch<LocaleController?>();
    final isDark = sc.brightness == Brightness.dark;
    final user = auth.user;
    final currentMode =
        uiSettings?.mode ?? themeController?.mode ?? ThemeMode.system;
    final activePreset = uiSettings?.colorPreset ?? AppColorPreset.matcha;
    final activeDensity = uiSettings?.density ?? AppDensity.comfortable;
    final isVi = localeController?.isVietnamese ?? true;

    return Scaffold(
      appBar: AppBar(
        title: Text(isVi ? 'Cài đặt' : 'Settings'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Section Ngôn ngữ
            SectionHeader(
              title: isVi ? 'Ngôn ngữ hiển thị' : 'Display Language',
              showCount: false,
            ),
            const SizedBox(height: AppSpacing.md),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color:
                                sc.colorScheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.translate_rounded,
                              color: sc.colorScheme.primary, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isVi
                                  ? 'Tùy chọn ngôn ngữ ứng dụng'
                                  : 'Application Language',
                              style: sc.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              isVi
                                  ? 'Hệ thống tự động áp dụng và lưu cấu hình'
                                  : 'Changes apply instantly and are saved',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment<String>(
                          value: 'vi',
                          icon: Text('🇻🇳', style: TextStyle(fontSize: 16)),
                          label: Text('Tiếng Việt (Mặc định)'),
                        ),
                        ButtonSegment<String>(
                          value: 'en',
                          icon: Text('🇬🇧', style: TextStyle(fontSize: 16)),
                          label: Text('English (Global)'),
                        ),
                      ],
                      selected: {isVi ? 'vi' : 'en'},
                      onSelectionChanged: (selected) {
                        localeController?.setLocale(Locale(selected.first));
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Section Giao diện
            const SectionHeader(title: 'Giao diện', showCount: false),
            const SizedBox(height: AppSpacing.md),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Chế độ hiển thị
                    Text(
                      isVi
                          ? 'Chế độ hiển thị (Sáng / Tối)'
                          : 'Display Theme Mode',
                      style: sc.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
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
                      selected: {currentMode},
                      onSelectionChanged: (modes) {
                        if (uiSettings != null) {
                          uiSettings.setMode(modes.first);
                        } else {
                          themeController?.setMode(modes.first);
                        }
                      },
                    ),

                    const SizedBox(height: AppSpacing.lg),
                    const Divider(height: 1),
                    const SizedBox(height: AppSpacing.lg),

                    // 2. Màu sắc thương hiệu
                    Row(
                      children: [
                        Icon(Icons.palette_outlined,
                            color: sc.colorScheme.primary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          isVi
                              ? 'Bảng màu thương hiệu Trà Sữa (Brand Themes)'
                              : 'Brand Color Themes',
                          style: sc.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isVi
                          ? 'Tùy chỉnh sắc thái đại diện cho chuỗi quán trà sữa của bạn'
                          : 'Choose the visual personality for your tea franchise',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _ColorPresetCard(
                          preset: AppColorPreset.matcha,
                          name: isVi ? '🍵 Xanh Matcha' : '🍵 Fresh Matcha',
                          primaryColor: const Color(0xFF059669),
                          secondaryColor: const Color(0xFF10B981),
                          isSelected: activePreset == AppColorPreset.matcha,
                          onTap: () =>
                              uiSettings?.setColorPreset(AppColorPreset.matcha),
                        ),
                        _ColorPresetCard(
                          preset: AppColorPreset.milktea,
                          name: isVi
                              ? '🧋 Trà Sữa Cổ Điển'
                              : '🧋 Classic Milk Tea',
                          primaryColor: const Color(0xFF8D5B4C),
                          secondaryColor: const Color(0xFFD97706),
                          isSelected: activePreset == AppColorPreset.milktea,
                          onTap: () => uiSettings
                              ?.setColorPreset(AppColorPreset.milktea),
                        ),
                        _ColorPresetCard(
                          preset: AppColorPreset.oolong,
                          name: isVi
                              ? '🫐 Ô Long Thượng Hạng'
                              : '🫐 Royal Oolong',
                          primaryColor: const Color(0xFF1E293B),
                          secondaryColor: const Color(0xFF0284C7),
                          isSelected: activePreset == AppColorPreset.oolong,
                          onTap: () =>
                              uiSettings?.setColorPreset(AppColorPreset.oolong),
                        ),
                        _ColorPresetCard(
                          preset: AppColorPreset.berry,
                          name: isVi ? '🌸 Dâu & Trà Hoa' : '🌸 Sakura Berry',
                          primaryColor: const Color(0xFFBE185D),
                          secondaryColor: const Color(0xFFE11D48),
                          isSelected: activePreset == AppColorPreset.berry,
                          onTap: () =>
                              uiSettings?.setColorPreset(AppColorPreset.berry),
                        ),
                      ],
                    ),

                    const SizedBox(height: AppSpacing.lg),
                    const Divider(height: 1),
                    const SizedBox(height: AppSpacing.lg),

                    // 3. Mật độ hiển thị
                    Row(
                      children: [
                        Icon(Icons.view_compact_outlined,
                            color: sc.colorScheme.primary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          isVi ? 'Mật độ hiển thị giao diện' : 'Layout Density',
                          style: sc.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SegmentedButton<AppDensity>(
                      segments: [
                        ButtonSegment<AppDensity>(
                          value: AppDensity.comfortable,
                          icon: const Icon(Icons.touch_app_outlined, size: 18),
                          label: Text(isVi
                              ? 'Tiêu chuẩn (POS/Cảm ứng)'
                              : 'Comfortable (Touch POS)'),
                        ),
                        ButtonSegment<AppDensity>(
                          value: AppDensity.compact,
                          icon:
                              const Icon(Icons.density_small_rounded, size: 18),
                          label: Text(isVi
                              ? 'Gọn gàng (Kiểm kho/Audit)'
                              : 'Compact (Audit/Tables)'),
                        ),
                      ],
                      selected: {activeDensity},
                      onSelectionChanged: (densities) {
                        uiSettings?.setDensity(densities.first);
                      },
                    ),

                    const SizedBox(height: AppSpacing.lg),
                    const Divider(height: 1),
                    const SizedBox(height: AppSpacing.sm),

                    // 4. Bật/tắt thanh Live Ticker
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        isVi
                            ? 'Thanh cảnh báo kho & ca trực (Live Ticker)'
                            : 'Live Inventory & Shift Alert Bar',
                        style: sc.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        isVi
                            ? 'Ghim thanh cảnh báo nhanh trạng thái ca trực, tồn kho định mức và hạn sử dụng FEFO ở đầu trang'
                            : 'Pins real-time alert ticker for shift status, minimum safety stock and FEFO expiry at the top of the app',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                      ),
                      value: uiSettings?.showLiveTicker ?? true,
                      activeThumbColor: sc.colorScheme.primary,
                      onChanged: (val) => uiSettings?.setShowLiveTicker(val),
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
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0),
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
                          value: user?.effectiveEmail ?? 'demo@khotrasua.local',
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
                    subtitle:
                        const Text('Cập nhật mật khẩu tài khoản hiện tại'),
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
            const SectionHeader(
                title: 'Hệ thống & Cổng kết nối API', showCount: false),
            const SizedBox(height: AppSpacing.md),
            Card(
              child: FutureBuilder<HealthStatus>(
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
                  final dotColor =
                      alive ? const Color(0xFF10B981) : const Color(0xFFB42318);
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
                          icon:
                              const Icon(Icons.content_copy_outlined, size: 20),
                          tooltip: 'Sao chép địa chỉ API',
                          onPressed: () => _copy('địa chỉ API', apiUrl),
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
            ),
            const SizedBox(height: AppSpacing.lg),
            if (RoleVisibility.canManageEmployees(user) ||
                RoleVisibility.canAccessEtlStudio(user) ||
                RoleVisibility.canRunEtl(user)) ...[
              const SectionHeader(
                  title: 'IAM & Quản trị Hệ thống', showCount: false),
              const SizedBox(height: AppSpacing.md),
              Card(
                child: Column(
                  children: [
                    if (RoleVisibility.canManageEmployees(user))
                      ListTile(
                        key: const Key('settings-goto-employees-tile'),
                        leading: const Icon(Icons.manage_accounts_outlined,
                            color: Color(0xFF2563EB)),
                        title: const Text('Quản trị Nhân viên & Cấp phát IAM'),
                        subtitle: const Text(
                            'Tạo nhân viên, cấp mật khẩu tạm/thư mời, phân quyền và khóa tài khoản'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => RepositoryScope(
                                repository: RepositoryScope.of(context),
                                child: const EmployeeManagementScreen(),
                              ),
                            ),
                          );
                        },
                      ),
                    if (RoleVisibility.canAccessEtlStudio(user)) ...[
                      const Divider(height: 1),
                      ListTile(
                        key: const Key('settings-goto-etl-studio-tile'),
                        leading: const Icon(Icons.tune_outlined,
                            color: Color(0xFF059669)),
                        title: const Text('ETL Studio & Thiết kế Pipeline'),
                        subtitle: const Text(
                            'Cấu hình kết nối, pipeline nghiệp vụ, mapping version và lịch chạy'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
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
                    if (RoleVisibility.canRunEtl(user)) ...[
                      const Divider(height: 1),
                      ListTile(
                        key: const Key('settings-goto-etl-run-tile'),
                        leading: const Icon(Icons.play_circle_outline,
                            color: Color(0xFF7C3AED)),
                        title: const Text('Chạy Nhập Liệu ETL'),
                        subtitle: const Text(
                            'Nạp dữ liệu nguồn, chạy staging và kiểm tra kết quả'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
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
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            const SectionHeader(title: 'Ứng dụng', showCount: false),
            const SizedBox(height: AppSpacing.md),
            const _AppDownloadCard(),
            const SizedBox(height: AppSpacing.lg),
            Card(
              child: Column(
                children: [
                  const ListTile(
                    leading: Icon(Icons.shield_outlined),
                    title: Text('Quản Lý Kho Trà Sữa v1.0.0'),
                    subtitle: Text(
                      'Hệ thống quản lý nhập, xuất và tồn nguyên vật liệu quán trà sữa.',
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.exit_to_app),
                    title: const Text('Đăng xuất'),
                    onTap: () async {
                      await context.read<AuthService>().signOut();
                      if (context.mounted) {
                        Navigator.of(context)
                            .popUntil((route) => route.isFirst);
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
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
        'INVENTORY_CUSTODIAN' => 'THỦ KHO NGUYÊN LIỆU',
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
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
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

class _ColorPresetCard extends StatelessWidget {
  const _ColorPresetCard({
    required this.preset,
    required this.name,
    required this.primaryColor,
    required this.secondaryColor,
    required this.isSelected,
    required this.onTap,
  });

  final AppColorPreset preset;
  final String name;
  final Color primaryColor;
  final Color secondaryColor;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryColor.withValues(alpha: isDark ? 0.25 : 0.12)
              : (isDark ? const Color(0xFF1E293B) : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? primaryColor
                : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: primaryColor.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                gradient:
                    LinearGradient(colors: [primaryColor, secondaryColor]),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? (isDark ? Colors.white : primaryColor)
                    : (isDark
                        ? const Color(0xFFE2E8F0)
                        : const Color(0xFF334155)),
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 6),
              Icon(Icons.check_circle_rounded, size: 16, color: primaryColor),
            ],
          ],
        ),
      ),
    );
  }
}

class _AppDownloadCard extends StatefulWidget {
  const _AppDownloadCard();

  @override
  State<_AppDownloadCard> createState() => _AppDownloadCardState();
}

class _AppDownloadCardState extends State<_AppDownloadCard> {
  int _selectedPlatformTab = 0;

  static const String appUrl =
      'https://quan-ly-kho-tra-sua.tanmainguyenbinh.workers.dev';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 640;

            final qrBlock = Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: appUrl,
                    version: QrVersions.auto,
                    size: isCompact ? 140 : 160,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Color(0xFF1E293B),
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Quét mã mở trên điện thoại',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            );

            final actionsAndGuides = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.install_mobile_rounded,
                          color: Color(0xFF0284C7), size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Cài đặt & Tự động Đồng bộ Ứng dụng',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Quét mã mở trên mọi điện thoại (iOS, Android). Tự động đồng bộ và nạp phiên bản mới nhất.',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF10B981).withValues(alpha: 0.25),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.sync_rounded, size: 16, color: Color(0xFF059669)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tự động đồng bộ: Khi hệ thống cập nhật trên Cloudflare, ứng dụng trên điện thoại sẽ tự động nạp phiên bản mới mà không cần cài đặt lại.',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF065F46),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  key: const Key('btn-install-pwa'),
                  onPressed: () {
                    promptPwaInstall();
                    AppToast.info(context, 'Đang mở hộp thoại cài đặt ứng dụng...');
                  },
                  icon: const Icon(Icons.download_for_offline_rounded, size: 18),
                  label: const Text('Cài đặt Ứng dụng Di động (1-Click PWA)'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Text(
                  'Hướng dẫn thêm vào màn hình chính (Home Screen):',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(
                      value: 0,
                      label: Text('Android / Chrome'),
                      icon: Icon(Icons.android, size: 16),
                    ),
                    ButtonSegment(
                      value: 1,
                      label: Text('iPhone / Safari'),
                      icon: Icon(Icons.apple, size: 16),
                    ),
                    ButtonSegment(
                      value: 2,
                      label: Text('Zalo / Quét QR'),
                      icon: Icon(Icons.qr_code_scanner, size: 16),
                    ),
                  ],
                  selected: {_selectedPlatformTab},
                  onSelectionChanged: (val) {
                    setState(() => _selectedPlatformTab = val.first);
                  },
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: _buildGuideContent(_selectedPlatformTab),
                ),
              ],
            );

            if (isCompact) {
              return Column(
                children: [
                  qrBlock,
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  actionsAndGuides,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                qrBlock,
                const SizedBox(width: 24),
                Expanded(child: actionsAndGuides),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildGuideContent(int tabIndex) {
    switch (tabIndex) {
      case 0:
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '1. Mở website bằng trình duyệt Google Chrome trên điện thoại.\n'
              '2. Nhấn nút 3 chấm dọc (⋮) ở góc trên bên phải màn hình.\n'
              '3. Chọn "Cài đặt ứng dụng" (hoặc "Thêm vào màn hình chính").\n'
              '4. Biểu tượng ứng dụng Quản Lý Kho Trà Sữa sẽ xuất hiện ngay trên màn hình chính của bạn.',
              style: TextStyle(fontSize: 12.5, height: 1.5),
            ),
          ],
        );
      case 1:
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '1. Mở website bằng trình duyệt Safari trên iPhone / iPad.\n'
              '2. Nhấn vào nút Chia sẻ (biểu tượng hình vuông có mũi tên chỉ lên ⎋ ở thanh dưới).\n'
              '3. Cuộn xuống và chọn "Thêm vào MH chính" (Add to Home Screen).\n'
              '4. Nhấn "Thêm" ở góc trên bên phải để hoàn tất.',
              style: TextStyle(fontSize: 12.5, height: 1.5),
            ),
          ],
        );
      case 2:
      default:
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '1. Dùng ứng dụng Camera, Zalo hoặc ZaloPay để quét mã QR bên cạnh.\n'
              '2. Khi Zalo mở liên kết, hãy nhấn vào biểu tượng 3 chấm (⋯) ở góc trên bên phải.\n'
              '3. Chọn "Mở bằng trình duyệt" (Chrome / Safari).\n'
              '4. Sau đó tiến hành thêm vào màn hình chính theo hướng dẫn của hệ điều hành.',
              style: TextStyle(fontSize: 12.5, height: 1.5),
            ),
          ],
        );
    }
  }
}

