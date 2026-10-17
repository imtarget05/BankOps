import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kho_tra_sua/src/app/app_shell.dart';
import 'package:kho_tra_sua/src/data/models/dtos.dart';
import 'package:kho_tra_sua/src/data/repositories/fake_repository.dart';
import 'package:kho_tra_sua/src/features/inventory/inventory_screen.dart';

void main() {
  testWidgets('Shift KPI cards have balanced heights and clean titles without Maker-Checker', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
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
              body: InventoryScreen(mode: InventoryTabMode.shiftWork),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Verify clean, enterprise shortened titles
    expect(find.text('TỔNG ĐỢT'), findsOneWidget);
    expect(find.text('CHỜ DUYỆT'), findsOneWidget);
    expect(find.text('ĐÃ DUYỆT'), findsOneWidget);
    expect(find.text('CHÊNH LỆCH'), findsOneWidget);

    // 2. Verify complete absence of "Maker-Checker"
    expect(find.textContaining('Maker-Checker'), findsNothing);
    expect(find.textContaining('maker-checker'), findsNothing);

    // 3. Verify card heights are balanced
    final rect0 = tester.getRect(find.widgetWithText(Container, 'TỔNG ĐỢT').first);
    final rect1 = tester.getRect(find.widgetWithText(Container, 'CHỜ DUYỆT').first);
    final rect2 = tester.getRect(find.widgetWithText(Container, 'ĐÃ DUYỆT').first);
    final rect3 = tester.getRect(find.widgetWithText(Container, 'CHÊNH LỆCH').first);

    expect((rect0.height - rect1.height).abs(), lessThan(2.0));
    expect((rect2.height - rect3.height).abs(), lessThan(2.0));
  });
}
