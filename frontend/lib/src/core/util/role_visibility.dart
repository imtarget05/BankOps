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
  static const _approvers = {'approver', 'checker'};
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

  /// Danh sách tab (full index theo AppShell) user được thấy.
  /// 0 Tổng quan, 1 Kho, 2 Quỹ, 3 Yêu cầu, 4 Duyệt, 5 Tích hợp,
  /// 6 Hoạt động, 7 Báo cáo, 8 Cài đặt.
  static List<int> visibleTabs(Set<String> roles) {
    if (isAuditorOnly(roles)) return const [0, 1, 2, 6, 7, 8];
    return const [0, 1, 2, 3, 4, 5, 6, 7, 8];
  }
}
