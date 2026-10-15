import 'package:flutter/widgets.dart';

/// Hệ thống từ điển đa ngôn ngữ (Tiếng Việt & English).
class AppI18n {
  const AppI18n(this.locale);

  final Locale locale;

  bool get isVietnamese => locale.languageCode == 'vi';

  static const Map<String, Map<String, String>> _localizedValues = {
    'vi': {
      // Navigation
      'nav_dashboard': 'Tổng quan',
      'nav_inventory': 'Kho',
      'nav_shift_work': 'Ca làm việc',
      'nav_requests': 'Yêu cầu',
      'nav_approvals': 'Duyệt',
      'nav_activity': 'Hoạt động',
      'nav_reports': 'Báo cáo',
      'nav_settings': 'Cài đặt',
      'nav_employees': 'Nhân viên',
      'nav_more': 'Thêm',

      // Branding & Shell
      'app_title': 'Quản Lý Kho Trà Sữa',
      'branch_badge': 'CN Quận 1 · Quán Trà Sữa Đô Thị',
      'live_online': 'Trực tuyến',
      'search_placeholder': 'Tìm nguyên liệu, phiếu kho, ca trực... (Ctrl+K)',
      'quick_shift_alert':
          '⚡ Ca sáng đang mở kiểm kê · 3 nguyên liệu sắp đến hạn FEFO · 2 mặt hàng dưới định mức',

      // Common Actions
      'btn_save': 'Lưu thay đổi',
      'btn_cancel': 'Hủy bỏ',
      'btn_confirm': 'Xác nhận',
      'btn_approve': 'Phê duyệt',
      'btn_reject': 'Từ chối',
      'btn_search': 'Tìm kiếm',
      'btn_export': 'Xuất báo cáo',
      'btn_refresh': 'Làm mới',
      'btn_logout': 'Đăng xuất',
      'btn_edit_profile': 'Chỉnh sửa hồ sơ',
      'btn_change_password': 'Đổi mật khẩu',
      'btn_change_pin': 'Đổi mã PIN kiểm soát viên',
      'btn_close': 'Đóng',

      // Settings Screen
      'settings_title': 'Cài đặt',
      'settings_language_section': 'Ngôn ngữ (Language)',
      'settings_appearance_section': 'Giao diện & Trải nghiệm',
      'settings_theme_mode': 'Chế độ hiển thị',
      'settings_theme_system': 'Hệ thống',
      'settings_theme_light': 'Sáng',
      'settings_theme_dark': 'Tối',
      'settings_brand_color': 'Màu sắc thương hiệu (Theme Color)',
      'settings_color_matcha': 'Xanh Matcha',
      'settings_color_milktea': 'Trà Sữa Cổ Điển',
      'settings_color_oolong': 'Ô Long Hoàng Gia',
      'settings_color_berry': 'Trà Dâu Sakura',
      'settings_density': 'Mật độ hiển thị',
      'settings_density_comfortable': 'Tiêu chuẩn (Màn hình POS cảm ứng)',
      'settings_density_compact': 'Gọn gàng (Kiểm kho & Báo cáo)',
      'settings_ticker_toggle':
          'Hiển thị thanh cảnh báo trực tiếp (Live Ticker)',
      'settings_profile_section': 'Hồ Sơ Của Tôi',
      'settings_security_section': 'Bảo Mật Tài Khoản & Kiểm Soát Viên',
      'settings_system_section': 'Trạng thái kết nối hệ thống',
      'settings_copy_success': 'Đã sao chép vào bộ nhớ tạm',

      // Status & Shifts
      'shift_morning': 'Ca Sáng (07:30 - 15:00)',
      'shift_afternoon': 'Ca Chiều (15:00 - 23:00)',
      'shift_split': 'Ca Lỡ (07:30 - 18:00)',
      'status_draft': 'Bản nháp',
      'status_pending': 'Chờ duyệt',
      'status_approved': 'Đã duyệt',
      'status_rejected': 'Từ chối',
      'status_posted': 'Đã vào sổ',
      'status_low_stock': 'Dưới định mức',
      'status_expiring_soon': 'Sắp hết hạn',
      'status_normal': 'An toàn',
    },
    'en': {
      // Navigation
      'nav_dashboard': 'Dashboard',
      'nav_inventory': 'Inventory',
      'nav_shift_work': 'Shifts',
      'nav_requests': 'Requests',
      'nav_approvals': 'Approvals',
      'nav_activity': 'Activity',
      'nav_reports': 'Reports',
      'nav_settings': 'Settings',
      'nav_employees': 'Employees',
      'nav_more': 'More',

      // Branding & Shell
      'app_title': 'Milk Tea Inventory Ops',
      'branch_badge': 'Branch 1 · Urban Milk Tea Shop',
      'live_online': 'Online',
      'search_placeholder': 'Search ingredients, vouchers, shifts... (Ctrl+K)',
      'quick_shift_alert':
          '⚡ Morning shift active · 3 items near expiry (FEFO) · 2 items low stock',

      // Common Actions
      'btn_save': 'Save Changes',
      'btn_cancel': 'Cancel',
      'btn_confirm': 'Confirm',
      'btn_approve': 'Approve',
      'btn_reject': 'Reject',
      'btn_search': 'Search',
      'btn_export': 'Export Report',
      'btn_refresh': 'Refresh',
      'btn_logout': 'Sign Out',
      'btn_edit_profile': 'Edit Profile',
      'btn_change_password': 'Change Password',
      'btn_change_pin': 'Change Supervisor PIN',
      'btn_close': 'Close',

      // Settings Screen
      'settings_title': 'Settings',
      'settings_language_section': 'Language',
      'settings_appearance_section': 'Appearance & UX',
      'settings_theme_mode': 'Display Mode',
      'settings_theme_system': 'System',
      'settings_theme_light': 'Light',
      'settings_theme_dark': 'Dark',
      'settings_brand_color': 'Brand Color Theme',
      'settings_color_matcha': 'Matcha Green',
      'settings_color_milktea': 'Classic Milk Tea',
      'settings_color_oolong': 'Royal Oolong',
      'settings_color_berry': 'Sakura Berry',
      'settings_density': 'Layout Density',
      'settings_density_comfortable': 'Comfortable (POS Touchscreen)',
      'settings_density_compact': 'Compact (Inventory & Auditing)',
      'settings_ticker_toggle': 'Show Live Alert Ticker Bar',
      'settings_profile_section': 'My Profile',
      'settings_security_section': 'Account & Supervisor Security',
      'settings_system_section': 'System Connection Status',
      'settings_copy_success': 'Copied to clipboard',

      // Status & Shifts
      'shift_morning': 'Morning Shift (07:30 - 15:00)',
      'shift_afternoon': 'Afternoon Shift (15:00 - 23:00)',
      'shift_split': 'Split Shift (07:30 - 18:00)',
      'status_draft': 'Draft',
      'status_pending': 'Pending',
      'status_approved': 'Approved',
      'status_rejected': 'Rejected',
      'status_posted': 'Posted',
      'status_low_stock': 'Low Stock',
      'status_expiring_soon': 'Expiring Soon',
      'status_normal': 'Normal',
    },
  };

  String tr(String key, [Map<String, String>? params]) {
    final lang = locale.languageCode;
    var value =
        _localizedValues[lang]?[key] ?? _localizedValues['vi']?[key] ?? key;
    if (params != null) {
      params.forEach((paramKey, paramVal) {
        value = value.replaceAll('{$paramKey}', paramVal);
      });
    }
    return value;
  }
}

/// Extension tiện lợi trên BuildContext để gọi `context.tr('key')`.
extension AppI18nExtension on BuildContext {
  String tr(String key, [Map<String, String>? params]) {
    // Tìm LocaleController từ context nếu có
    final locale = Localizations.maybeLocaleOf(this) ?? const Locale('vi');
    return AppI18n(locale).tr(key, params);
  }
}
