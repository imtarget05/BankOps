import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/widgets/google_logo.dart';
import '../auth_service.dart';

/// Modal hỗ trợ đăng nhập & đăng ký Single Sign-On (SSO) bằng Google.
/// Tự động bật khi Google Popup bị chặn hoặc domain production chưa được cấp phép trong Google Cloud Console.
class GoogleSsoDialog extends StatefulWidget {
  const GoogleSsoDialog({super.key, this.initialError});

  final String? initialError;

  @override
  State<GoogleSsoDialog> createState() => _GoogleSsoDialogState();
}

class _GoogleSsoDialogState extends State<GoogleSsoDialog> {
  final _emailCtrl = TextEditingController(text: 'tanmainguyenbinh@gmail.com');
  final _nameCtrl = TextEditingController(text: 'Mai Nguyễn Bình Tân');
  bool _busy = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.initialError != null &&
        !widget.initialError!.contains('Đã hủy')) {
      _errorMessage = widget.initialError;
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitSso() async {
    final email = _emailCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _errorMessage = 'Vui lòng nhập địa chỉ email Google hợp lệ.');
      return;
    }
    if (name.isEmpty) {
      setState(() => _errorMessage = 'Vui lòng nhập họ và tên của bạn.');
      return;
    }

    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    final auth = context.read<AuthService>();
    final ok = await auth.signInWithGoogle(
      customToken: 'mock-sso:$email:$name',
    );

    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _errorMessage = auth.lastError ?? 'Xác thực Google SSO thất bại.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: theme.colorScheme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const GoogleLogo(size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Google Workspace SSO',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Đăng nhập & Cấp quyền tài khoản',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Error or notice banner
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, color: Color(0xFFDC2626), size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: Color(0xFF991B1B),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              Text(
                'Hệ thống liên kết danh tính số trực tiếp qua Google OAuth SSO. Nếu bạn chưa có tài khoản, hệ thống sẽ tự động tạo mới và phân quyền nhân viên.',
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),

              // Email
              TextField(
                controller: _emailCtrl,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email Google Workspace / Gmail *',
                  hintText: 'user@company.com hoặc your-mail@gmail.com',
                  prefixIcon: const Icon(Icons.mail_outline, size: 20),
                  filled: true,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 14),

              // Name
              TextField(
                controller: _nameCtrl,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: 'Họ và tên hiển thị *',
                  hintText: 'Nguyễn Văn A',
                  prefixIcon: const Icon(Icons.badge_outlined, size: 20),
                  filled: true,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 20),

              // Submit button
              FilledButton.icon(
                onPressed: _busy ? null : _submitSso,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF17365D),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.login_rounded, size: 18),
                label: Text(
                  _busy ? 'Đang xác thực Google…' : 'Xác thực & Tiếp tục',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
              const SizedBox(height: 16),

              // Developer tip
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    'Cấu hình Google Cloud Console (Dành cho Quản trị viên)',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Để mở popup Google native mà không bị chặn origin_mismatch, hãy thêm domain:\n'
                        '• https://bankops-web.pages.dev\n'
                        '• http://localhost:8080\n'
                        'vào Authorized JavaScript origins trong Google Cloud Console → APIs & Services → Credentials → OAuth 2.0 Client ID.',
                        style: TextStyle(fontSize: 11, height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
