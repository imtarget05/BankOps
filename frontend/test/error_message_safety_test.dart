import 'dart:async';

import 'package:bankops/src/core/theme/app_theme.dart';
import 'package:bankops/src/core/widgets/async_view.dart';
import 'package:bankops/src/data/repositories/bankops_repository.dart';
import 'package:bankops/src/features/auth/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

/// QA-11: error surfaces must never leak the internal backend URL or a raw
/// transport exception (e.g. `ClientException: Failed to fetch, uri=https://…modal.run/…`).
/// Observed live: aborting the API made ReportsScreen print the raw Modal URL
/// straight into the UI.
void main() {
  const rawLeak = 'ClientException: Failed to fetch, '
      'uri=https://imtarget05--bankops-api-api.us-east.modal.run/api/v1/reports/inventory-daily';
  const host = 'imtarget05--bankops-api-api.us-east.modal.run';

  Future<void> pumpAsync(WidgetTester tester, Object error) async {
    // Attach the listener first, then complete with the error — otherwise the
    // Future.error is thrown before FutureBuilder subscribes and flutter_test
    // reports it as an unhandled zone error.
    final completer = Completer<String>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: AsyncView<String>(
            future: completer.future,
            builder: (context, data) => Text(data),
          ),
        ),
      ),
    );
    await tester.pump();
    completer.completeError(error);
    await tester.pumpAndSettle();
  }

  group('AsyncView error formatting', () {
    testWidgets('generic transport exception is shown friendly, no URL leaked',
        (tester) async {
      await pumpAsync(tester, Exception(rawLeak));
      expect(find.textContaining(host), findsNothing);
      expect(find.textContaining('ClientException'), findsNothing);
      expect(find.textContaining('uri='), findsNothing);
      expect(find.textContaining('Không kết nối'), findsOneWidget);
    });

    testWidgets('ApiException message is preserved (server is the source)',
        (tester) async {
      await pumpAsync(tester, ApiException('NOT_FOUND', 'Phiếu không tồn tại'));
      expect(find.text('Phiếu không tồn tại'), findsOneWidget);
    });

    testWidgets('FormatException message is preserved', (tester) async {
      await pumpAsync(tester, const FormatException('Dữ liệu trả về không hợp lệ'));
      expect(find.text('Dữ liệu trả về không hợp lệ'), findsOneWidget);
    });
  });

  group('AuthService error formatting', () {
    test('network failure does not leak baseUrl or raw exception', () async {
      final client = MockClient((request) async {
        throw Exception(rawLeak);
      });
      final service = AuthService(
        baseUrl: 'https://$host',
        httpClient: client,
      );
      final ok = await service.signInWithPassword(
        username: 'demo_admin',
        password: 'DemoPass123!',
      );
      expect(ok, isFalse);
      expect(service.lastError, isNotNull);
      expect(service.lastError, isNot(contains(host)));
      expect(service.lastError, isNot(contains('ClientException')));
      expect(service.lastError, contains('Không kết nối'));
    });
  });
}
