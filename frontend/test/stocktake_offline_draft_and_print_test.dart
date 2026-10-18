import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kho_tra_sua/src/app/app_shell.dart';
import 'package:kho_tra_sua/src/core/theme/app_theme.dart';
import 'package:kho_tra_sua/src/data/models/dtos.dart';
import 'package:kho_tra_sua/src/data/repositories/fake_repository.dart';
import 'package:kho_tra_sua/src/features/inventory/inventory_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'Stocktake dialog restores offline draft from SharedPreferences and displays print button',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final repo = FakeBankOpsRepository(latency: Duration.zero);
      final locs = await repo.getLocations();
      final items = await repo.getItems();

      // Pre-seed a stocktake
      final st = await repo.createStocktake(
        locationId: locs.first.id,
        note: 'Kiểm kê ca sáng thử nghiệm',
      );

      // Pre-seed an offline draft in SharedPreferences
      final draftPayload = {
        'stocktake_id': st.id,
        'saved_at': DateTime.now().toIso8601String(),
        'used': {items.first.id: '7.5'},
        'counted': {items.first.id: '88.0'},
        'reason': {items.first.id: 'Đếm lại ngoại tuyến'},
      };
      SharedPreferences.setMockInitialValues({
        'stocktake_draft_${st.id}': jsonEncode(draftPayload),
      });

      const user = AppUser(
        id: 'u_staff',
        username: 'demo_maker',
        displayName: 'Nhân Viên Quầy',
        roles: ['staff'],
      );

      await tester.pumpWidget(
        RepositoryScope(
          repository: repo,
          child: SessionScope(
            user: user,
            child: MaterialApp(
              theme: AppTheme.light(),
              home: const Scaffold(body: InventoryScreen()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find and open stocktake detail dialog from shift stocktake desk
      final desk = find.text('Quầy kiểm kê theo ca');
      await tester.scrollUntilVisible(desk, 500,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();

      final openBtn = find.text('Mở phiên kiểm kê');
      await tester.tap(openBtn);
      await tester.pumpAndSettle();

      // Verify draft restored notice
      expect(
        find.text('Đã khôi phục số liệu kiểm đếm từ bản nháp ngoại tuyến trên thiết bị.'),
        findsOneWidget,
      );

      // Verify Print button is present in header
      expect(find.byTooltip('In Phiếu Ca'), findsOneWidget);

      // Verify restored draft values in textfields
      expect(find.text('88.0'), findsOneWidget);
      expect(find.text('7.5'), findsOneWidget);

      // Tap Save button
      await tester.tap(find.text('Lưu Số Đếm'));
      await tester.pumpAndSettle();

      // Verify success snackbar
      expect(find.text('Đã lưu số kiểm đếm thực tế!'), findsOneWidget);
    },
  );
}
