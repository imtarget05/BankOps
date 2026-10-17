import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kho_tra_sua/src/app/app_shell.dart';
import 'package:kho_tra_sua/src/core/theme/app_theme.dart';
import 'package:kho_tra_sua/src/data/repositories/fake_repository.dart';
import 'package:kho_tra_sua/src/features/auth/auth_service.dart';
import 'package:kho_tra_sua/src/features/settings/settings_screen.dart';
import 'package:provider/provider.dart';

void main() {
  group('PWA Install & iOS Guide Redesign Tests', () {
    testWidgets('Settings screen renders redesigned install card, non-breaking pill tabs and handles click', (tester) async {
      final repo = FakeBankOpsRepository(latency: Duration.zero);
      final auth = AuthService();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: auth),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: RepositoryScope(
              repository: repo,
              child: const Scaffold(
                body: SettingsScreen(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll down to the install card in the long Settings list
      await tester.scrollUntilVisible(
        find.byKey(const Key('btn-install-pwa')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Ensure 1-Click PWA button is present with clean, non-blocky styling
      final installBtn = find.byKey(const Key('btn-install-pwa'));
      expect(installBtn, findsOneWidget);

      // Verify the horizontal platform pills exist
      expect(find.text('iPhone / Safari'), findsOneWidget);
      expect(find.text('Android / Chrome'), findsOneWidget);
      expect(find.text('Zalo / Quét QR'), findsOneWidget);

      // Tap iPhone pill
      await tester.tap(find.text('iPhone / Safari'));
      await tester.pumpAndSettle();

      // Check iOS specific guide contents
      expect(find.textContaining('Nhấn nút Chia sẻ (Share ⎋)'), findsOneWidget);
      expect(find.textContaining('Thêm vào MH chính'), findsWidgets);

      // Tap Android pill
      await tester.tap(find.text('Android / Chrome'));
      await tester.pumpAndSettle();

      // Check Android specific guide contents
      expect(find.textContaining('Nhấn menu 3 chấm (⋮)'), findsOneWidget);
      expect(find.textContaining('Chọn "Cài đặt ứng dụng"'), findsOneWidget);

      // Tap the Install button to trigger install / guide modal
      await tester.tap(installBtn);
      await tester.pumpAndSettle();

      // Modal should appear with clear visual steps
      expect(find.text('Đã hiểu, tiến hành ngay'), findsOneWidget);
      expect(find.textContaining('Cài đặt trên'), findsWidgets);

      // Dismiss modal
      await tester.tap(find.text('Đã hiểu, tiến hành ngay'));
      await tester.pumpAndSettle();

      expect(find.text('Đã hiểu, tiến hành ngay'), findsNothing);
    });

    testWidgets('Small mobile screen layout (360px) does not overflow or wrap words awkwardly', (tester) async {
      // Simulate narrow mobile phone
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = FakeBankOpsRepository(latency: Duration.zero);
      final auth = AuthService();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: auth),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: RepositoryScope(
              repository: repo,
              child: const Scaffold(
                body: SettingsScreen(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Ensure no overflow errors occurred
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('btn-install-pwa')), findsOneWidget);
    });

    testWidgets('Settings screen provides force sync & clear cache buttons', (tester) async {
      final repo = FakeBankOpsRepository(latency: Duration.zero);
      final auth = AuthService();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: auth),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: RepositoryScope(
              repository: repo,
              child: const Scaffold(
                body: SettingsScreen(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('btn-force-sync-app')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      final forceSyncBtn = find.byKey(const Key('btn-force-sync-app'));
      expect(forceSyncBtn, findsOneWidget);

      await tester.tap(forceSyncBtn);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('Đang đồng bộ'), findsOneWidget);
      
      // Clear snackbars so the next button tap can show its own toast
      ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first)).clearSnackBars();
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('btn-sync-app-version')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      final versionSyncBtn = find.byKey(const Key('btn-sync-app-version'));
      expect(versionSyncBtn, findsOneWidget);

      await tester.tap(versionSyncBtn);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('Đang làm sạch bộ nhớ tạm'), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });
}
