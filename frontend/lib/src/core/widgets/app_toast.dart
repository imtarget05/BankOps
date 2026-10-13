import 'package:flutter/material.dart';

/// Toast (SnackBar) thống nhất toàn app — đợt A "chuyên nghiệp & dễ dùng".
///
/// Quy ước màu:
/// - success: xanh lá (duyệt, xác nhận, sao chép xong)
/// - error: đỏ (lỗi API, lỗi import)
/// - info: hổ phách (từ chối, cảnh báo nhẹ)
///
/// Cách dùng: `AppToast.success(context, 'Đã duyệt phiếu X')`.
/// Không thay đổi flow nghiệp vụ — chỉ chuẩn hoá hiển thị.
class AppToast {
  const AppToast._();

  static const Color _successBg = Color(0xFF059669);
  static const Color _errorBg = Color(0xFFB42318);
  static const Color _infoBg = Color(0xFFD97706);

  static void success(BuildContext context, String message) {
    _show(
      context,
      message: message,
      backgroundColor: _successBg,
      icon: Icons.check_circle_outline,
    );
  }

  static void error(BuildContext context, String message) {
    _show(
      context,
      message: message,
      backgroundColor: _errorBg,
      icon: Icons.error_outline,
    );
  }

  static void info(BuildContext context, String message) {
    _show(
      context,
      message: message,
      backgroundColor: _infoBg,
      icon: Icons.info_outline,
    );
  }

  static void _show(
    BuildContext context, {
    required String message,
    required Color backgroundColor,
    required IconData icon,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}
