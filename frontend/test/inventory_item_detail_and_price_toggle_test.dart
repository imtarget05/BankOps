import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kho_tra_sua/src/app/app_shell.dart';
import 'package:kho_tra_sua/src/data/models/dtos.dart';
import 'package:kho_tra_sua/src/data/repositories/fake_repository.dart';
import 'package:kho_tra_sua/src/features/inventory/inventory_screen.dart';

void main() {
  testWidgets('Inventory spreadsheet renders 30 items, supports price toggle and clicking row opens detail sheet', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final repo = FakeBankOpsRepository(latency: Duration.zero);

    await tester.pumpWidget(
      RepositoryScope(
        repository: repo,
        child: const SessionScope(
          user: AppUser(
            id: 'u-admin',
            username: 'tanmainguyen',
            email: 'tanmainguyenbinhtan@gmail.com',
            displayName: 'Admin Quản Trị',
            roles: ['admin'],
          ),
          child: MaterialApp(
            home: Scaffold(
              body: InventoryScreen(mode: InventoryTabMode.stock),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Verify all 30 items are in the catalog
    expect(find.text('Tất cả (30)'), findsOneWidget);

    // 2. Verify Admin has price toggle ActionChip
    final priceToggleFinder = find.text('Đang hiện giá');
    expect(priceToggleFinder, findsOneWidget);

    // 3. Verify prices are visible as VND
    expect(find.textContaining('95.000 ₫'), findsWidgets);

    // 4. Tap toggle to hide prices
    await tester.tap(priceToggleFinder);
    await tester.pumpAndSettle();

    expect(find.text('Đang ẩn giá'), findsOneWidget);
    expect(find.textContaining('GIÁ BÁN (🔒)'), findsOneWidget);

    // 5. Tap toggle back to show prices
    await tester.tap(find.text('Đang ẩn giá'));
    await tester.pumpAndSettle();
    expect(find.text('Đang hiện giá'), findsOneWidget);

    // 6. Click on the first item row to open Item Detail Sheet
    final itemFinder = find.text('Trà Đen Lộc Phát Số 9').first;
    await tester.tap(itemFinder);
    await tester.pumpAndSettle();

    // Verify detail sheet opened with location breakdown and financial info
    expect(find.text('VỊ TRÍ LƯU KHO & TỒN KHẢ DỤNG'), findsOneWidget);
    expect(find.text('THÔNG TIN TÀI CHÍNH & GIÁ'), findsOneWidget);
    expect(find.text('Biên Lợi Nhuận Gộp:'), findsOneWidget);
    expect(find.text('Sửa & Đổi Giá'), findsOneWidget);
    expect(find.text('Cài Định Mức'), findsOneWidget);
  });
}
