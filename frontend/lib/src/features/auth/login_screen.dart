import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_shell.dart';
import '../../core/widgets/google_logo.dart';
import '../../data/repositories/bankops_repository.dart';
import 'auth_service.dart';
import 'widgets/forgot_password_dialog.dart';
import 'widgets/google_sso_dialog.dart';
import 'widgets/register_dialog.dart';

/// Màn hình đăng nhập phong cách Enterprise Banking Portal:
/// Thiết kế Split-screen trên desktop/tablet, giao diện chuyên nghiệp cho Maker/Checker/Auditor,
/// hỗ trợ đăng nhập nhanh bằng tài khoản Demo và Google Sign-In SSO.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _busy = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _loginWithPassword([String? presetUser]) async {
    if (_busy) return;
    if (presetUser != null) {
      _usernameCtrl.text = presetUser;
    }
    setState(() => _busy = true);
    try {
      final ok = await context.read<AuthService>().signInWithPassword(
            username: _usernameCtrl.text.trim(),
            password: _passwordCtrl.text,
          );
      if (!mounted) return;
      if (!ok) {
        final msg =
            context.read<AuthService>().lastError ?? 'Đăng nhập thất bại. Vui lòng kiểm tra lại thông tin.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFB42318),
            behavior: SnackBarBehavior.floating,
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(msg)),
              ],
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loginWithGoogle() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await context.read<AuthService>().signInWithGoogle();
      if (!mounted) return;
      if (!ok) {
        final auth = context.read<AuthService>();
        final msg = auth.lastError;
        if (msg != null && msg.contains('Đã hủy')) {
          return;
        }
        await showDialog<bool>(
          context: context,
          builder: (_) => GoogleSsoDialog(initialError: msg),
        );
      }
    } catch (e) {
      if (!mounted) return;
      await showDialog<bool>(
        context: context,
        builder: (_) => GoogleSsoDialog(initialError: 'Lỗi xác thực Google: $e'),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openForgotPassword() async {
    BankOpsRepository? repo;
    try {
      repo = RepositoryScope.of(context);
    } catch (_) {}
    final username = await ForgotPasswordDialog.show(
      context,
      initialUsername: _usernameCtrl.text.trim(),
      repository: repo,
    );
    if (username != null && mounted) {
      _usernameCtrl.text = username;
      _passwordCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
          content: Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Expanded(
                child:
                    Text('Khôi phục mật khẩu thành công! Vui lòng đăng nhập.'),
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _openRegister() async {
    await RegisterDialog.show(context);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 900;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFF8FAFC),
      body: Center(
        child: isDesktop ? _buildDesktopLayout(context) : _buildMobileLayout(context),
      ),
    );
  }

  Widget _buildDesktopLayout(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 720),
      margin: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: _buildHeroPanel(context),
          ),
          Expanded(
            flex: 6,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 36),
              child: _buildLoginForm(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildBrandHeader(context),
                  const SizedBox(height: 24),
                  _buildLoginForm(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrandHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: const Color(0xFF1E3A8A),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1E3A8A).withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.account_balance,
            color: Colors.white,
            size: 28,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'BankOps',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Cổng Quản Lý Vận Hành Kho Quỹ & Phê Duyệt 4 Mắt',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildHeroPanel(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF0F172A),
            Color(0xFF1E293B),
            Color(0xFF17365D),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                ),
                child: const Icon(
                  Icons.account_balance,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'BankOps',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    'ENTERPRISE CORE SYSTEM',
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shield_outlined, color: Color(0xFF34D399), size: 14),
                    SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Bảo mật Ngân hàng & Kiểm soát kép',
                        style: TextStyle(
                          color: Color(0xFF6EE7B7),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Quản lý kho quỹ\nchuẩn mực tài chính',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 20),
              _buildFeatureItem(
                icon: Icons.checklist_rtl_rounded,
                title: 'Quy trình 4 Mắt (Maker - Checker)',
                desc: 'Phân định độc lập giữa người lập và người duyệt lệnh.',
              ),
              const SizedBox(height: 14),
              _buildFeatureItem(
                icon: Icons.account_tree_outlined,
                title: 'Sổ cái Bất biến & Real-time Vault',
                desc: 'Khóa dòng dữ liệu ACID, loại bỏ rủi ro tương tranh số dư.',
              ),
              const SizedBox(height: 14),
              _buildFeatureItem(
                icon: Icons.sync_alt_rounded,
                title: 'Đối soát Tự động & Vết Kiểm toán',
                desc: 'Khớp số dư thực tế với Core Banking, lưu vết toàn diện.',
              ),
            ],
          ),
          Row(
            children: [
              const Icon(Icons.lock_clock_outlined, color: Color(0xFF94A3B8), size: 16),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Tuân thủ bảo mật ISO/IEC 27001 • v3.8.0',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem({
    required IconData icon,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: const Color(0xFF38BDF8), size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 11.5,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLoginForm(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final auth = context.watch<AuthService>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Đăng nhập tài khoản',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Truy cập hệ thống phân hệ kiểm soát kho quỹ nội bộ',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          key: const Key('login-username-field'),
          controller: _usernameCtrl,
          enabled: !_busy,
          decoration: InputDecoration(
            labelText: 'Tên đăng nhập / Mã định danh',
            prefixIcon: const Icon(Icons.person_outline, size: 20),
            filled: true,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const Key('login-password-field'),
          controller: _passwordCtrl,
          enabled: !_busy,
          obscureText: _obscurePassword,
          onSubmitted: (_) => _loginWithPassword(),
          decoration: InputDecoration(
            labelText: 'Mật khẩu bảo mật',
            prefixIcon: const Icon(Icons.lock_outline, size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                size: 20,
              ),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
            filled: true,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: const Key('login-forgot-password-btn'),
            onPressed: _busy ? null : _openForgotPassword,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Quên mật khẩu?',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2563EB),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          key: const Key('login-submit-btn'),
          onPressed: _busy ? null : () => _loginWithPassword(),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            backgroundColor: const Color(0xFF17365D),
          ),
          icon: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Icon(Icons.login_rounded, size: 20),
          label: Text(
            _busy ? 'Đang xác thực thông tin…' : 'Xác thực & Đăng nhập',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: Divider(color: theme.colorScheme.outlineVariant)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'HOẶC TIẾP TỤC VỚI',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  fontSize: 10,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(child: Divider(color: theme.colorScheme.outlineVariant)),
          ],
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          key: const Key('login-google-btn'),
          onPressed: _busy ? null : _loginWithGoogle,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 13),
            backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
            foregroundColor:
                isDark ? Colors.white : const Color(0xFF1F2937),
            side: BorderSide(
              color: isDark
                  ? const Color(0xFF334155)
                  : const Color(0xFFDADCE0),
              width: 1,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: isDark ? 0 : 0.5,
          ),
          icon: const GoogleLogo(size: 20),
          label: const Text(
            'Đăng nhập bằng Google',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              letterSpacing: 0.2,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          auth.isGoogleSignInConfigured
              ? 'Tài khoản Google tổ chức sẽ được tự động phân quyền theo vai trò.'
              : 'Hỗ trợ đăng nhập bảo mật với Google Workspace và Single Sign-On (SSO).',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
            fontSize: 11,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Chưa có tài khoản?',
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 4),
            TextButton(
              key: const Key('login-register-btn'),
              onPressed: _busy ? null : _openRegister,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Đăng ký ngay',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Color(0xFF2563EB),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
