import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kho_tra_sua/src/app/app_shell.dart';
import 'package:kho_tra_sua/src/core/theme/app_theme.dart';
import 'package:kho_tra_sua/src/data/models/dtos.dart';
import 'package:kho_tra_sua/src/data/repositories/fake_repository.dart';
import 'package:kho_tra_sua/src/features/inventory/inventory_screen.dart';

void main() {
  testWidgets(
      'InventoryScreen in stock mode shows stock catalog and hides stocktake desk',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(500, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final repo = FakeBankOpsRepository(latency: Duration.zero);
    const user = AppUser(
      id: 'u_manager',
      username: 'manager_test',
      displayName: 'Quản Lý Kho',
      roles: ['manager', 'admin'],
    );

    await tester.pumpWidget(
      RepositoryScope(
        repository: repo,
        child: SessionScope(
          user: user,
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

    // In Stock mode:
    expect(find.text('Quản Lý Nhập Xuất Tồn Nguyên Vật Liệu'), findsOneWidget);
    final catalogText = find.text('Danh mục mặt hàng');
    await tester.scrollUntilVisible(
      catalogText,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(catalogText, findsOneWidget);

    // Stocktake / Shift sections should NOT be present in Stock mode
    expect(
        find.text('Kiểm Kê Kho Định Kỳ & Đối Soát Chênh Lệch'), findsNothing);
    expect(find.text('Quầy kiểm kê theo ca'), findsNothing);
  });

  testWidgets(
      'InventoryScreen in shiftWork mode shows shift KPIs, stocktakes and hides raw catalog',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(380, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final repo = FakeBankOpsRepository(latency: Duration.zero);
    const user = AppUser(
      id: 'u_staff',
      username: 'staff_test',
      displayName: 'Nhân Viên Pha Chế',
      roles: ['teller'],
    );

    await tester.pumpWidget(
      RepositoryScope(
        repository: repo,
        child: SessionScope(
          user: user,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(
              body: InventoryScreen(mode: InventoryTabMode.shiftWork),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // In ShiftWork mode:
    expect(find.text('Quản Lý Ca Làm Việc & Kiểm Kê Ca Pha Chế'), findsOneWidget);
    expect(find.text('TỔNG ĐỢT'), findsOneWidget);
    expect(find.text('CHỜ DUYỆT'), findsOneWidget);
    expect(
        find.text('Kiểm Kê Kho Định Kỳ & Đối Soát Chênh Lệch'), findsOneWidget);
    expect(find.text('Quầy kiểm kê theo ca'), findsOneWidget);

    // Raw stock catalog & balance tables should NOT be present in ShiftWork mode
    expect(find.text('Danh mục mặt hàng'), findsNothing);
    expect(find.text('Chi Tiết Tồn Kho Theo Nguyên Vật Liệu'), findsNothing);
  });

  testWidgets(
      'AppShell "Chọn màn" more menu opens DraggableScrollableSheet with full scrollable list',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(380, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final repo = FakeBankOpsRepository(latency: Duration.zero);
    const user = AppUser(
      id: 'u_admin',
      username: 'admin_test',
      displayName: 'Quản Trị Viên',
      roles: ['admin', 'manager'],
    );

    await tester.pumpWidget(
      RepositoryScope(
        repository: repo,
        child: SessionScope(
          user: user,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: AppShell(repository: repo),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Bottom navigation bar has "Thêm" (more menu)
    final moreNav = find.byKey(const Key('nav-bottom-more'));
    expect(moreNav, findsOneWidget);

    await tester.tap(moreNav);
    await tester.pumpAndSettle();

    // Bottom sheet is now visible
    expect(find.text('Chọn phân hệ làm việc'), findsOneWidget);
    final sheetFinder = find.byType(DraggableScrollableSheet);
    expect(sheetFinder, findsOneWidget);

    // Check that items are visible inside sheet
    expect(find.descendant(of: sheetFinder, matching: find.text('Kho')),
        findsOneWidget);
    expect(find.descendant(of: sheetFinder, matching: find.text('Ca làm việc')),
        findsOneWidget);

    // Find and tap "Ca làm việc" in sheet
    final shiftItem =
        find.descendant(of: sheetFinder, matching: find.text('Ca làm việc'));
    expect(shiftItem, findsOneWidget);

    await tester.tap(shiftItem);
    await tester.pumpAndSettle();

    // Sheet should close and Shift Work screen should be displayed
    expect(find.text('Chọn phân hệ làm việc'), findsNothing);
    expect(find.byType(DraggableScrollableSheet), findsNothing);
    expect(
        find.text('Quản Lý Ca Làm Việc & Kiểm Kê Ca Pha Chế'), findsOneWidget);
  });
}
