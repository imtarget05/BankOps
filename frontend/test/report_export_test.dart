import 'package:bankops/src/core/util/approval_pdf.dart';
import 'package:bankops/src/core/util/report_excel.dart';
import 'package:bankops/src/data/models/dtos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ReportExcel.encodeInventory produces non-empty xlsx bytes', () {
    final bytes = ReportExcel.encodeInventory([
      const InventoryBucket(
        bucket: '2026-10-01',
        inboundQty: '10',
        outboundQty: '4',
        netQty: '6',
        receiptCount: 1,
        issueCount: 1,
      ),
    ]);
    expect(bytes.isNotEmpty, true);
    // Đọc lại: đúng sheet + header + 1 dòng dữ liệu.
    final back = ReportExcel.decodeSheet(bytes, 'NhapXuatKho');
    expect(back.length, 2);
    expect(back.first.first, 'bucket');
    expect(back[1].first, '2026-10-01');
  });

  test('ReportExcel.encodeCashflow produces non-empty xlsx bytes', () {
    final bytes = ReportExcel.encodeCashflow([
      const CashflowBucket(
        bucket: '2026-10',
        totalIn: '50000000',
        totalOut: '35000000',
        net: '15000000',
        journalCount: 3,
      ),
    ]);
    expect(bytes.isNotEmpty, true);
    final back = ReportExcel.decodeSheet(bytes, 'DongTien');
    expect(back.length, 2);
    expect(back.first.first, 'bucket');
  });

  test('ReportExcel.encodeStagnation produces non-empty xlsx bytes', () {
    final bytes = ReportExcel.encodeStagnation([
      const StagnationItem(
        itemId: 'id-1',
        sku: 'DEMO-LAPTOP',
        name: 'Phôi thẻ',
        quantity: '5',
        daysSinceLastIssue: 95,
        severity: 'critical',
      ),
    ]);
    expect(bytes.isNotEmpty, true);
    final back = ReportExcel.decodeSheet(bytes, 'TonDong');
    expect(back.length, 2);
    expect(back[1].first, 'DEMO-LAPTOP');
  });

  test('ApprovalPdf.encode produces a one-page PDF', () async {
    final bytes = await ApprovalPdf.encode(
      const ApprovalItem(
        id: 'sr-0002',
        kind: 'inventory',
        maker: 'Trần Tuấn Bình (KSV)',
        impact: 'Kho (payment)',
        detail: 'Xuất phôi thẻ Visa',
      ),
    );
    expect(bytes.isNotEmpty, true);
    // Magic header của PDF.
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('VnAscii.strip removes Vietnamese diacritics', () {
    expect(VnAscii.strip('Người lập (Maker)'), 'Nguoi lap (Maker)');
    expect(VnAscii.strip('PHIẾU MÔ PHỎNG — ĐỢT 1'), 'PHIEU MO PHONG - DOT 1');
    expect(VnAscii.strip('sr-0002'), 'sr-0002');
  });
}
