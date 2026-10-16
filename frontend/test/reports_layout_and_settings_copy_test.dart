import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kho_tra_sua/src/app/app_shell.dart';
import 'package:kho_tra_sua/src/app/theme_mode_controller.dart';
import 'package:kho_tra_sua/src/core/theme/app_theme.dart';
import 'package:kho_tra_sua/src/data/models/dtos.dart';
import 'package:kho_tra_sua/src/data/repositories/fake_repository.dart';
import 'package:kho_tra_sua/src/features/auth/auth_service.dart';
import 'package:kho_tra_sua/src/features/reports/reports_screen.dart';
import 'package:kho_tra_sua/src/features/settings/settings_screen.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('Báo cáo scroll toàn trang thay vì giữ header cố định',
      (tester) async {
    final repo = FakeBankOpsRepository(latency: Duration.zero);
    await tester.pumpWidget(RepositoryScope(
      repository: repo,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: ReportsScreen()),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(NestedScrollView), findsOneWidget);
  });

  testWidgets('Cài đặt không hiển thị thuật ngữ ETL', (tester) async {
    final repo = FakeBankOpsRepository(latency: Duration.zero);
    const root = AppUser(
      id: 'root-test',
      username: 'root_test',
      displayName: 'Root Test',
      roles: ['root_admin', 'admin'],
      capabilities: ['iam:root'],
    );
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>(
          create: (_) => AuthService(baseUrl: 'http://localhost:8000'),
        ),
        ChangeNotifierProvider<ThemeModeController>(
          create: (_) => ThemeModeController(),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: SessionScope(
          user: root,
          child: RepositoryScope(
            repository: repo,
            child: const SettingsScreen(),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('ETL'), findsNothing);
  });
}
