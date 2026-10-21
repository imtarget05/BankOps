import 'package:kho_tra_sua/src/app/app_shell.dart';
import 'package:kho_tra_sua/src/core/theme/app_theme.dart';
import 'package:kho_tra_sua/src/data/models/dtos.dart';
import 'package:kho_tra_sua/src/data/repositories/fake_repository.dart';
import 'package:kho_tra_sua/src/features/reports/reports_filter.dart';
import 'package:kho_tra_sua/src/features/reports/reports_screen.dart';
import 'package:kho_tra_sua/src/features/reports/widgets/meeting_report_pdf.dart';
import 'package:kho_tra_sua/src/features/reports/widgets/meeting_summary_formatter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Meeting Summary & PDF Unit Tests', () {
    test(
        'MeetingSummaryFormatter produces structured markdown with all sections',
        () {
      final md = MeetingSummaryFormatter.generateMarkdown(
        inventoryBuckets: [
          const InventoryBucket(
            bucket: '2026-10-01',
            inboundQty: '20',
            outboundQty: '5',
            netQty: '15',
            receiptCount: 2,
            issueCount: 1,
          ),
        ],
        cashflowBuckets: [
          const CashflowBucket(
            bucket: '2026-10-01',
            totalIn: '50000000',
            totalOut: '20000000',
            net: '30000000',
            journalCount: 3,
          ),
        ],
        stagnationItems: [
          const StagnationItem(
            itemId: 'item-1',
            sku: 'STK-VIP',
            name: 'Sổ tiết kiệm VIP',
            quantity: '50',
            daysSinceLastIssue: 95,
            severity: 'critical',
          ),
        ],
        reconciliations: [
          ReconciliationRun(
            id: 'rc-01',
            status: 'matched',
            scope: 'cash',
            startedAt: DateTime.now(),
            exceptions: const [],
          ),
        ],
        granularity: ReportGranularity.daily,
        staffAssessment: 'Cần lưu ý theo dõi',
        staffNotes: 'Kiến nghị xuất 50 cuốn sổ cho chi nhánh.',
      );

      expect(md, contains('BÁO CÁO VẬN HÀNH QUẢN LÝ KHO TRÀ SỮA'));
      expect(md, contains('1. DÒNG TIỀN & THANH KHOẢN'));
      expect(md, contains('2. VẬN HÀNH KHO NGUYÊN LIỆU'));
      expect(md, contains('3. ĐIỂM NÓNG TỒN ĐỌNG'));
      expect(md, contains('4. KIỂM SOÁT ĐỐI SOÁT'));
      expect(md, contains('5. TRỌNG TÂM THẢO LUẬN'));
      expect(md, contains('6. GHI CHÚ BỔ SUNG'));
      expect(md, contains('STK-VIP'));
      expect(md, contains('Kiến nghị xuất 50 cuốn sổ'));
    });

    test('MeetingReportPdf.encode generates non-empty A4 PDF document',
        () async {
      final bytes = await MeetingReportPdf.encode(
        inventoryBuckets: [
          const InventoryBucket(
            bucket: '2026-10-01',
            inboundQty: '10',
            outboundQty: '2',
            netQty: '8',
            receiptCount: 1,
            issueCount: 1,
          ),
        ],
        cashflowBuckets: [
          const CashflowBucket(
            bucket: '2026-10-01',
            totalIn: '10000000',
            totalOut: '4000000',
            net: '6000000',
            journalCount: 2,
          ),
        ],
        stagnationItems: [
          const StagnationItem(
            itemId: 'item-1',
            sku: 'PHOI-THE',
            name: 'Phôi thẻ Chip',
            quantity: '20',
            daysSinceLastIssue: 100,
            severity: 'critical',
          ),
        ],
        reconciliations: [
          ReconciliationRun(
            id: 'rc-02',
            status: 'matched',
            scope: 'cash',
            startedAt: DateTime.now(),
            exceptions: const [],
          ),
        ],
        granularity: ReportGranularity.daily,
        staffAssessment: 'Vận hành đạt chuẩn',
        staffNotes: 'Đề nghị thanh lý.',
      );

      expect(bytes.isNotEmpty, true);
    });
  });

  group('ReportsScreen Executive Business UI Tests', () {
    testWidgets(
        'Renders Executive KPI Deck, opens Voucher Print Modal, and views Report Summary',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final repo = FakeBankOpsRepository(latency: Duration.zero);
      await tester.pumpWidget(
        RepositoryScope(
          repository: repo,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: ReportsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check header and business action buttons
      expect(find.text('Báo cáo & Biểu đồ'), findsOneWidget);
      expect(find.byKey(const Key('btn-print-meeting-pdf-header')),
          findsOneWidget);
      expect(find.byKey(const Key('btn-print-vouchers-modal')), findsOneWidget);
      expect(find.byKey(const Key('btn-export-csv-reports')), findsOneWidget);

      // Check 4 Executive KPI cards
      expect(find.byKey(const Key('kpi-cash-liquidity')), findsOneWidget);
      expect(find.byKey(const Key('kpi-inventory-movement')), findsOneWidget);
      expect(find.byKey(const Key('kpi-reconciliation-rate')), findsOneWidget);
      expect(find.byKey(const Key('kpi-stagnation-risk')), findsOneWidget);

      // Open Ministry of Finance Voucher Print Center Modal
      await tester.tap(find.byKey(const Key('btn-print-vouchers-modal')));
      await tester.pumpAndSettle();

      expect(find.text('Trung Tâm In Chứng Từ & Biểu Mẫu'), findsOneWidget);
      expect(find.text('Phiếu Nhập Kho (Mẫu 01-VT)'), findsOneWidget);
      expect(find.text('Phiếu Xuất Kho (Mẫu 02-VT)'), findsOneWidget);
      expect(find.text('Phiếu Thu Tiền Mặt (Mẫu 01-TT)'), findsOneWidget);
      expect(find.text('Phiếu Chi Tiền Mặt (Mẫu 02-TT)'), findsOneWidget);
      expect(find.text('Biên Bản Kiểm Kê Kho & Bàn Giao Ca (Mẫu 05-VT)'),
          findsOneWidget);

      // Close modal by tapping outside or popping
      final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
      navigator.pop();
      await tester.pumpAndSettle();

      // Switch to Meeting Notes / Executive Summary Tab
      final tabFinder = find.byKey(const Key('tab-reports-meeting-notes'));
      await tester.ensureVisible(tabFinder);
      await tester.pumpAndSettle();
      await tester.tap(tabFinder);
      await tester.pumpAndSettle();

      expect(find.text('Báo Cáo Đánh Giá Hoạt Động & Vận Hành'), findsOneWidget);
      expect(find.text('1. ĐÁNH GIÁ TRẠNG THÁI VẬN HÀNH (STAFF ASSESSMENT)'),
          findsOneWidget);
      expect(find.textContaining('TRỌNG TÂM PHÁT BIỂU & KIẾN NGHỊ CUỘC HỌP'),
          findsOneWidget);
    });
  });
}
