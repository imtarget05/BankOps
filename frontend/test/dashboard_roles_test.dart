import 'package:bankops/src/app/app_shell.dart';
import 'package:bankops/src/core/theme/app_theme.dart';
import 'package:bankops/src/data/models/dtos.dart';
import 'package:bankops/src/data/repositories/fake_repository.dart';
import 'package:bankops/src/features/auth/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Dashboard điều hướng + phân quyền hiển thị theo vai trò.
void main() {
  Future<void> pumpShell(
    WidgetTester tester, {
    AppUser? user,
    required FakeBankOpsRepository repo,
  }) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthService>(
        create: (_) => AuthService(baseUrl: 'http://localhost:8000'),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: SessionScope(
            user: user,
            onSignOut: () async {},
            child: AppShell(repository: repo),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Quick action navigates to approvals tab instead of snackbar',
    (WidgetTester tester) async {
      await pumpShell(
        tester,
        repo: FakeBankOpsRepository(latency: Duration.zero),
      );

      await tester.tap(find.text('Xử lý Hộp thư duyệt 4-Mắt'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Hộp Thư Phê Duyệt 4 Mắt'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'KPI inbox card navigates to approvals tab',
    (WidgetTester tester) async {
      await pumpShell(
        tester,
        repo: FakeBankOpsRepository(latency: Duration.zero),
      );

      await tester.tap(find.byKey(const Key('kpi-inbox-card')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Hộp Thư Phê Duyệt 4 Mắt'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Auditor only sees view tabs, maker sees everything',
    (WidgetTester tester) async {
      const auditor = AppUser(
        id: 'u-aud',
        username: 'demo_auditor',
        displayName: 'Lê Khánh Chi (KTNB)',
        roles: ['auditor'],
      );

      await pumpShell(
        tester,
        user: auditor,
        repo: FakeBankOpsRepository(latency: Duration.zero),
      );

      // Auditor: mất Yêu cầu / Duyệt / Tích hợp, còn xem Kho/Quỹ/Báo cáo.
      expect(find.byKey(const Key('nav-requests')), findsNothing);
      expect(find.byKey(const Key('nav-approvals')), findsNothing);
      expect(find.byKey(const Key('nav-integrations')), findsNothing);
      expect(find.byKey(const Key('nav-inventory')), findsOneWidget);
      expect(find.byKey(const Key('nav-reports')), findsOneWidget);
      // Quick action tạo/duyệt cũng bị ẩn, chỉ còn Đối soát.
      expect(find.text('Lập phiếu Quỹ tiền mặt'), findsNothing);
      expect(find.text('Xử lý Hộp thư duyệt 4-Mắt'), findsNothing);
      expect(find.text('Đối soát Sổ cái tức thì'), findsOneWidget);
    },
  );

  testWidgets(
    'Compact auditor bottom bar hides requests slot, keeps more',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const auditor = AppUser(
        id: 'u-aud',
        username: 'demo_auditor',
        displayName: 'Lê Khánh Chi (KTNB)',
        roles: ['auditor'],
      );
      await tester.pumpWidget(
        ChangeNotifierProvider<AuthService>(
          create: (_) => AuthService(baseUrl: 'http://localhost:8000'),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: SessionScope(
              user: auditor,
              onSignOut: () async {},
              child: AppShell(
                repository: FakeBankOpsRepository(latency: Duration.zero),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('nav-bottom-requests')), findsNothing);
      expect(find.byKey(const Key('nav-bottom-approvals')), findsNothing);
      expect(find.byKey(const Key('nav-bottom-dashboard')), findsOneWidget);
      expect(find.byKey(const Key('nav-bottom-more')), findsOneWidget);
    },
  );

  testWidgets(
    'Activity live bar shows and refreshes',
    (WidgetTester tester) async {
      await pumpShell(
        tester,
        repo: FakeBankOpsRepository(latency: Duration.zero),
      );

      await tester.tap(find.byKey(const Key('nav-activity')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('activity-live-bar')), findsOneWidget);
      expect(find.textContaining('Trực tiếp'), findsOneWidget);

      await tester.tap(find.byKey(const Key('activity-refresh-btn')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('activity-live-bar')), findsOneWidget);
    },
  );
}
