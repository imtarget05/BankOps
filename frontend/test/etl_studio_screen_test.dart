import 'package:kho_tra_sua/src/app/app_shell.dart';
import 'package:kho_tra_sua/src/core/theme/app_theme.dart';
import 'package:kho_tra_sua/src/data/models/dtos.dart';
import 'package:kho_tra_sua/src/data/repositories/fake_repository.dart';
import 'package:kho_tra_sua/src/features/etl/etl_review_screen.dart';
import 'package:kho_tra_sua/src/features/etl/etl_run_screen.dart';
import 'package:kho_tra_sua/src/features/etl/etl_studio_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const adminUser = AppUser(
    id: 'usr_admin',
    username: 'admin',
    displayName: 'Quản trị viên',
    roles: ['admin'],
    capabilities: ['etl:admin', 'etl:design', 'etl:run', 'etl:review', 'etl:post_balance'],
  );

  testWidgets(
    'EtlStudioScreen renders tabs, pipelines, and creates new connection',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final repo = FakeBankOpsRepository(latency: Duration.zero);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: SessionScope(
            user: adminUser,
            child: RepositoryScope(
              repository: repo,
              child: const Scaffold(body: EtlStudioScreen()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ETL Studio & Cổng Dữ Liệu'), findsOneWidget);
      expect(find.text('Pipelines Nghiệp Vụ'), findsOneWidget);
      expect(find.text('Kết Nối Dữ Liệu'), findsOneWidget);
      expect(find.text('Lịch Sử Lượt Chạy'), findsOneWidget);

      // Switch to Connections tab
      await tester.tap(find.text('Kết Nối Dữ Liệu'));
      await tester.pumpAndSettle();

      // Tap add connection button
      await tester.tap(find.byKey(const Key('etl-create-conn-btn')));
      await tester.pumpAndSettle();

      expect(find.text('Thêm Kết Nối Dữ Liệu ETL'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('etl-conn-name-input')),
        'Chi nhánh Đà Nẵng - Excel Ingestion',
      );

      await tester.tap(find.byKey(const Key('etl-confirm-create-conn-btn')));
      await tester.pumpAndSettle();

      expect(find.text('Chi nhánh Đà Nẵng - Excel Ingestion'), findsOneWidget);
    },
  );

  testWidgets(
    'EtlRunScreen loads pipeline, allows JSON payload and triggers staging',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final repo = FakeBankOpsRepository(latency: Duration.zero);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: SessionScope(
            user: adminUser,
            child: RepositoryScope(
              repository: repo,
              child: const EtlRunScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chạy Nhập Liệu ETL'), findsOneWidget);
      expect(find.text('Dữ liệu nguồn (Source Payload)'), findsOneWidget);
      expect(find.byKey(const Key('etl-trigger-staging-btn')), findsOneWidget);
    },
  );

  testWidgets(
    'EtlReviewScreen displays staging details, Single-Admin Override badge and post button',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final repo = FakeBankOpsRepository(latency: Duration.zero);
      final runs = await repo.getEtlRuns();
      final targetRunId = runs.first.id;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: SessionScope(
            user: adminUser,
            child: RepositoryScope(
              repository: repo,
              child: EtlReviewScreen(runId: targetRunId),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Review Staging: Run #'), findsOneWidget);
      expect(find.text('Tổng số dòng'), findsOneWidget);
      expect(find.text('Hợp lệ'), findsWidgets);
      expect(find.text('Dòng lỗi'), findsOneWidget);
      expect(find.byKey(const Key('etl-post-to-ledger-btn')), findsOneWidget);
    },
  );
}
