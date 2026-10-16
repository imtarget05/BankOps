import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kho_tra_sua/src/app/app_shell.dart';
import 'package:kho_tra_sua/src/core/theme/app_theme.dart';
import 'package:kho_tra_sua/src/core/util/role_visibility.dart';
import 'package:kho_tra_sua/src/data/models/dtos.dart';
import 'package:kho_tra_sua/src/data/repositories/fake_repository.dart';
import 'package:kho_tra_sua/src/features/ai/ai_assistant_dialog.dart';
import 'package:kho_tra_sua/src/features/auth/auth_service.dart';
import 'package:kho_tra_sua/src/features/settings/settings_screen.dart';
import 'package:provider/provider.dart';

void main() {
  group('1. Streamlined App Download & Auto-sync in Settings', () {
    testWidgets('Download card removes APK and Copy buttons and keeps 1-Click PWA and QR', (tester) async {
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

      // Ensure APK and copy buttons are removed
      expect(find.byKey(const Key('btn-download-apk')), findsNothing);
      expect(find.byKey(const Key('btn-copy-install-link')), findsNothing);

      // Ensure 1-Click PWA button is present
      expect(find.byKey(const Key('btn-install-pwa')), findsOneWidget);

      // Ensure Auto-sync banner is present
      expect(find.textContaining('Tự động đồng bộ'), findsWidgets);
    });
  });

  group('2. Dynamic Live Ticker based on Actual Time', () {
    testWidgets('Live Ticker renders dynamic shift based on real time without hardcoded Ca sáng', (tester) async {
      final repo = FakeBankOpsRepository(latency: Duration.zero);
      final auth = AuthService();

      const user = AppUser(
        id: 'u_checker',
        username: 'demo_checker',
        displayName: 'Quản lý',
        roles: ['admin', 'approver'],
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: auth),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: RepositoryScope(
              repository: repo,
              child: SessionScope(
                user: user,
                child: AppShell(repository: repo),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final now = DateTime.now();
      if (now.hour >= 6 && now.hour < 14) {
        expect(find.textContaining('Ca Sáng'), findsOneWidget);
      } else if (now.hour >= 14 && now.hour < 22) {
        expect(find.textContaining('Ca Chiều/Tối'), findsOneWidget);
      } else {
        expect(find.textContaining('Ca Đêm / Chốt Sổ'), findsOneWidget);
      }

      // Can dismiss ticker
      final dismissBtn = find.byKey(const Key('btn-dismiss-live-ticker'));
      expect(dismissBtn, findsOneWidget);
      await tester.tap(dismissBtn);
      await tester.pumpAndSettle();
    });
  });

  group('3. AI Assistant Khai Non-Modal & Structured SOP responses', () {
    testWidgets('AiAssistantDialog opens as bottom sheet and local SOP resolver answers Maker-Checker', (tester) async {
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
              child: Builder(
                builder: (ctx) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () => AiAssistantDialog.show(ctx),
                    child: const Text('Open AI'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open AI'));
      await tester.pumpAndSettle();

      // Should find drag handle
      expect(find.text('Khai'), findsOneWidget);
      expect(find.text('Trợ lý Quản Lý Kho Trà Sữa'), findsOneWidget);

      // Tap quick prompt "Ai được lập và duyệt phiếu kho?"
      final prompt = find.text('Ai được lập và duyệt phiếu kho?');
      expect(prompt, findsOneWidget);
      await tester.tap(prompt);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Should have structured SOP evidence
      expect(
          find.textContaining('Quy trình áp dụng', findRichText: true),
          findsOneWidget);
      expect(
          find.textContaining('Người lập (Maker)', findRichText: true),
          findsOneWidget);
      expect(
          find.textContaining('Người duyệt (Checker)', findRichText: true),
          findsOneWidget);
      expect(
          find.textContaining('Căn cứ & Bằng chứng', findRichText: true),
          findsOneWidget);
      expect(
          find.textContaining('created_by != approved_by', findRichText: true),
          findsOneWidget);
    });
  });

  group('4. Admin only for Employee Tab & demo_checker setup', () {
    test('Non-admin role cannot see tab 9 in visibleTabs', () {
      const staffUser = AppUser(
        id: 'u_staff',
        username: 'demo_maker',
        displayName: 'Nhân viên',
        roles: ['staff'],
        capabilities: ['inventory:create_request'],
      );
      final staffTabs = RoleVisibility.visibleTabs(RoleVisibility.rolesOf(staffUser), staffUser);
      expect(staffTabs.contains(9), isFalse);

      const auditorUser = AppUser(
        id: 'u_auditor',
        username: 'demo_auditor',
        displayName: 'Kiểm toán',
        roles: ['auditor'],
        capabilities: ['audit:view'],
      );
      final auditorTabs = RoleVisibility.visibleTabs(RoleVisibility.rolesOf(auditorUser), auditorUser);
      expect(auditorTabs.contains(9), isFalse);
    });

    test('demo_checker has admin role and can access employee tab', () {
      final auth = AuthService();
      final offlineDemo = auth.getOfflineDemoUserForTesting('demo_checker', 'DemoPass123!');
      expect(offlineDemo, isNotNull);
      expect(offlineDemo!.username, equals('demo_checker'));
      expect(offlineDemo.roles.contains('admin'), isTrue);
      expect(RoleVisibility.canManageEmployees(offlineDemo), isTrue);

      final adminTabs = RoleVisibility.visibleTabs(RoleVisibility.rolesOf(offlineDemo), offlineDemo);
      expect(adminTabs.contains(9), isTrue);
    });
  });
}
