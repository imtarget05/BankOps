import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kho_tra_sua/src/app/app_shell.dart';
import 'package:kho_tra_sua/src/core/i18n/locale_controller.dart';
import 'package:kho_tra_sua/src/core/theme/app_theme.dart';
import 'package:kho_tra_sua/src/core/theme/app_ui_settings_controller.dart';
import 'package:kho_tra_sua/src/data/models/dtos.dart';
import 'package:kho_tra_sua/src/data/repositories/fake_repository.dart';
import 'package:kho_tra_sua/src/features/reports/reports_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const adminUser = AppUser(
    id: 'u_admin',
    username: 'admin',
    displayName: 'Quản Trị Viên',
    roles: ['admin', 'manager', 'teller', 'cashier'],
  );

  const localizationsDelegates = [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  testWidgets(
      'AppShell dynamically switches navigation tab labels between VI and EN without restart',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final repo = FakeBankOpsRepository(latency: Duration.zero);
    final localeController = LocaleController();
    final uiSettings = AppUiSettingsController()..setShowLiveTicker(false);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LocaleController>.value(value: localeController),
          ChangeNotifierProvider<AppUiSettingsController>.value(value: uiSettings),
        ],
        child: RepositoryScope(
          repository: repo,
          child: SessionScope(
            user: adminUser,
            child: Consumer<LocaleController>(
              builder: (context, locCtrl, _) => MaterialApp(
                theme: AppTheme.light(),
                locale: locCtrl.locale,
                localizationsDelegates: localizationsDelegates,
                supportedLocales: const [Locale('vi'), Locale('en')],
                home: AppShell(repository: repo),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 1. Initially Vietnamese
    expect(find.text('Tổng quan'), findsWidgets);
    expect(find.text('Kho'), findsWidgets);
    expect(find.text('Yêu cầu'), findsWidgets);
    expect(find.text('Duyệt'), findsWidgets);
    expect(find.text('Báo cáo'), findsWidgets);

    // 2. Switch to English via LocaleController
    await localeController.setLocale(const Locale('en'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify tabs update to English immediately
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Inventory'), findsWidgets);
    expect(find.text('Requests'), findsWidgets);
    expect(find.text('Approvals'), findsWidgets);
    expect(find.text('Reports'), findsWidgets);

    // 3. Switch back to Vietnamese
    await localeController.setLocale(const Locale('vi'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Tổng quan'), findsWidgets);
    expect(find.text('Kho'), findsWidgets);
    expect(find.text('Báo cáo'), findsWidgets);
  });

  testWidgets(
      'ReportsScreen dynamically translates headers and all 7 tabs between VI and EN',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final repo = FakeBankOpsRepository(latency: Duration.zero);
    final localeController = LocaleController();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LocaleController>.value(value: localeController),
        ],
        child: RepositoryScope(
          repository: repo,
          child: SessionScope(
            user: adminUser,
            child: Consumer<LocaleController>(
              builder: (context, locCtrl, _) => MaterialApp(
                theme: AppTheme.light(),
                locale: locCtrl.locale,
                localizationsDelegates: localizationsDelegates,
                supportedLocales: const [Locale('vi'), Locale('en')],
                home: const Scaffold(
                  body: ReportsScreen(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // In Vietnamese mode
    expect(find.text('Báo cáo & Biểu đồ'), findsOneWidget);
    expect(find.text('Nhập/Xuất kho'), findsOneWidget);
    expect(find.text('Sổ Quỹ Tiền Mặt'), findsOneWidget);
    expect(find.text('Tồn đọng'), findsOneWidget);
    expect(find.text('Top Tiêu Hao F&B'), findsOneWidget);
    expect(find.text('Lịch Sử Chốt Ca'), findsOneWidget);
    expect(find.text('Đối soát'), findsOneWidget);
    expect(find.text('Báo Cáo Tổng Hợp'), findsOneWidget);

    // Switch to English mode
    await localeController.setLocale(const Locale('en'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Management & Reconciliation Reports'), findsOneWidget);
    expect(find.text('Stock In/Out'), findsOneWidget);
    expect(find.text('Cash Ledger'), findsOneWidget);
    expect(find.text('Stagnation'), findsOneWidget);
    expect(find.text('Top Consumption'), findsOneWidget);
    expect(find.text('Shift History'), findsOneWidget);
    expect(find.text('Reconciliation'), findsOneWidget);
    expect(find.text('Executive Summary'), findsOneWidget);
  });
}
