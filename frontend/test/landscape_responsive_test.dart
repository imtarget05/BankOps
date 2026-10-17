import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kho_tra_sua/src/app/app_shell.dart';
import 'package:kho_tra_sua/src/core/theme/app_theme.dart';
import 'package:kho_tra_sua/src/data/models/dtos.dart';
import 'package:kho_tra_sua/src/data/repositories/fake_repository.dart';
import 'package:kho_tra_sua/src/features/approvals/approvals_screen.dart';
import 'package:kho_tra_sua/src/features/cash/cash_screen.dart';
import 'package:kho_tra_sua/src/features/inventory/inventory_screen.dart';
import 'package:kho_tra_sua/src/features/requests/requests_screen.dart';

import 'package:provider/provider.dart';
import 'package:kho_tra_sua/src/core/i18n/locale_controller.dart';

void main() {
  const user = AppUser(
    id: 'u_admin',
    username: 'admin',
    displayName: 'Quản Trị Viên',
    roles: ['admin', 'manager', 'accountant'],
  );

  Widget wrapWithScaffold(Widget child) {
    final repo = FakeBankOpsRepository(latency: Duration.zero);
    return ChangeNotifierProvider<LocaleController>(
      create: (_) => LocaleController(),
      child: RepositoryScope(
        repository: repo,
        child: SessionScope(
          user: user,
          child: MaterialApp(
            locale: const Locale('vi'),
            theme: AppTheme.light(),
            home: Scaffold(body: child),
          ),
        ),
      ),
    );
  }

  group('Landscape responsive layout tests', () {
    testWidgets('InventoryScreen renders without squishing in landscape phone mode (800x390)', (tester) async {
      tester.view.physicalSize = const Size(800, 390);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(wrapWithScaffold(const InventoryScreen(mode: InventoryTabMode.stock)));
      await tester.pumpAndSettle();

      // Check header title is visible
      expect(find.text('Quản Lý Nhập Xuất Tồn Nguyên Vật Liệu'), findsOneWidget);
      // Check action buttons are visible
      expect(find.byKey(const Key('btn-add-item')), findsOneWidget);
      expect(find.byKey(const Key('btn-import-items')), findsOneWidget);
      expect(find.byKey(const Key('btn-create-stock-request')), findsOneWidget);

      // Check that title is stacked above buttons (y of title < y of buttons)
      final titleTop = tester.getTopLeft(find.text('Quản Lý Nhập Xuất Tồn Nguyên Vật Liệu')).dy;
      final btnTop = tester.getTopLeft(find.byKey(const Key('btn-add-item'))).dy;
      expect(titleTop, lessThan(btnTop), reason: 'In landscape mode (<960px), header should stack vertically to prevent title compression');

      // Check that KPI cards are visible (scroll down in ListView if needed)
      await tester.scrollUntilVisible(find.text('TỔNG LƯỢNG TỒN KHO'), 100);
      expect(find.text('TỔNG LƯỢNG TỒN KHO'), findsOneWidget);
    });

    testWidgets('RequestsScreen renders stacked buttons in landscape phone mode (800x390)', (tester) async {
      tester.view.physicalSize = const Size(800, 390);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(wrapWithScaffold(const RequestsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Quản Lý & Lập Phiếu Yêu Cầu'), findsOneWidget);
      expect(find.byKey(const Key('btn-create-stock-request')), findsOneWidget);
      expect(find.byKey(const Key('btn-create-spoilage-request')), findsOneWidget);
      expect(find.byKey(const Key('btn-create-cash-request')), findsOneWidget);

      final titleTop = tester.getTopLeft(find.text('Quản Lý & Lập Phiếu Yêu Cầu')).dy;
      final btnTop = tester.getTopLeft(find.byKey(const Key('btn-create-stock-request'))).dy;
      expect(titleTop, lessThan(btnTop));
    });

    testWidgets('CashScreen renders stacked header in landscape phone mode (800x390)', (tester) async {
      tester.view.physicalSize = const Size(800, 390);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(wrapWithScaffold(const CashScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Quản Lý Quỹ Tiền Mặt & Két Sắt'), findsOneWidget);
      expect(find.byKey(const Key('btn-add-cashbox')), findsOneWidget);
      expect(find.byKey(const Key('btn-create-cash-request')), findsOneWidget);

      final titleTop = tester.getTopLeft(find.text('Quản Lý Quỹ Tiền Mặt & Két Sắt')).dy;
      final btnTop = tester.getTopLeft(find.byKey(const Key('btn-add-cashbox'))).dy;
      expect(titleTop, lessThan(btnTop));
    });

    testWidgets('ApprovalsScreen renders stacked badge in landscape phone mode (700x390)', (tester) async {
      tester.view.physicalSize = const Size(700, 390);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(wrapWithScaffold(const ApprovalsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Hộp Thư Phê Duyệt Yêu Cầu'), findsOneWidget);
      expect(find.byIcon(Icons.shield_outlined), findsOneWidget);

      final titleTop = tester.getTopLeft(find.text('Hộp Thư Phê Duyệt Yêu Cầu')).dy;
      final badgeTop = tester.getTopLeft(find.byIcon(Icons.shield_outlined)).dy;
      expect(titleTop, lessThan(badgeTop));
    });
  });
}
