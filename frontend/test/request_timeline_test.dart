import 'package:kho_tra_sua/src/app/app_shell.dart';
import 'package:kho_tra_sua/src/core/theme/app_theme.dart';
import 'package:kho_tra_sua/src/data/repositories/fake_repository.dart';
import 'package:kho_tra_sua/src/features/requests/request_timeline.dart';
import 'package:kho_tra_sua/src/features/requests/requests_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'RequestTimeline shows events for the request in time order',
    (WidgetTester tester) async {
      final repo = FakeBankOpsRepository(latency: Duration.zero);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RequestTimeline(requestId: 'sr-0001', repo: repo),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('request-timeline-sr-0001')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('timeline-event-ae-0001')), findsOneWidget);
      expect(find.textContaining('Tạo phiếu'), findsOneWidget);
    },
  );

  testWidgets(
    'RequestTimeline shows empty state when no history',
    (WidgetTester tester) async {
      final repo = FakeBankOpsRepository(latency: Duration.zero);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RequestTimeline(requestId: 'no-such-id', repo: repo),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Chưa có lịch sử'), findsOneWidget);
    },
  );

  testWidgets(
    'RequestsScreen history button opens timeline sheet',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        RepositoryScope(
          repository: FakeBankOpsRepository(latency: Duration.zero),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: RequestsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('request-history-stock-sr-0001')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('request-timeline-sr-0001')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('timeline-event-ae-0001')), findsOneWidget);
    },
  );
}
