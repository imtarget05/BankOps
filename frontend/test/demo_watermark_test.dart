import 'package:bankops/src/app/app_shell.dart';
import 'package:bankops/src/core/theme/app_theme.dart';
import 'package:bankops/src/core/widgets/demo_banner.dart';
import 'package:bankops/src/data/repositories/fake_repository.dart';
import 'package:bankops/src/features/integrations/import_screen.dart';
import 'package:bankops/src/features/reports/reports_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// QA-11: the "DEMO — QUỸ MÔ PHỎNG" watermark must be visible on every money
/// screen. Verified against the live bundle (string is compiled in) — these
/// tests prove the widget actually mounts and renders it.
void main() {
  const watermark = 'DEMO — QUỸ MÔ PHỎNG';

  testWidgets('DemoBanner renders the default watermark text', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: DemoBanner()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(watermark), findsOneWidget);
  });

  testWidgets('DemoBanner accepts a custom label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: DemoBanner(text: 'DEMO — KHO MÔ PHỎNG')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('DEMO — KHO MÔ PHỎNG'), findsOneWidget);
  });

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    // Tall viewport so lazily-built list children (incl. the banner) lay out.
    tester.view.physicalSize = const Size(1400, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      RepositoryScope(
        repository: FakeBankOpsRepository(latency: Duration.zero),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: screen),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('ReportsScreen mounts the demo watermark', (tester) async {
    await pumpScreen(tester, const ReportsScreen());
    expect(find.byType(DemoBanner), findsOneWidget);
    expect(find.text(watermark), findsOneWidget);
  });

  testWidgets('ImportScreen mounts the demo watermark', (tester) async {
    await pumpScreen(tester, const ImportScreen());
    expect(find.byType(DemoBanner), findsOneWidget);
    expect(find.text(watermark), findsOneWidget);
  });
}
