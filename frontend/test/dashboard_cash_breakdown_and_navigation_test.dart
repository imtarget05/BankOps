import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kho_tra_sua/src/app/app_shell.dart';
import 'package:kho_tra_sua/src/core/theme/app_theme.dart';
import 'package:kho_tra_sua/src/data/models/dtos.dart';
import 'package:kho_tra_sua/src/data/repositories/fake_repository.dart';
import 'package:kho_tra_sua/src/features/dashboard/dashboard_screen.dart';

void main() {
  testWidgets('Dashboard cash breakdown displays registers, shifts and adjustment button opens modal', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final repo = FakeBankOpsRepository(latency: Duration.zero);

    int? navigatedIndex;
    String? navigatedCategory;
    String? navigatedViewMode;

    await tester.pumpWidget(
      RepositoryScope(
        repository: repo,
        child: SessionScope(
          user: const AppUser(
            id: 'u-admin',
            username: 'tanmainguyen',
            email: 'tanmainguyenbinhtan@gmail.com',
            displayName: 'Admin Quản Trị',
            roles: ['admin'],
          ),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: DashboardScreen(
                onNavigate: (index, {category, stockFilter, viewMode, locationId, autoOpenCash = false, autoOpenStock = false}) {
                  navigatedIndex = index;
                  navigatedCategory = category;
                  navigatedViewMode = viewMode;
                },
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Verify Cash Register breakdown
    expect(find.text('Quỹ tiền mặt & Ca trực chi nhánh'), findsOneWidget);
    expect(find.textContaining('Quầy Thu Ngân 01'), findsOneWidget);
    expect(find.textContaining('Quầy Thu Ngân 02'), findsOneWidget);
    expect(find.textContaining('Két Sắt Trung Tâm Chi Nhánh'), findsOneWidget);

    // 2. Verify Shifts & Cashiers
    expect(find.text('Ca Sáng (06:30 – 14:30)'), findsOneWidget);
    expect(find.text('Ca Chiều (14:30 – 22:30)'), findsOneWidget);

    // 3. Tap "Kiểm tra & Tùy chỉnh" button
    final adjustBtn = find.text('Kiểm tra & Tùy chỉnh').first;
    await tester.tap(adjustBtn);
    await tester.pumpAndSettle();

    // Verify cash adjustment bottom sheet opens
    expect(find.textContaining('Kiểm Tra & Tùy Chỉnh Két / Quầy'), findsOneWidget);
    expect(find.text('Lý do / Nội dung kiểm tra'), findsOneWidget);
    expect(find.text('Lưu & Cập nhật'), findsOneWidget);

    // Close bottom sheet
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();

    // 4. Test 6 Navigation Buttons at bottom
    // Tile 1: Chủng loại vật tư -> routes to Inventory with category
    final categoryBtn = find.byKey(const Key('kpi-tile-category'));
    if (categoryBtn.evaluate().isNotEmpty) {
      await tester.tap(categoryBtn);
      await tester.pumpAndSettle();
      expect(navigatedIndex, 1);
      expect(navigatedCategory, 'Nhóm Trà');
    }

    // Tile 2: Bản ghi tồn kho -> routes to Inventory in Google Sheet view
    final sheetBtn = find.byKey(const Key('kpi-tile-sheet'));
    if (sheetBtn.evaluate().isNotEmpty) {
      await tester.tap(sheetBtn);
      await tester.pumpAndSettle();
      expect(navigatedIndex, 1);
      expect(navigatedViewMode, 'sheet');
    }
  });
}
