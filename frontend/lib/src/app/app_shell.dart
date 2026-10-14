import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/models/dtos.dart';
import '../data/repositories/bankops_repository.dart';
import '../core/theme/app_tokens.dart';
import '../core/util/role_visibility.dart';
import '../core/widgets/app_screen.dart';
import '../core/widgets/app_toast.dart';
import '../core/widgets/global_search.dart';
import '../core/widgets/user_avatar.dart';
import 'theme_mode_controller.dart';
import '../data/repositories/http_bankops_repository.dart';
import '../features/activity/activity_screen.dart';
import '../features/approvals/approvals_screen.dart';
import '../features/auth/auth_service.dart';
import '../features/cash/cash_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/inventory/inventory_screen.dart';
import '../features/integrations/integrations_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/requests/requests_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/ai/ai_assistant_dialog.dart';

class SessionScope extends InheritedWidget {
  const SessionScope({super.key, required super.child, this.user, this.onSignOut});
  final AppUser? user;
  final Future<void> Function()? onSignOut;

  static SessionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SessionScope>();

  @override
  bool updateShouldNotify(SessionScope old) =>
      old.user != user || old.onSignOut != onSignOut;
}

class RepositoryScope extends InheritedWidget {
  const RepositoryScope({super.key, required this.repository, required super.child});

  final BankOpsRepository repository;

  static BankOpsRepository? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RepositoryScope>()?.repository;

  static BankOpsRepository of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RepositoryScope>()!.repository;

  @override
  bool updateShouldNotify(RepositoryScope old) => repository != old.repository;
}

/// Shell 3-tier theo docs/07-flutter.md:
/// <600 bottom nav 4 mục + More | 600–1199 rail | >=1200 sidebar + topbar.
class AppShell extends StatefulWidget {
  const AppShell({super.key, this.repository});

  final BankOpsRepository? repository;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  BankOpsRepository? _repository;
  int _index = 0;
  int _refreshTick = 0;
  StreamSubscription<String>? _approvalSub;
  int _pendingApprovalCount = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.repository != null) {
      _repository = widget.repository;
    } else if (_repository == null) {
      final auth = Provider.of<AuthService?>(context, listen: false);
      _repository = HttpBankOpsRepository(
        baseUrl: auth?.apiBaseUrl,
        tokenProvider: auth?.getAccessToken,
      );
    }
    _initApprovalSubscription();
  }

  @override
  void dispose() {
    _approvalSub?.cancel();
    _repository?.dispose();
    super.dispose();
  }

  void _initApprovalSubscription() {
    _approvalSub?.cancel();
    final repo = _repository;
    if (repo != null) {
      _fetchPendingCount(repo);
      _approvalSub = repo.approvalNotifications.listen((event) {
        if (mounted) {
          _fetchPendingCount(repo);
          if (event.startsWith('new_request:') && _canAccessApprovals(SessionScope.maybeOf(context))) {
            AppToast.info(context, '🔔 Yêu cầu mới chờ phê duyệt kiểm soát kép (Dual Control)!');
          }
        }
      });
    }
  }

  Future<void> _fetchPendingCount(BankOpsRepository repo) async {
    try {
      final items = await repo.getApprovalInbox();
      if (mounted) {
        setState(() {
          _pendingApprovalCount = items.length;
        });
      }
    } catch (_) {}
  }


  static const _items = <_Item>[
    _Item(0, 'Tổng quan', Icons.dashboard_outlined, Icons.dashboard),
    _Item(1, 'Kho', Icons.inventory_2_outlined, Icons.inventory_2),
    _Item(2, 'Quỹ', Icons.savings_outlined, Icons.savings),
    _Item(3, 'Yêu cầu', Icons.receipt_long_outlined, Icons.receipt_long),
    _Item(4, 'Duyệt', Icons.fact_check_outlined, Icons.fact_check),
    _Item(5, 'Tích hợp', Icons.hub_outlined, Icons.hub),
    _Item(6, 'Hoạt động', Icons.timeline_outlined, Icons.timeline),
    _Item(7, 'Báo cáo', Icons.insert_chart_outlined, Icons.insert_chart),
    _Item(8, 'Cài đặt', Icons.settings_outlined, Icons.settings),
  ];

  static const _slugs = <String>[
    'dashboard',
    'inventory',
    'cash',
    'requests',
    'approvals',
    'integrations',
    'activity',
    'reports',
    'settings',
  ];

  static const _titles = <String>[
    'Tổng quan',
    'Kho',
    'Quỹ',
    'Yêu cầu',
    'Duyệt',
    'Tích hợp',
    'Hoạt động',
    'Báo cáo',
    'Cài đặt',
  ];

  static const _icons = <IconData>[
    Icons.dashboard_outlined,
    Icons.inventory_2_outlined,
    Icons.savings_outlined,
    Icons.receipt_long_outlined,
    Icons.fact_check_outlined,
    Icons.hub_outlined,
    Icons.timeline_outlined,
    Icons.insert_chart_outlined,
    Icons.settings_outlined,
  ];

  static const _filled = <IconData>[
    Icons.dashboard,
    Icons.inventory_2,
    Icons.savings,
    Icons.receipt_long,
    Icons.fact_check,
    Icons.hub,
    Icons.timeline,
    Icons.insert_chart,
    Icons.settings,
  ];

  bool _canAccessApprovals(SessionScope? session) {
    final user = session?.user;
    if (user == null) return true; // Giữ nguyên cho unauthenticated & widget tests
    return user.roles.any((r) =>
        ['approver', 'checker'].contains(r.toLowerCase()));
  }

  Widget _screenFor(int i, SessionScope? session) {
    if (i == 4 && !_canAccessApprovals(session)) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.gpp_bad_outlined, size: 64, color: Color(0xFFF59E0B)),
              const SizedBox(height: 16),
              const Text(
                'Từ chối quyền truy cập',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tài khoản của bạn không có vai trò Kiểm soát viên (Checker) hoặc Quản trị viên để truy cập danh sách phê duyệt chứng từ.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                icon: const Icon(Icons.arrow_back),
                label: const Text('Quay lại Tổng quan'),
                onPressed: () => setState(() => _index = 0),
              ),
            ],
          ),
        ),
      );
    }
    switch (i) {
      case 0:
        return DashboardScreen(onNavigate: _go);
      case 1:
        return const InventoryScreen();
      case 2:
        return const CashScreen();
      case 3:
        return const RequestsScreen();
      case 4:
        return const ApprovalsScreen();
      case 5:
        return const IntegrationsScreen();
      case 6:
        return const ActivityScreen();
      case 7:
        return const ReportsScreen();
      case 8:
        return const SettingsScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _reload() async {
    setState(() => _refreshTick++);
  }

  void _openSettings() {
    _go(8);
  }

  Future<void> _openSearch() async {
    final repo = _repository;
    if (repo == null) return;
    final tab = await showGlobalSearch(context, repo);
    if (tab != null && mounted) _go(tab);
  }

  /// Điều hướng có kiểm tra quyền hiển thị theo vai trò (RoleVisibility).
  /// Tab bị ẩn với role hiện tại -> toast + ở yên, không chuyển.
  void _go(int i) {
    final session = SessionScope.maybeOf(context);
    final roles = RoleVisibility.rolesOf(session?.user);
    if (!RoleVisibility.visibleTabs(roles).contains(i)) {
      AppToast.info(
          context, 'Vai trò của bạn không có quyền vào phân hệ này');
      return;
    }
    setState(() => _index = i);
  }

  Future<void> _signOut() async {
    await SessionScope.maybeOf(context)?.onSignOut?.call();
    if (mounted) setState(() => _index = 0);
  }

  /// Slot 3 của bottom-bar compact: Duyệt (có quyền duyệt) -> Yêu cầu
  /// (có quyền tạo) -> Hoạt động (auditor thuần, chỉ xem).
  int _compactSlot3(SessionScope? session) {
    if (_canAccessApprovals(session)) return 4;
    final roles = RoleVisibility.rolesOf(session?.user);
    if (RoleVisibility.canCreate(roles)) return 3;
    return 6;
  }

  /// Bar chỉ có 5 slot: 0-2 map thẳng _index, slot 3 = tab _compactSlot3,
  /// slot 4 = Thêm (mở sheet).
  int _bottomSelected(SessionScope? session) {
    if (_index >= 0 && _index <= 2) return _index;
    if (_index == _compactSlot3(session)) return 3;
    return 4;
  }

  Widget _destination(String label, int index,
      {IconData? icon, IconData? selectedIcon, Key? key}) {
    return NavigationDestination(
      key: key,
      icon: Icon(icon ?? _icons[index], size: 22),
      selectedIcon: Icon(selectedIcon ?? _filled[index], size: 22),
      label: label,
    );
  }

  Widget _bottomBar({SessionScope? session}) {
    final slot3 = _compactSlot3(session);
    return NavigationBar(
      selectedIndex: _bottomSelected(session),
      onDestinationSelected: (i) {
        if (i == 4) {
          _openMoreSheet(session: session);
          return;
        }
        setState(() => _index = i == 3 ? slot3 : i);
      },
      height: 64,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: [
        _destination('Tổng quan', 0, key: const Key('nav-bottom-dashboard')),
        _destination('Kho', 1, key: const Key('nav-bottom-inventory')),
        _destination('Quỹ', 2, key: const Key('nav-bottom-cash')),
        _slot3Destination(slot3),
        _destination('Thêm', 4,
            icon: Icons.more_horiz_outlined,
            selectedIcon: Icons.expand_more,
            key: const Key('nav-bottom-more')),
      ],
    );
  }

  /// Slot 3 hiển thị đúng nhãn/icon/key theo tab + badge số chờ duyệt.
  Widget _slot3Destination(int slot3) {
    if (slot3 == 4) {
      final badgeCount = _pendingApprovalCount;
      Widget badge(IconData icon) {
        final ic = Icon(icon, size: 22);
        if (badgeCount <= 0) return ic;
        return Badge(
          label: Text('$badgeCount'),
          child: ic,
        );
      }
      return NavigationDestination(
        key: const Key('nav-bottom-approvals'),
        icon: badge(_icons[4]),
        selectedIcon: badge(_filled[4]),
        label: 'Duyệt',
      );
    }
    if (slot3 == 3) {
      return _destination('Yêu cầu', 3,
          key: const Key('nav-bottom-requests'));
    }
    return _destination('Hoạt động', 6,
        key: const Key('nav-bottom-activity'));
  }

  void _openMoreSheet({SessionScope? session}) {
    final canApprove = _canAccessApprovals(session);
    final roles = RoleVisibility.rolesOf(session?.user);
    final visibleItems = _items
        .where((it) =>
            (it.index != 4 || canApprove) &&
            RoleVisibility.visibleTabs(roles).contains(it.index))
        .toList();
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(title: Text('Chọn màn'), leading: Icon(Icons.list_alt_outlined)),
          const Divider(),
          ...visibleItems.map((it) => ListTile(
                leading: const Icon(Icons.arrow_forward_ios, size: 16),
                title: Text(_titles[it.index]),
                dense: true,
                onTap: () {
                  Navigator.of(context).pop();
                  setState(() => _index = it.index);
                },
              )),
        ],
      ),
    );
  }

  Widget _navRail({required double width, SessionScope? session}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isWide = width >= 200;
    final canApprove = _canAccessApprovals(session);
    final roles = RoleVisibility.rolesOf(session?.user);
    final visibleItems = _items
        .where((it) =>
            (it.index != 4 || canApprove) &&
            RoleVisibility.visibleTabs(roles).contains(it.index))
        .toList();

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        border: Border(
          right: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E3A8A),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.account_balance,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                if (isWide) ...[
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'BankOps',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          'Enterprise Core',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF64748B),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(radius: 3, backgroundColor: Color(0xFF10B981)),
                        SizedBox(width: 4),
                        Text(
                          'LIVE',
                          style: TextStyle(
                            color: Color(0xFF059669),
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              itemCount: visibleItems.length,
              itemBuilder: (context, i) {
                final item = visibleItems[i];
                final selected = _index == item.index;

                // Category header on wide layout
                Widget? sectionHeader;
                if (isWide) {
                  if (item.index == 0) {
                    sectionHeader = _buildNavSectionHeader('VẬN HÀNH KHO QUỸ');
                  } else if (item.index == 3) {
                    sectionHeader = _buildNavSectionHeader('KIỂM SOÁT 4 MẮT');
                  } else if (item.index == 5) {
                    sectionHeader = _buildNavSectionHeader('HỆ THỐNG & ĐỐI SOÁT');
                  }
                }

                final navBtn = Container(
                  height: 44,
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    color: selected
                        ? (isDark
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFEFF6FF))
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: selected
                        ? Border.all(
                            color: isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFBFDBFE),
                            width: 1,
                          )
                        : null,
                  ),
                  child: InkWell(
                    key: Key('nav-${_slugs[item.index]}'),
                    onTap: () => setState(() => _index = item.index),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isWide ? 12 : 8,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisAlignment: isWide
                            ? MainAxisAlignment.start
                            : MainAxisAlignment.center,
                        children: [
                          Icon(
                            selected ? item.filled : item.icon,
                            size: 20,
                            color: selected
                                ? const Color(0xFF2563EB)
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          if (isWide) ...[
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                item.label,
                                style: TextStyle(
                                  color: selected
                                      ? (isDark ? Colors.white : const Color(0xFF1E3A8A))
                                      : theme.colorScheme.onSurface,
                                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                            if (item.index == 4) // Approvals tab badge
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (_pendingApprovalCount > 0 ? const Color(0xFFDC2626) : const Color(0xFFF59E0B))
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  _pendingApprovalCount > 0 ? '$_pendingApprovalCount CHỜ DUYỆT' : '4-EYES',
                                  style: TextStyle(
                                    color: _pendingApprovalCount > 0 ? const Color(0xFFDC2626) : const Color(0xFFD97706),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );

                if (sectionHeader != null) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      sectionHeader,
                      navBtn,
                    ],
                  );
                }
                return navBtn;
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  PreferredSizeWidget _topBar({SessionScope? session}) {
    final theme = Theme.of(context);
    final user = session?.user;
    final role = user?.roles.isNotEmpty == true ? user!.roles.first.toUpperCase() : 'STAFF';

    Color roleColor;
    if (role.contains('MAKER')) {
      roleColor = const Color(0xFF2563EB);
    } else if (role.contains('CHECKER')) {
      roleColor = const Color(0xFF7C3AED);
    } else if (role.contains('ADMIN')) {
      roleColor = const Color(0xFF059669);
    } else {
      roleColor = const Color(0xFF475467);
    }

    // Màn hẹp (<600): chỉ giữ search + chuông + avatar để AppBar không tràn.
    // Refresh dùng kéo-thả, theme/cài đặt vào qua More sheet và menu avatar.
    final compact = MediaQuery.sizeOf(context).width < 600;

    return AppBar(
      title: Row(
        children: [
          Icon(
            _icons[_index],
            size: 20,
            color: const Color(0xFF2563EB),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              _titles[_index],
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      centerTitle: false,
      backgroundColor: theme.colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 1,
      actions: [
        IconButton(
          key: const Key('topbar-search-btn'),
          icon: const Icon(Icons.search_rounded, size: 20),
          onPressed: _openSearch,
          tooltip: 'Tìm kiếm toàn cục (Ctrl+K)',
        ),
        IconButton(
          key: const Key('topbar-refresh-btn'),
          icon: const Icon(Icons.refresh_rounded, size: 20),
          onPressed: _reload,
          tooltip: 'Làm mới dữ liệu',
        ),
        if (_canAccessApprovals(session))
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                key: const Key('topbar-approvals-notif-btn'),
                icon: const Icon(Icons.notifications_outlined, size: 20),
                tooltip: 'Hộp thư duyệt: $_pendingApprovalCount yêu cầu',
                onPressed: () => setState(() => _index = 4),
              ),
              if (_pendingApprovalCount > 0)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Color(0xFFDC2626),
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      '$_pendingApprovalCount',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        if (!compact)
          IconButton(
            icon: Icon(
              theme.brightness == Brightness.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
              size: 20,
            ),
            tooltip: 'Chuyển giao diện Sáng / Tối',
            onPressed: () {
              // ignore: use_build_context_synchronously
              final ctrl = Provider.of<ThemeModeController?>(context, listen: false);
              if (ctrl != null) {
                ctrl.setMode(
                  theme.brightness == Brightness.dark ? ThemeMode.light : ThemeMode.dark,
                );
              }
            },
          ),
        if (!compact)
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 20),
            onPressed: _openSettings,
            tooltip: 'Cài đặt hệ thống',
          ),
        const SizedBox(width: 8),
        Container(
          height: 36,
          padding: const EdgeInsets.only(left: 8, right: 4),
          decoration: BoxDecoration(
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!compact) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: roleColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    role,
                    style: TextStyle(
                      color: roleColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  user?.displayName ?? 'Khách',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ],
              PopupMenuButton<String>(
                key: const Key('topbar-user-menu'),
                icon: user != null
                    ? UserAvatar(name: user.displayName, size: 26)
                    : const UserAvatar(size: 26),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                tooltip: user?.displayName ?? 'Tài khoản',
                itemBuilder: (context) => [
                  if (user != null) ...[
                    PopupMenuItem(
                      enabled: false,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.displayName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            user.username,
                            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'settings',
                      child: ListTile(
                        leading: Icon(Icons.settings, size: 18),
                        title: Text('Cài đặt'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuDivider(),
                  ],
                  const PopupMenuItem(
                    key: Key('menu-signout'),
                    value: 'signout',
                    child: ListTile(
                      leading: Icon(Icons.logout_rounded, size: 18, color: Colors.red),
                      title: Text('Đăng xuất', style: TextStyle(color: Colors.red)),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
                onSelected: (v) {
                  if (v == 'settings') _openSettings();
                  if (v == 'signout') _signOut();
                },
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.maybeOf(context);
    final layout = Breakpoints.fromWidth(MediaQuery.sizeOf(context).width);

    final body = AppScreen(
      body: KeyedSubtree(
        key: ValueKey('screen-$_index-$_refreshTick-${session?.user?.id ?? ''}'),
        child: _screenFor(_index, session),
      ),
      header: _index == 0 ? const _DashboardHeader() : null,
      onRefresh: _reload,
    );

    if (layout.isWide) return _shortcutWrapper(_wide(session, body));
    if (layout.isMedium) return _shortcutWrapper(_medium(session, body));
    return _shortcutWrapper(_compact(session, body));
  }

  /// Phím tắt toàn cục: `Ctrl+K` mở tìm kiếm từ mọi màn.
  Widget _shortcutWrapper(Widget page) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _openSearch,
      },
      child: Focus(autofocus: true, child: page),
    );
  }

  Widget _wide(SessionScope? session, Widget body) {
    return RepositoryScope(repository: _repository!, child: Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('btn-ai-assistant'),
        onPressed: () => AiAssistantDialog.show(context),
        icon: const Icon(Icons.psychology_outlined),
        label: const Text('Trợ lý AI'),
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
      ),
      body: Row(
        children: [
          _navRail(width: 256, session: session),
          const VerticalDivider(width: 8, thickness: 1),
          Expanded(
            child: Column(
              children: [
                _topBar(session: session),
                Expanded(child: body),
              ],
            ),
          ),
        ],
      ),
    ));
  }

  Widget _medium(SessionScope? session, Widget body) {
    return RepositoryScope(repository: _repository!, child: Scaffold(
      floatingActionButton: FloatingActionButton(
        key: const Key('btn-ai-assistant'),
        onPressed: () => AiAssistantDialog.show(context),
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        tooltip: 'Trợ lý AI',
        child: const Icon(Icons.psychology_outlined),
      ),
      appBar: _topBar(session: session),
      body: Row(
        children: [
          _navRail(width: 88, session: session),
          const VerticalDivider(width: 8, thickness: 1),
          Expanded(child: body),
        ],
      ),
    ));
  }

  Widget _compact(SessionScope? session, Widget body) {
    return RepositoryScope(repository: _repository!, child: Scaffold(
      floatingActionButton: FloatingActionButton(
        key: const Key('btn-ai-assistant'),
        onPressed: () => AiAssistantDialog.show(context),
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        tooltip: 'Trợ lý AI',
        child: const Icon(Icons.psychology_outlined),
      ),
      appBar: _topBar(session: session),
      body: body,
      bottomNavigationBar: _bottomBar(session: session),
    ));
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class _Item {
  const _Item(this.index, this.label, this.icon, this.filled);
  final int index;
  final String label;
  final IconData icon;
  final IconData filled;
}

