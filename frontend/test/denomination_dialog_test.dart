import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bankops/src/features/requests/widgets/denomination_breakdown_dialog.dart';

void main() {
  testWidgets('DenominationBreakdownDialog calculates total and returns DenominationResult',
      (tester) async {
    DenominationResult? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showDialog<DenominationResult>(
                  context: context,
                  builder: (_) => const DenominationBreakdownDialog(),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    // Open dialog
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Verify dialog title
    expect(find.text('Bảng Kê Mệnh Giá Tiền Mặt'), findsOneWidget);

    // Enter 10 notes for 500k -> 5,000,000 VND
    await tester.enterText(find.byKey(const Key('denom-input-500000')), '10');
    await tester.pump();

    // Enter 20 notes for 200k -> 4,000,000 VND
    await tester.enterText(find.byKey(const Key('denom-input-200000')), '20');
    await tester.pump();

    // Verify total header shows 9.000.000 đ and 30 tờ
    expect(find.text('9.000.000 đ'), findsWidgets);
    expect(find.text('30 tờ'), findsOneWidget);

    // Tap apply
    await tester.tap(find.byKey(const Key('apply-denomination-btn')));
    await tester.pumpAndSettle();

    // Verify result
    expect(result, isNotNull);
    expect(result!.totalAmount, 9000000);
    expect(result!.counts[500000], 10);
    expect(result!.counts[200000], 20);
    expect(result!.breakdownSummary, contains('500k: 10 tờ'));
    expect(result!.breakdownSummary, contains('200k: 20 tờ'));
  });
}
