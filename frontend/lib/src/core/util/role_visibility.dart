import '../../data/models/dtos.dart';

/// Phân quyền hiển thị menu theo vai trò — client chỉ ẨN/HIỆN,
/// backend vẫn là nơi thi hành RBAC thật (capability + Maker ≠ Checker).
///
/// Vai trò thực tế không nhất quán giữa các nguồn (backend seed:
/// admin/staff/approver/auditor; fallback HTTP: maker/checker/auditor),
/// nên mọi so sánh đều lowercase + cho phép rộng (allowlist).
class RoleVisibility {
  const RoleVisibility._();

  static const _creators = {
    'staff',
    'maker',
    'admin',
    'integration_admin',
  };
  static const _approvers = {
    'approver',
    'checker',
    'admin',
    'system_admin',
    'supervisor',
  };
  static const _privileged = {
    'staff',
    'maker',
    'admin',
    'integration_admin',
    'approver',
    'checker',
    'supervisor',
    'inventory_manager',
    'cash_sim_operator',
  };

  /// Roles lowercase của user; rỗng = chưa rõ (test/dev) -> hiện tất cả.
  static Set<String> rolesOf(AppUser? user) {
    if (user == null) return const {};
    return user.roles.map((e) => e.toLowerCase()).toSet();
  }

  /// Được tạo/gửi phiếu (Yêu cầu + Tích hợp staging).
  static bool canCreate(Set<String> roles) =>
      roles.isEmpty || roles.intersection(_creators).isNotEmpty;

  /// Được duyệt phiếu (Hộp thư duyệt).
  static bool canApprove(Set<String> roles) =>
      roles.isEmpty || roles.intersection(_approvers).isNotEmpty;

  static bool canManageCatalog(Set<String> roles) =>
      roles.isEmpty || roles.contains('admin') || roles.contains('inventory_manager');

  /// Auditor thuần: có nhãn auditor nhưng không có bất kỳ quyền tạo/duyệt nào.
  /// Chỉ trường hợp rõ ràng này mới bị ẩn tab (fail-open với role lạ).
  static bool isAuditorOnly(Set<String> roles) =>
      roles.isNotEmpty &&
      roles.contains('auditor') &&
      roles.intersection(_privileged).isEmpty;

  /// Quản trị nhân sự / cấp phát IAM (Phase 1).
  static bool canManageEmployees(AppUser? user) {
    if (user == null) return false;
    final email = user.email?.trim().toLowerCase();
    if (email == 'tanmainguyenbinh@gmail.com') return true;
    final roles = rolesOf(user);
    if (roles.contains('admin') || roles.contains('system_admin')) return true;
    final caps = user.capabilities.map((e) => e.toLowerCase()).toSet();
    return caps.contains('iam:admin') || caps.contains('admin:user_management');
  }

  /// ETL Studio (Phase 2): Cấu hình pipeline, mapping.
  static bool canAccessEtlStudio(AppUser? user) {
    if (user == null) return false;
    final roles = rolesOf(user);
    if (roles.contains('admin') || roles.contains('system_admin')) return true;
    final caps = user.capabilities.map((e) => e.toLowerCase()).toSet();
    return caps.contains('etl:admin') || caps.contains('etl:design');
  }

  /// Chạy nhập liệu ETL (Phase 2).
  static bool canRunEtl(AppUser? user) {
    if (user == null) return false;
    final roles = rolesOf(user);
    if (roles.contains('admin') || roles.contains('system_admin')) return true;
    final caps = user.capabilities.map((e) => e.toLowerCase()).toSet();
    return caps.contains('etl:run') || caps.contains('etl:admin');
  }

  /// Danh sách tab (full index theo AppShell) user được thấy.
  /// Pilot trà sữa: ẩn 2 Quỹ, 5 Tích hợp/ETL khỏi UI chính
  /// (backend giữ nguyên để rollback). Index giữ nguyên để không vỡ _go().
  /// 0 Tổng quan, 1 Kho, 2 Ca làm việc, 3 Yêu cầu, 4 Duyệt, 5 Tích hợp/ETL (ẩn),
  /// 6 Hoạt động, 7 Báo cáo, 8 Cài đặt, 9 Quản trị nhân viên.
  /// Vai trò hiển thị chuẩn SRS: Quản lý (admin/manager) và
  /// Nhân viên/Trưởng ca (staff).
  static const hiddenPilotTabs = {5};
  static List<int> visibleTabs(Set<String> roles, [AppUser? user]) {
    final list = <int>[0, 1, 2];
    if (!isAuditorOnly(roles)) {
      list.addAll([3, 4]);
    }
    list.addAll([6, 7, 8]);
    if ((user != null && canManageEmployees(user)) ||
        roles.contains('admin') ||
        roles.contains('system_admin')) {
      list.add(9);
    }
    return list;
  }

  /// Nhãn vai trò chuẩn kho F&B: Chủ Quán (Admin), Quản Lý Kho, Nhân Viên Pha Chế, Kiểm Soát.
  static String roleLabel(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
      case 'system_admin':
        return 'Chủ Quán (Admin)';
      case 'inventory_manager':
        return 'Quản Lý Kho / Cửa Hàng';
      case 'approver':
      case 'checker':
        return 'Quản Lý Ca Trực';
      case 'auditor':
        return 'Kiểm Soát Chất Lượng';
      case 'staff':
      case 'maker':
        return 'Nhân Viên Pha Chế / Quầy';
      default:
        return 'Nhân viên';
    }
  }
}
