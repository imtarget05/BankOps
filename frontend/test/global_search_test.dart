import 'package:bankops/src/app/app_shell.dart';
import 'package:bankops/src/core/theme/app_theme.dart';
import 'package:bankops/src/core/widgets/global_search.dart';
import 'package:bankops/src/data/repositories/fake_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Global search finds seeded items and returns target tab',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final repo = FakeBankOpsRepository(latency: Duration.zero);
      int? navigatedTo;
      await tester.pumpWidget(
        RepositoryScope(
          repository: repo,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => FilledButton(
                  key: const Key('open-search-btn'),
                  onPressed: () async {
                    navigatedTo =
                        await showGlobalSearch(context, repo);
                  },
                  child: const Text('Mở tìm kiếm'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open-search-btn')));
      await tester.pumpAndSettle();

      // Chưa gõ: hiện lối tắt nhanh.
      expect(find.text('Hộp thư duyệt'), findsOneWidget);

      // Gõ SKU vật tư -> kết quả nhóm Kho, bấm -> về tab Kho (1).
      await tester.enterText(
        find.byKey(const Key('global-search-input')),
        'DEMO-PAPER',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('global-search-hit-0')), findsOneWidget);
      await tester.tap(find.byKey(const Key('global-search-hit-0')));
      await tester.pumpAndSettle();
      expect(navigatedTo, 1);
    },
  );

  testWidgets(
    'Global search quick link navigates to approvals tab',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final repo = FakeBankOpsRepository(latency: Duration.zero);
      int? navigatedTo;
      await tester.pumpWidget(
        RepositoryScope(
          repository: repo,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => FilledButton(
                  key: const Key('open-search-btn'),
                  onPressed: () async {
                    navigatedTo =
                        await showGlobalSearch(context, repo);
                  },
                  child: const Text('Mở tìm kiếm'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open-search-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('global-search-quick-4')));
      await tester.pumpAndSettle();
      expect(navigatedTo, 4);
    },
  );
}
