import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/widgets/app_toast.dart';
import '../auth_service.dart';

/// Hộp thoại Đăng ký tài khoản mới cho BankOps.
class RegisterDialog extends StatefulWidget {
  const RegisterDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const RegisterDialog(),
    );
  }

  @override
  State<RegisterDialog> createState() => _RegisterDialogState();
}

class _RegisterDialogState extends State<RegisterDialog> {
  final _usernameCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _pinCtrl = TextEditingController(text: '123456');

  String _selectedRole = 'staff';
  bool _busy = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _displayNameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final username = _usernameCtrl.text.trim();
    final displayName = _displayNameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final confirm = _confirmPasswordCtrl.text;
    final pin = _pinCtrl.text.trim();

    if (username.isEmpty || username.length < 3) {
      setState(() => _errorMessage = 'Tên đăng nhập phải có ít nhất 3 ký tự.');
      return;
    }
    if (displayName.isEmpty) {
      setState(() => _errorMessage = 'Vui lòng nhập họ và tên hiển thị.');
      return;
    }
    if (password.length < 6) {
      setState(() => _errorMessage = 'Mật khẩu phải có ít nhất 6 ký tự.');
      return;
    }
    if (password != confirm) {
      setState(() => _errorMessage = 'Mật khẩu xác nhận không khớp.');
      return;
    }
    if (pin.isNotEmpty && (pin.length != 6 || int.tryParse(pin) == null)) {
      setState(() => _errorMessage = 'Mã PIN bảo mật phải gồm đúng 6 chữ số.');
      return;
    }

    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    final auth = context.read<AuthService>();
    final ok = await auth.register(
      username: username,
      displayName: displayName,
      password: password,
      email: email.isNotEmpty ? email : null,
      role: _selectedRole,
      pin: pin.isNotEmpty ? pin : '123456',
    );

    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pop(true);
      AppToast.success(context, 'Đăng ký tài khoản thành công! Đã đăng nhập vào hệ thống.');
    } else {
      setState(() {
        _busy = false;
        _errorMessage = auth.lastError ?? 'Đăng ký tài khoản thất bại.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: theme.colorScheme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.person_add_outlined, color: Color(0xFF2563EB), size: 26),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Đăng ký tài khoản',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tạo tài khoản người dùng nội bộ hệ thống BankOps',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Error Box
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Form fields
              TextField(
                key: const Key('register-username-field'),
                controller: _usernameCtrl,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: 'Tên đăng nhập *',
                  hintText: 'Ví dụ: nguyenvan_a',
                  prefixIcon: const Icon(Icons.badge_outlined, size: 20),
                  filled: true,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 14),

              TextField(
                key: const Key('register-displayname-field'),
                controller: _displayNameCtrl,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: 'Họ và tên hiển thị *',
                  hintText: 'Ví dụ: Nguyễn Văn A (Giao dịch viên)',
                  prefixIcon: const Icon(Icons.person_outline, size: 20),
                  filled: true,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 14),

              TextField(
                key: const Key('register-email-field'),
                controller: _emailCtrl,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email liên hệ / khôi phục OTP',
                  hintText: 'user@example.com (nhận mã OTP khi quên mật khẩu)',
                  prefixIcon: const Icon(Icons.mail_outline, size: 20),
                  filled: true,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 14),

              // Vai trò trong hệ thống
              DropdownButtonFormField<String>(
                key: const Key('register-role-dropdown'),
                initialValue: _selectedRole,
                decoration: InputDecoration(
                  labelText: 'Phân hệ / Vai trò *',
                  prefixIcon: const Icon(Icons.admin_panel_settings_outlined, size: 20),
                  filled: true,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'staff',
                    child: Text('Maker — Giao dịch viên (Lập lệnh kho & quỹ)'),
                  ),
                  DropdownMenuItem(
                    value: 'approver',
                    child: Text('Checker — Kiểm soát viên (Duyệt lệnh 4 mắt)'),
                  ),
                  DropdownMenuItem(
                    value: 'auditor',
                    child: Text('Auditor — Kiểm toán viên (Xem báo cáo & vết KT)'),
                  ),
                ],
                onChanged: _busy ? null : (v) => setState(() => _selectedRole = v ?? 'staff'),
              ),
              const SizedBox(height: 14),

              // Supervisor PIN
              TextField(
                key: const Key('register-pin-field'),
                controller: _pinCtrl,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Mã PIN bảo mật (6 số) *',
                  hintText: '123456 (dùng duyệt lệnh 4 mắt)',
                  counterText: '',
                  prefixIcon: const Icon(Icons.pin_outlined, size: 20),
                  filled: true,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 14),

              // Password & Confirm Password
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('register-password-field'),
                      controller: _passwordCtrl,
                      enabled: !_busy,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Mật khẩu *',
                        prefixIcon: const Icon(Icons.lock_outline, size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                        filled: true,
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: const Key('register-confirm-password-field'),
                      controller: _confirmPasswordCtrl,
                      enabled: !_busy,
                      obscureText: _obscureConfirm,
                      decoration: InputDecoration(
                        labelText: 'Xác nhận MK *',
                        prefixIcon: const Icon(Icons.lock_reset_outlined, size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                          onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                        ),
                        filled: true,
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Hủy bỏ'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      key: const Key('register-submit-btn'),
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: const Color(0xFF17365D),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.how_to_reg_rounded, size: 20),
                      label: Text(
                        _busy ? 'Đang tạo tài khoản…' : 'Đăng ký & Đăng nhập',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
