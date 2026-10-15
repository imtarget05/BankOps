import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'src/app/app_shell.dart';
import 'src/core/theme/app_theme.dart';
import 'src/app/theme_mode_controller.dart';
import 'src/features/auth/auth_service.dart';
import 'src/features/auth/login_screen.dart';

import 'src/core/i18n/app_i18n.dart';
import 'src/core/i18n/locale_controller.dart';
import 'src/core/theme/app_ui_settings_controller.dart';

void main() {
  final uiSettings = AppUiSettingsController();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthService()..tryAutoLogin(),
        ),
        ChangeNotifierProvider(
          create: (_) => LocaleController(),
        ),
        ChangeNotifierProvider<AppUiSettingsController>.value(
          value: uiSettings,
        ),
        ChangeNotifierProvider<ThemeModeController>.value(
          value: uiSettings,
        ),
      ],
      child: const TeaInventoryApp(),
    ),
  );
}

/// Cầu nối session: đọc AuthService, expose user cho AppShell qua SessionScope.
class SessionBridge extends StatelessWidget {
  const SessionBridge({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, auth, _) => SessionScope(
        user: auth.user,
        onSignOut: auth.signOut,
        child: child,
      ),
    );
  }
}

/// Chưa đăng nhập -> LoginScreen (Google, lần đầu tự signup);
/// đã có token hợp lệ -> AppShell.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    if (auth.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (auth.user == null) return const LoginScreen();
    return const AppShell();
  }
}

class TeaInventoryApp extends StatelessWidget {
  const TeaInventoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    final uiSettings = context.watch<AppUiSettingsController>();
    final locale = context.watch<LocaleController>().locale;
    final i18n = AppI18n(locale);

    return MaterialApp(
      title: i18n.tr('app_title'),
      debugShowCheckedModeBanner: false,
      locale: locale,
      theme: AppTheme.light(
        preset: uiSettings.colorPreset,
        density: uiSettings.density,
      ),
      darkTheme: AppTheme.dark(
        preset: uiSettings.colorPreset,
        density: uiSettings.density,
      ),
      themeMode: uiSettings.mode,
      home: const SessionBridge(child: _AuthGate()),
    );
  }
}
