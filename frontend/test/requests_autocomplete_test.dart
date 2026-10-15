import 'package:kho_tra_sua/src/app/app_shell.dart';
import 'package:kho_tra_sua/src/core/theme/app_theme.dart';
import 'package:kho_tra_sua/src/data/repositories/fake_repository.dart';
import 'package:kho_tra_sua/src/features/requests/requests_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpRequests(
    WidgetTester tester, {
    bool initialOpenCreateStock = false,
    bool initialOpenCreateCash = false,
  }) async {
    tester.view
      ..physicalSize = const Size(1100, 720)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final repo = FakeBankOpsRepository(latency: Duration.zero);
    await tester.pumpWidget(
      RepositoryScope(
        repository: repo,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: RequestsScreen(
              initialOpenCreateStock: initialOpenCreateStock,
              initialOpenCreateCash: initialOpenCreateCash,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Stock reason field shows autocomplete suggestions and lets user pick one',
    (WidgetTester tester) async {
      await pumpRequests(tester, initialOpenCreateStock: true);
      await tester.pumpAndSettle();

      expect(find.text('Tạo Phiếu Kho Mới'), findsOneWidget);
      expect(
          find.byKey(const Key('stock-reason-autocomplete')), findsOneWidget);

      await tester.enterText(
          find.byKey(const Key('stock-reason-input')), 'Thay');
      await tester.pump();

      expect(find.text('Thay mới'), findsWidgets);

      await tester.tap(find.text('Thay mới'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('stock-dialog-save-btn')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Lỗi'), findsNothing);
    },
  );

  testWidgets(
    'Inventory adjustment reason field shows autocomplete suggestions and lets user pick one',
    (WidgetTester tester) async {
      await pumpRequests(tester, initialOpenCreateCash: true);
      await tester.pumpAndSettle();

      expect(find.text('Tạo Phiếu Nhập Nguyên Liệu'), findsOneWidget);
      expect(find.byKey(const Key('cash-reason-autocomplete')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('cash-reason-input')), 'Chi');
      await tester.pump();

      expect(find.text('Chi chi phí vận hành'), findsWidgets);

      await tester.tap(find.text('Chi chi phí vận hành'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('cash-dialog-save-btn')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Lỗi'), findsNothing);
    },
  );

  testWidgets('Stock reason field accepts custom text (no selection)',
      (WidgetTester tester) async {
    await pumpRequests(tester, initialOpenCreateStock: true);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('stock-reason-input')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('stock-reason-input')),
      'Lý do tùy chỉnh khác biệt',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('stock-dialog-save-btn')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Lỗi'), findsNothing);
  });

  testWidgets(
    'Cash reason field remains scrollable when keyboard is open',
    (WidgetTester tester) async {
      await pumpRequests(tester, initialOpenCreateCash: true);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('cash-reason-input')));
      await tester.pumpAndSettle();

      expect(find.byType(ConstrainedBox).evaluate().isNotEmpty, isTrue);
    },
  );
}
