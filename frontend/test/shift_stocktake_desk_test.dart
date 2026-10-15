import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kho_tra_sua/src/features/inventory/shift_stocktake_desk.dart';

void main() {
  testWidgets('counter desk shows all shifts and reconciliation columns',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ShiftStocktakeDesk(
            lines: [
              ShiftStocktakeLine(
                name: 'Sữa tươi',
                unit: 'hộp',
                openingQty: 12,
                receivedQty: 4,
                usedQty: 7,
                countedQty: 8,
                reason: 'Hỏng 1 hộp',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Quầy kiểm kê theo ca'), findsOneWidget);
    expect(find.text('Ca Sáng\n07:30 – 15:00'), findsOneWidget);
    expect(find.text('Ca Chiều\n15:00 – 23:00'), findsOneWidget);
    expect(find.text('Ca Lỡ\n07:30 – 18:00'), findsOneWidget);
    expect(find.text('Tồn đầu'), findsOneWidget);
    expect(find.text('Tồn lý thuyết'), findsOneWidget);
    expect(find.text('Kiểm thực tế'), findsOneWidget);
    expect(find.text('Độ lệch'), findsOneWidget);
    expect(find.text('Lệch -1'), findsOneWidget);
    expect(find.text('Cần đối soát'), findsOneWidget);

    await tester.tap(find.text('Ca Chiều\n15:00 – 23:00'));
    await tester.pump();
    expect(find.text('Ca Chiều · 15:00 – 23:00'), findsOneWidget);
  });
}
