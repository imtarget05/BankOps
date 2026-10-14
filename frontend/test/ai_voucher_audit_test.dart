import 'package:bankops/src/core/util/approval_pdf.dart';
import 'package:bankops/src/data/models/dtos.dart';
import 'package:bankops/src/features/ai/ai_voucher_audit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AiVoucherAuditor Logic Tests', () {
    test('Flags unapproved status as compliance violation', () {
      const pendingItem = ApprovalItem(
        id: 'REQ-001',
        kind: 'Tiền mặt (Chi)',
        maker: 'demo_maker',
        impact: '10.000.000 VND',
        detail: 'Chi tiền mua vật tư văn phòng',
        status: 'pending',
      );

      final result = AiVoucherAuditor.checkApprovalItem(pendingItem, null);
      expect(result.hasErrors, isTrue);
      expect(
        result.warnings.any((w) => w.contains('chưa hoàn tất phê duyệt')),
        isTrue,
      );
      expect(result.recommendations.isNotEmpty, isTrue);
    });

    test('Flags empty or missing transaction reason', () {
      const itemEmptyReason = ApprovalItem(
        id: 'REQ-002',
        kind: 'Tiền mặt (Thu)',
        maker: 'demo_maker',
        impact: '50.000.000 VND',
        detail: '',
        status: 'approved',
      );

      final result = AiVoucherAuditor.checkApprovalItem(itemEmptyReason, null);
      expect(result.hasErrors, isTrue);
      expect(
        result.warnings.any((w) => w.contains('Nội dung hoặc lý do')),
        isTrue,
      );
    });

    test('Flags high-value transaction exceeding threshold (>= 500M VND)', () {
      const bigItem = ApprovalItem(
        id: 'REQ-003',
        kind: 'Tiền mặt (Chi)',
        maker: 'demo_maker',
        impact: '650.000.000 VND',
        detail: 'Tiếp quỹ phòng giao dịch cuối tuần',
        status: 'approved',
      );

      final result = AiVoucherAuditor.checkApprovalItem(bigItem, null);
      expect(result.hasErrors, isTrue);
      expect(
        result.warnings.any((w) => w.contains('vượt hạn mức kiểm soát 500.000.000 VND')),
        isTrue,
      );
    });

    test('Incorporates AI risk assessment flags and high risk scores', () {
      const item = ApprovalItem(
        id: 'REQ-004',
        kind: 'Tiền mặt (Chi)',
        maker: 'demo_maker',
        impact: '50.000.000 VND',
        detail: 'Giao dịch thường',
        status: 'approved',
      );

      const highRisk = AiRiskAssessment(
        requestId: 'REQ-004',
        riskLevel: 'high',
        riskScore: 85,
        summary: 'Tần suất rút tiền bất thường trong 24h',
        flaggedRules: ['QUY_CHE_04_RUT_TIEN_DOT_BIEN'],
        recommendations: ['Yêu cầu Giám đốc chi nhánh ký duyệt bổ sung'],
        auditStamp: 'AI-STAMP-TEST-85',
        assessmentSource: 'cloudflare',
      );

      final result = AiVoucherAuditor.checkApprovalItem(item, highRisk);
      expect(result.hasErrors, isTrue);
      expect(
        result.warnings.any((w) => w.contains('rủi ro cao (85/100)')),
        isTrue,
      );
      expect(
        result.warnings.any((w) => w.contains('QUY_CHE_04_RUT_TIEN_DOT_BIEN')),
        isTrue,
      );
      expect(
        result.recommendations.any((r) => r.contains('Giám đốc chi nhánh')),
        isTrue,
      );
    });

    test('Clean approved item passes with zero errors', () {
      const cleanItem = ApprovalItem(
        id: 'REQ-005',
        kind: 'Tiền mặt (Chi)',
        maker: 'demo_maker',
        impact: '15.000.000 VND',
        detail: 'Thanh toán hoá đơn tiền điện tháng 10/2026',
        status: 'approved',
      );

      const cleanAssessment = AiRiskAssessment(
        requestId: 'REQ-005',
        riskLevel: 'low',
        riskScore: 10,
        summary: 'Giao dịch hợp lệ, trong hạn mức cho phép',
        flaggedRules: [],
        recommendations: [],
        auditStamp: 'AI-CLEAN-STAMP',
        assessmentSource: 'cloudflare',
      );

      final result = AiVoucherAuditor.checkApprovalItem(cleanItem, cleanAssessment);
      expect(result.hasErrors, isFalse);
      expect(result.warnings, isEmpty);
    });
  });

  group('ApprovalPdf AI Audit Stamp Integration Tests', () {
    test('ApprovalPdf.encode generates valid PDF with AI warnings and stamps', () async {
      const item = ApprovalItem(
        id: 'REQ-999',
        kind: 'Tiền mặt (Chi)',
        maker: 'demo_maker',
        impact: '800.000.000 VND',
        detail: 'Rút tiền gửi tiết kiệm',
        status: 'pending',
      );

      final pdfBytes = await ApprovalPdf.encode(
        item,
        auditWarnings: [
          'Chưa hoàn tất phê duyệt',
          'Vượt hạn mức 500tr VND',
        ],
      );

      expect(pdfBytes, isNotEmpty);
      expect(pdfBytes.length, greaterThan(1000));
    });

    test('ApprovalPdf.encode generates valid PDF with clean AI verification stamp', () async {
      const item = ApprovalItem(
        id: 'REQ-1000',
        kind: 'Tiền mặt (Thu)',
        maker: 'demo_maker',
        impact: '20.000.000 VND',
        detail: 'Nộp tiền mặt định kỳ',
        status: 'approved',
      );

      final pdfBytes = await ApprovalPdf.encode(item);
      expect(pdfBytes, isNotEmpty);
      expect(pdfBytes.length, greaterThan(1000));
    });
  });

  group('AiVoucherAuditDialog UI Tests', () {
    testWidgets('AiVoucherAuditDialog displays warning report and action buttons',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const item = ApprovalItem(
        id: 'REQ-TEST-01',
        kind: 'Tiền mặt (Chi)',
        maker: 'demo_maker',
        impact: '700.000.000 VND',
        detail: 'Chi tiền gấp',
        status: 'pending',
      );

      final auditResult = AiVoucherAuditor.checkApprovalItem(item, null);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => AiVoucherAuditDialog.show(
                  ctx,
                  item: item,
                  result: auditResult,
                ),
                child: const Text('Open Audit Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Audit Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('AI Kiểm Tra Chứng Từ & Báo Cáo Sai Sót'), findsOneWidget);
      expect(find.textContaining('Qwen2.5-1.5B Fine-Tuned (Production)'), findsOneWidget);
      expect(find.byKey(const Key('voucher-audit-cancel-btn')), findsOneWidget);
      expect(find.byKey(const Key('voucher-audit-confirm-btn')), findsOneWidget);

      // Tap cancel closes dialog
      await tester.tap(find.byKey(const Key('voucher-audit-cancel-btn')));
      await tester.pumpAndSettle();
      expect(find.byType(AiVoucherAuditDialog), findsNothing);
    });
  });
}
