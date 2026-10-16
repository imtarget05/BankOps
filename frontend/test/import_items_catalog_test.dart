import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kho_tra_sua/src/app/app_shell.dart';
import 'package:kho_tra_sua/src/core/theme/app_theme.dart';
import 'package:kho_tra_sua/src/data/models/dtos.dart';
import 'package:kho_tra_sua/src/data/repositories/fake_repository.dart';
import 'package:kho_tra_sua/src/features/inventory/import_items_dialog.dart';
import 'package:kho_tra_sua/src/features/inventory/inventory_screen.dart';

void main() {
  testWidgets(
      'Import mặt hàng button is visible for manager and opens ImportItemsDialog',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final repo = FakeBankOpsRepository(latency: Duration.zero);
    const user = AppUser(
      id: 'u_manager',
      username: 'manager_test',
      displayName: 'Quản Lý Kho',
      roles: ['inventory_manager', 'admin'],
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

    // Verify 'btn-import-items' exists in header actions
    final importBtn = find.byKey(const Key('btn-import-items'));
    expect(importBtn, findsOneWidget);

    // Click Import button
    await tester.tap(importBtn);
    await tester.pumpAndSettle();

    // Verify ImportItemsDialog is opened
    expect(find.byType(ImportItemsDialog), findsOneWidget);
    expect(find.text('Nhập Mặt Hàng Hàng Loạt'), findsOneWidget);
    expect(find.text('Danh mục mẫu Trà Sữa'), findsOneWidget);
    expect(find.text('Nhập File / Dán dữ liệu'), findsOneWidget);

    // Verify preset items are shown in Tab 1
    expect(find.textContaining('mặt hàng mẫu'), findsWidgets);
    expect(find.text('Trà Đen Lộc Phát Số 9'), findsWidgets);

    // Tap submit button in preset tab
    final submitSampleBtn = find.byKey(const Key('btn-confirm-import-sample'));
    expect(submitSampleBtn, findsOneWidget);
    await tester.tap(submitSampleBtn);
    await tester.pumpAndSettle();

    // Dialog closes and items imported
    expect(find.byType(ImportItemsDialog), findsNothing);
    expect(find.textContaining('Đã nhập thành công'), findsOneWidget);
  });

  testWidgets('Tab 2 parses pasted CSV text and imports items',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final repo = FakeBankOpsRepository(latency: Duration.zero);
    const user = AppUser(
      id: 'u_manager',
      username: 'manager_test',
      displayName: 'Quản Lý Kho',
      roles: ['inventory_manager'],
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

    // Open import dialog
    await tester.tap(find.byKey(const Key('btn-import-items')));
    await tester.pumpAndSettle();

    // Switch to Tab 2
    await tester.tap(find.text('Nhập File / Dán dữ liệu'));
    await tester.pumpAndSettle();

    // Verify Tab 2 is active
    expect(find.byKey(const Key('input-paste-csv')), findsOneWidget);

    // Enter CSV text
    const sampleCsv =
        'SKU_TEST01\tTrà Xanh Hoa Nhài\tg\tTrà\tTúi 500g\t1000\nSKU_TEST02,Topping Thạch Dừa,kg,Topping,Hũ 1kg,50';
    await tester.enterText(find.byKey(const Key('input-paste-csv')), sampleCsv);
    await tester.pumpAndSettle();

    // Verify preview table appears with 2 rows
    expect(find.textContaining('Xem trước: 2 dòng'), findsOneWidget);
    expect(find.text('Trà Xanh Hoa Nhài (SKU_TEST01)'), findsOneWidget);
    expect(find.text('Topping Thạch Dừa (SKU_TEST02)'), findsOneWidget);

    // Tap submit custom import
    final submitCustomBtn = find.byKey(const Key('btn-confirm-import-custom'));
    expect(submitCustomBtn, findsOneWidget);
    await tester.tap(submitCustomBtn);
    await tester.pumpAndSettle();

    // Dialog closes
    expect(find.byType(ImportItemsDialog), findsNothing);
    expect(find.textContaining('Đã nhập thành công 2 mặt hàng'), findsOneWidget);
  });

  testWidgets('Empty catalog card shows quick 1-click import sample button',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    // Create a mock repo with 0 items
    final repo = _EmptyCatalogFakeRepository();
    const user = AppUser(
      id: 'u_manager',
      username: 'manager_test',
      displayName: 'Quản Lý Kho',
      roles: ['inventory_manager'],
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

    // Verify empty state is displayed
    final emptyCardTitle = find.text('Chưa có mặt hàng nào trong kho');
    await tester.scrollUntilVisible(
      emptyCardTitle,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(emptyCardTitle, findsOneWidget);
    final emptyImportBtn = find.byKey(const Key('btn-empty-import-sample'));
    expect(emptyImportBtn, findsOneWidget);

    // Tapping empty import button opens dialog
    await tester.tap(emptyImportBtn);
    await tester.pumpAndSettle();

    expect(find.byType(ImportItemsDialog), findsOneWidget);
  });
}

class _EmptyCatalogFakeRepository extends FakeBankOpsRepository {
  _EmptyCatalogFakeRepository() : super(latency: Duration.zero);

  @override
  Future<List<InventoryItem>> getItems() async => [];
}
