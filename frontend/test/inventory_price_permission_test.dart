import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:kho_tra_sua/src/app/app_shell.dart';
import 'package:kho_tra_sua/src/app/theme_mode_controller.dart';
import 'package:kho_tra_sua/src/core/theme/app_theme.dart';
import 'package:kho_tra_sua/src/data/models/dtos.dart';
import 'package:kho_tra_sua/src/data/repositories/fake_repository.dart';
import 'package:kho_tra_sua/src/features/auth/auth_service.dart';
import 'package:kho_tra_sua/src/features/inventory/inventory_screen.dart';
import 'package:kho_tra_sua/src/features/settings/settings_screen.dart';

void main() {
  group('Role-Based Price Protection & Reset Data Tests', () {
    testWidgets('Admin user can see selling price, cost price, and total valuation',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final repo = FakeBankOpsRepository(latency: Duration.zero);
      const adminUser = AppUser(
        id: 'u_admin',
        username: 'admin',
        displayName: 'Trần Văn Quản Lý',
        roles: ['admin', 'inventory_manager'],
      );

      await tester.pumpWidget(
        RepositoryScope(
          repository: repo,
          child: SessionScope(
            user: adminUser,
            child: MaterialApp(
              theme: AppTheme.light(),
              home: const Scaffold(
                body: InventoryScreen(mode: InventoryTabMode.stock),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check header contains GIÁ BÁN and GIÁ VỐN without lock icon
      expect(find.text('GIÁ BÁN'), findsOneWidget);
      expect(find.text('GIÁ VỐN'), findsOneWidget);

      // Check that price masking bullets '••••••' are NOT displayed for admin
      expect(find.text('••••••'), findsNothing);

      // Check that formatted VNĐ prices appear
      expect(find.textContaining('₫'), findsWidgets);

      // Check that Total Inventory Valuation card shows a money value
      expect(find.text('TỔNG GIÁ TRỊ KHO'), findsOneWidget);
      expect(find.text('Định giá vốn tồn hiện tại'), findsOneWidget);
    });

    testWidgets('Non-admin user (staff) sees masked prices and cannot see total valuation',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final repo = FakeBankOpsRepository(latency: Duration.zero);
      const staffUser = AppUser(
        id: 'u_staff',
        username: 'staff',
        displayName: 'Nguyễn Thị Mai',
        roles: ['cashier', 'inventory_manager'],
      );

      await tester.pumpWidget(
        RepositoryScope(
          repository: repo,
          child: SessionScope(
            user: staffUser,
            child: MaterialApp(
              theme: AppTheme.light(),
              home: const Scaffold(
                body: InventoryScreen(mode: InventoryTabMode.stock),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check header indicates price locking (🔒)
      expect(find.text('GIÁ BÁN (🔒)'), findsOneWidget);
      expect(find.text('GIÁ VỐN (🔒)'), findsOneWidget);

      // Check that masked prices '••••••' are rendered for items
      expect(find.text('••••••'), findsWidgets);

      // Check total valuation card shows masked security note
      expect(find.text('Bảo mật (Chỉ Admin)'), findsOneWidget);

      // Check tooltip on masked price
      final maskedFinder = find.byTooltip('Chỉ Admin mới có quyền xem giá');
      expect(maskedFinder, findsWidgets);
    });

    testWidgets('Admin user can see Reset Store Data button in Settings',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final repo = FakeBankOpsRepository(latency: Duration.zero);
      const adminUser = AppUser(
        id: 'u_admin',
        username: 'admin',
        displayName: 'Trần Văn Quản Lý',
        roles: ['admin'],
      );
      final auth = AuthService(baseUrl: 'http://localhost:8000');
      auth.setUserForTest(adminUser);
      final themeController = ThemeModeController();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: auth),
            ChangeNotifierProvider<ThemeModeController>.value(value: themeController),
          ],
          child: RepositoryScope(
            repository: repo,
            child: SessionScope(
              user: adminUser,
              child: MaterialApp(
                theme: AppTheme.light(),
                home: const Scaffold(
                  body: SettingsScreen(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Admin can see reset data button
      final resetBtn = find.byKey(const Key('btn-reset-store-data'));
      await tester.scrollUntilVisible(resetBtn, 150,
          scrollable: find.byType(Scrollable).first);
      expect(resetBtn, findsOneWidget);

      // Tap reset button and verify dialog
      await tester.tap(resetBtn);
      await tester.pumpAndSettle();

      expect(find.text('Khởi tạo lại hệ thống'), findsOneWidget);
      expect(find.textContaining('19 mặt hàng'), findsOneWidget);
    });

    testWidgets('Non-admin user cannot see Reset Store Data button in Settings',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final repo = FakeBankOpsRepository(latency: Duration.zero);
      const staffUser = AppUser(
        id: 'u_staff',
        username: 'staff',
        displayName: 'Nguyễn Thị Mai',
        roles: ['cashier'],
      );
      final auth = AuthService(baseUrl: 'http://localhost:8000');
      auth.setUserForTest(staffUser);
      final themeController = ThemeModeController();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: auth),
            ChangeNotifierProvider<ThemeModeController>.value(value: themeController),
          ],
          child: RepositoryScope(
            repository: repo,
            child: SessionScope(
              user: staffUser,
              child: MaterialApp(
                theme: AppTheme.light(),
                home: const Scaffold(
                  body: SettingsScreen(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Non-admin CANNOT see reset data button
      final resetBtn = find.byKey(const Key('btn-reset-store-data'));
      expect(resetBtn, findsNothing);
    });
  });
}
