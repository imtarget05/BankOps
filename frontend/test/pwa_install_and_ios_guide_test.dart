import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kho_tra_sua/src/app/app_shell.dart';
import 'package:kho_tra_sua/src/core/theme/app_theme.dart';
import 'package:kho_tra_sua/src/data/repositories/fake_repository.dart';
import 'package:kho_tra_sua/src/features/auth/auth_service.dart';
import 'package:kho_tra_sua/src/features/settings/settings_screen.dart';
import 'package:provider/provider.dart';

void main() {
  group('PWA Install & Simplified Background Install Tests', () {
    testWidgets('Settings screen renders streamlined 1-click install card with QR code, hides manual guides', (tester) async {
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

      // Scroll down to the install card in the Settings list
      await tester.scrollUntilVisible(
        find.byKey(const Key('btn-install-pwa')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Ensure 1-Click PWA button and QR code are present
      final installBtn = find.byKey(const Key('btn-install-pwa'));
      expect(installBtn, findsOneWidget);
      expect(find.text('Quét mã trên điện thoại'), findsOneWidget);

      // Verify the old platform pills and 4-step guides are removed/hidden
      expect(find.text('iPhone / Safari'), findsNothing);
      expect(find.text('Android / Chrome'), findsNothing);
      expect(find.text('Zalo / Quét QR'), findsNothing);
      expect(find.textContaining('Nhấn nút Chia sẻ (Share ⎋)'), findsNothing);

      // Tap the Install button to trigger background execution without modal popup
      await tester.tap(installBtn);
      await tester.pumpAndSettle();

      // Ensure no blocking modal sheet was popped up
      expect(find.byType(BottomSheet), findsNothing);
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

    testWidgets('Settings screen removed duplicate sync buttons and build line, leaving clean Quản lý kho', (tester) async {
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

      // Duplicate sync buttons should not exist
      expect(find.byKey(const Key('btn-force-sync-app')), findsNothing);
      expect(find.byKey(const Key('btn-sync-app-version')), findsNothing);

      // Build number line should not be exposed
      expect(find.textContaining('Build:'), findsNothing);

      // Clean text Quản lý kho should be displayed
      expect(find.text('Quản lý kho'), findsOneWidget);
      expect(find.text('Hệ thống quản lý bán hàng và kho hàng'), findsOneWidget);
    });
  });
}
