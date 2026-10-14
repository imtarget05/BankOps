import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:provider/provider.dart';

import '../../../app/app_shell.dart';
import '../../../data/repositories/bankops_repository.dart';
import '../../../data/repositories/http_bankops_repository.dart';
import '../auth_service.dart';

/// Hộp thoại Phục hồi mật khẩu 2 bước:
/// Bước 1: Nhập Tên đăng nhập -> Nhận mã OTP (mô phỏng).
/// Bước 2: Nhập Mã OTP + Mật khẩu mới -> Hoàn tất khôi phục.
class ForgotPasswordDialog extends StatefulWidget {
  const ForgotPasswordDialog({
    super.key,
    this.initialUsername,
    this.repository,
  });

  final String? initialUsername;
  final BankOpsRepository? repository;

  static Future<String?> show(
    BuildContext context, {
    String? initialUsername,
    BankOpsRepository? repository,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ForgotPasswordDialog(
        initialUsername: initialUsername,
        repository: repository,
      ),
    );
  }

  @override
  State<ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<ForgotPasswordDialog> {
  late final TextEditingController _usernameCtrl;
  final _otpCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  int _step = 1; // 1: Nhập username, 2: Nhập OTP & mật khẩu mới
  bool _busy = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String? _otpDemo;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _usernameCtrl = TextEditingController(text: widget.initialUsername ?? '');
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _otpCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  BankOpsRepository _resolveRepository() {
    if (widget.repository != null) return widget.repository!;
    try {
      return RepositoryScope.of(context);
    } catch (_) {}
    final auth = Provider.of<AuthService?>(context, listen: false);
    return HttpBankOpsRepository(
      baseUrl: auth?.apiBaseUrl,
      tokenProvider: auth?.getAccessToken,
    );
  }

  Future<void> _requestOtp() async {
    final username = _usernameCtrl.text.trim();
    if (username.isEmpty) {
      setState(() => _errorMessage = 'Vui lòng nhập tên đăng nhập hoặc email.');
      return;
    }

    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    try {
      final repo = _resolveRepository();
      final res = await repo.requestPasswordReset(username);
      if (!mounted) return;
      setState(() {
        _otpDemo = res.otpDemo;
        if (res.otpDemo != null) {
          _otpCtrl.text = res.otpDemo!;
        }
        _step = 2;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (e is ApiException) {
          _errorMessage = e.message;
        } else {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final username = _usernameCtrl.text.trim();
    final otp = _otpCtrl.text.trim();
    final newPass = _newPasswordCtrl.text;
    final confirmPass = _confirmPasswordCtrl.text;

    if (!RegExp(r'^\d{6}$').hasMatch(otp)) {
      setState(() => _errorMessage = 'Mã OTP phải gồm đúng 6 chữ số.');
      return;
    }
    if (newPass.length < 6) {
      setState(
          () => _errorMessage = 'Mật khẩu mới phải có tối thiểu 6 ký tự.');
      return;
    }
    if (confirmPass != newPass) {
      setState(() => _errorMessage = 'Mật khẩu xác nhận không trùng khớp.');
      return;
    }

    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    try {
      final repo = _resolveRepository();
      await repo.resetPassword(
        username: username,
        otp: otp,
        newPassword: newPass,
      );
      if (!mounted) return;
      Navigator.of(context).pop(username);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (e is ApiException) {
          _errorMessage = e.message;
        } else {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1E3A8A).withValues(alpha: 0.3)
                  : const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.lock_reset_rounded,
              color: Color(0xFF2563EB),
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Phục hồi mật khẩu',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                ),
                Text(
                  _step == 1
                      ? 'Bước 1/2: Xác thực tài khoản người dùng'
                      : 'Bước 2/2: Nhập mã OTP & Đặt mật khẩu mới',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB42318).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFFB42318).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: Color(0xFFB42318), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: Color(0xFFB42318),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (_step == 1) ...[
                const Text(
                  'Nhập tên đăng nhập hoặc email tài khoản cần khôi phục mật khẩu. Hệ thống sẽ tạo mã xác thực OTP bảo mật.',
                  style: TextStyle(fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('forgot-password-username-field'),
                  controller: _usernameCtrl,
                  enabled: !_busy,
                  autofocus: true,
                  onSubmitted: (_) => _requestOtp(),
                  decoration: InputDecoration(
                    labelText: 'Tên đăng nhập / Mã định danh',
                    prefixIcon: const Icon(Icons.person_outline, size: 20),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF0F172A)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.check_circle_outline,
                              color: Color(0xFF10B981), size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Đã tạo mã xác thực cho: ${_usernameCtrl.text.trim()}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                      if (_otpDemo != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Text(
                              'Mã OTP mô phỏng: ',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2563EB)
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _otpDemo!,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF2563EB),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('forgot-password-otp-field'),
                  controller: _otpCtrl,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Mã xác thực OTP (6 chữ số)',
                    counterText: '',
                    prefixIcon: const Icon(Icons.pin, size: 20),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const Key('forgot-password-new-field'),
                  controller: _newPasswordCtrl,
                  enabled: !_busy,
                  obscureText: _obscureNew,
                  decoration: InputDecoration(
                    labelText: 'Mật khẩu mới (tối thiểu 6 ký tự)',
                    prefixIcon: const Icon(Icons.lock_outline, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureNew
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscureNew = !_obscureNew),
                    ),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const Key('forgot-password-confirm-field'),
                  controller: _confirmPasswordCtrl,
                  enabled: !_busy,
                  obscureText: _obscureConfirm,
                  onSubmitted: (_) => _resetPassword(),
                  decoration: InputDecoration(
                    labelText: 'Nhập lại mật khẩu mới',
                    prefixIcon: const Icon(Icons.lock_clock_outlined, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 20,
                      ),
                      onPressed: () => setState(
                          () => _obscureConfirm = !_obscureConfirm),
                    ),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (_step == 1) ...[
          OutlinedButton(
            key: const Key('forgot-password-cancel-btn'),
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Hủy'),
          ),
          FilledButton.icon(
            key: const Key('forgot-password-send-otp-btn'),
            onPressed: _busy ? null : _requestOtp,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF17365D),
            ),
            icon: _busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.arrow_forward_rounded, size: 18),
            label: Text(_busy ? 'Đang gửi…' : 'Tiếp tục'),
          ),
        ] else ...[
          OutlinedButton.icon(
            key: const Key('forgot-password-back-btn'),
            onPressed: _busy
                ? null
                : () => setState(() {
                      _step = 1;
                      _errorMessage = null;
                    }),
            icon: const Icon(Icons.arrow_back_rounded, size: 16),
            label: const Text('Quay lại'),
          ),
          FilledButton.icon(
            key: const Key('forgot-password-submit-btn'),
            onPressed: _busy ? null : _resetPassword,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
            ),
            icon: _busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.check, size: 18),
            label: Text(_busy ? 'Đang lưu…' : 'Đổi mật khẩu'),
          ),
        ],
      ],
    );
  }
}
