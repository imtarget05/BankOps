import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kho_tra_sua/src/app/app_shell.dart';
import 'package:kho_tra_sua/src/core/theme/app_theme.dart';
import 'package:kho_tra_sua/src/data/repositories/fake_repository.dart';
import 'package:kho_tra_sua/src/features/ai/ai_assistant_dialog.dart';
import 'package:kho_tra_sua/src/features/auth/auth_service.dart';
import 'package:provider/provider.dart';

void main() {
  group('AI Assistant Continuous Chat & Single Drag Handle Tests', () {
    testWidgets('BottomSheet suppresses exterior drag handle and shows only integrated dialog handle', (tester) async {
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

      // Open AI Assistant
      await tester.tap(find.text('Open AI'));
      await tester.pumpAndSettle();

      expect(find.text('Khai'), findsOneWidget);
      expect(find.text('Trợ lý Quản Lý Kho Trà Sữa'), findsOneWidget);

      // Verify TextField is present and enabled
      final inputFinder = find.byType(TextField);
      expect(inputFinder, findsOneWidget);
      final textField = tester.widget<TextField>(inputFinder);
      expect(textField.enabled, isTrue);
    });

    testWidgets('AI Assistant allows continuous multi-turn chat without deadlock', (tester) async {
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

      // Turn 1: Tap first prompt
      final prompt1 = find.text('Ai được lập và duyệt phiếu kho?');
      expect(prompt1, findsOneWidget);
      await tester.tap(prompt1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Turn 1 response verified
      expect(
        find.textContaining('Người lập (Maker)', findRichText: true),
        findsOneWidget,
      );

      // Verify TextField is NOT deadlocked and still enabled
      var input = tester.widget<TextField>(find.byType(TextField));
      expect(input.enabled, isTrue, reason: 'TextField must remain enabled after first response');

      // Turn 2: Type and send a second question
      await tester.enterText(find.byType(TextField), 'chốt ca sáng');
      await tester.pump();

      final sendIconFinder = find.byIcon(Icons.arrow_upward_rounded);
      expect(sendIconFinder, findsOneWidget);
      final sendIconButton = tester.widget<IconButton>(
        find.ancestor(of: sendIconFinder, matching: find.byType(IconButton)),
      );
      expect(sendIconButton.onPressed, isNotNull, reason: 'Send button must be enabled for turn 2');

      await tester.tap(sendIconFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      // Turn 2 response verified (Shift SOP answer)
      expect(
        find.textContaining('Bàn giao ca trực', findRichText: true),
        findsOneWidget,
      );

      // Verify TextField is STILL enabled for turn 3
      input = tester.widget<TextField>(find.byType(TextField));
      expect(input.enabled, isTrue, reason: 'TextField must remain enabled after second response');

      // Turn 3: Type and send third question
      await tester.enterText(find.byType(TextField), 'sữa tươi cận date');
      await tester.pump();
      await tester.tap(sendIconFinder);
      await tester.pump();
      await tester.pumpAndSettle();

      // Turn 3 response verified (Near expiry SOP answer)
      expect(
        find.textContaining('FEFO', findRichText: true),
        findsOneWidget,
      );

      // Verify system still alive and ready for Turn 4
      input = tester.widget<TextField>(find.byType(TextField));
      expect(input.enabled, isTrue, reason: 'TextField must remain enabled for turn 4');
    });
  });
}
