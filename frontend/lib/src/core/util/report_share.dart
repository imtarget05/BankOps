import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../widgets/app_toast.dart';
import 'error_text.dart';

/// Chia sẻ/in file báo cáo ra ngoài app.
///
/// - XLSX: share sheet trên mobile (`Printing.sharePdf` nhận mọi bytes).
///   Trên Web không có FileSaver nên fallback về Sao chép CSV (toast hướng dẫn).
/// - PDF phiếu: `Printing.layoutPdf` in được cả Web + mobile.
class ReportShare {
  const ReportShare._();

  static Future<void> shareXlsx(
    BuildContext context, {
    required String filename,
    required List<int> bytes,
  }) async {
    try {
      if (kIsWeb) {
        if (!context.mounted) return;
        AppToast.info(
          context,
          'Trên Web hãy dùng nút Sao chép CSV rồi dán sang Excel',
        );
        return;
      }
      await Printing.sharePdf(
        bytes: Uint8List.fromList(bytes),
        filename: filename,
      );
      if (!context.mounted) return;
      AppToast.success(context, 'Đã chia sẻ file $filename');
    } catch (e) {
      if (!context.mounted) return;
      AppToast.error(context, 'Không chia sẻ được file: ${friendlyError(e)}');
    }
  }

  static Future<void> printPdf(
    BuildContext context, {
    required String filename,
    required Future<List<int>> Function() build,
  }) async {
    try {
      await Printing.layoutPdf(
        name: filename,
        onLayout: (_) async => Uint8List.fromList(await build()),
      );
    } catch (e) {
      if (!context.mounted) return;
      AppToast.error(context, 'Không in được phiếu: ${friendlyError(e)}');
    }
  }
}
