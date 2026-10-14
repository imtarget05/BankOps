import 'package:flutter/material.dart';

import '../../data/models/dtos.dart';

/// Kết quả kiểm tra sai sót chứng từ/hoá đơn bởi mô hình AI.
class VoucherAuditResult {
  const VoucherAuditResult({
    required this.hasErrors,
    required this.warnings,
    required this.recommendations,
    this.assessment,
  });

  final bool hasErrors;
  final List<String> warnings;
  final List<String> recommendations;
  final AiRiskAssessment? assessment;
}

/// Trình thẩm định và kiểm tra chứng từ tự động bằng AI trước khi xuất hoá đơn/phiếu.
class AiVoucherAuditor {
  const AiVoucherAuditor._();

  static VoucherAuditResult checkApprovalItem(
    ApprovalItem item,
    AiRiskAssessment? assessment,
  ) {
    final warnings = <String>[];
    final recommendations = <String>[];

    // 1. Kiểm tra trạng thái phê duyệt của chứng từ
    final statusLower = item.status.toLowerCase();
    if (statusLower != 'approved') {
      final statusVi = switch (statusLower) {
        'pending' => 'Chờ kiểm soát viên duyệt',
        'draft' => 'Bản nháp (chưa gửi duyệt)',
        'returned' => 'Bị kiểm soát viên trả về chỉnh sửa',
        'rejected' => 'Bị từ chối',
        _ => item.status,
      };
      warnings.add(
        'Chứng từ chưa hoàn tất phê duyệt chính thức (Trạng thái: $statusVi). '
        'Xuất hoá đơn/phiếu lúc này chỉ mang tính tham khảo nội bộ, không có giá trị ghi sổ.',
      );
      recommendations.add(
        'Yêu cầu Kiểm soát viên phê duyệt phiếu trước khi xuất bản cứng/hoá đơn chính thức.',
      );
    }

    // 2. Kiểm tra nội dung & lý do giao dịch
    final detail = item.detail.trim();
    if (detail.isEmpty || detail == '—' || detail.length < 5) {
      warnings.add(
        'Nội dung hoặc lý do giao dịch để trống hoặc quá sơ sài ("$detail"). Thiếu chứng cứ giải trình kiểm toán.',
      );
      recommendations.add(
        'Cập nhật bổ sung nội dung nghiệp vụ chi tiết và hồ sơ chứng từ gốc đính kèm.',
      );
    }

    // 3. Kiểm tra tính hợp lệ của người lập và kiểm soát viên
    if (item.maker.trim().isEmpty) {
      warnings.add('Không xác định được danh tính Giao dịch viên lập phiếu (Maker để trống).');
      recommendations.add('Kiểm tra lại tài khoản người dùng và phiên đăng nhập.');
    }

    // 4. Kiểm tra giá trị / số lượng vượt hạn mức rủi ro
    final impactClean = item.impact.replaceAll('.', '').replaceAll(',', '');
    final matchDigits = RegExp(r'\d+').allMatches(impactClean).map((m) => m.group(0)!).join();
    final numVal = double.tryParse(matchDigits) ?? 0;
    if (numVal >= 500000000) {
      warnings.add(
        'Giá trị giao dịch (${item.impact}) vượt hạn mức kiểm soát 500.000.000 VND. '
        'Bắt buộc xác thực quyền kiểm soát kép (Dual Control 4 mắt) và kiểm đếm trực tiếp.',
      );
      recommendations.add(
        'Kiểm tra lại biên bản kiểm đếm tiền mặt/ấn chỉ trước khi giao khách hàng.',
      );
    }

    // 5. Kết hợp đánh giá rủi ro từ mô hình AI
    if (assessment != null) {
      if (assessment.isHighRisk) {
        warnings.add(
          'Mô hình AI phát hiện mức độ rủi ro cao (${assessment.riskScore}/100): ${assessment.summary}',
        );
      }
      for (final rule in assessment.flaggedRules) {
        if (!warnings.any((w) => w.contains(rule))) {
          warnings.add('Cảnh báo quy chế kiểm soát nội bộ: $rule');
        }
      }
      for (final rec in assessment.recommendations) {
        if (!recommendations.contains(rec)) {
          recommendations.add(rec);
        }
      }
    }

    return VoucherAuditResult(
      hasErrors: warnings.isNotEmpty,
      warnings: warnings,
      recommendations: recommendations,
      assessment: assessment,
    );
  }

  static VoucherAuditResult checkCashRequest(CashRequest request, AiRiskAssessment? assessment) {
    final item = ApprovalItem(
      id: request.id,
      kind: 'Tiền mặt (${request.kind == RequestKind.receipt ? "Thu" : "Chi"})',
      maker: request.createdByName,
      impact: '${request.amount} ${request.currency}',
      detail: request.reason,
      status: request.status.name,
    );
    return checkApprovalItem(item, assessment);
  }

  static VoucherAuditResult checkStockRequest(StockRequest request, AiRiskAssessment? assessment) {
    final totalQty = request.items.fold<double>(
      0,
      (sum, l) => sum + (double.tryParse(l.quantity) ?? 0),
    );
    final item = ApprovalItem(
      id: request.id,
      kind: 'Kho ấn chỉ (${request.kind.name})',
      maker: request.createdByName,
      impact: '${totalQty.toInt()} ấn chỉ',
      detail: request.reason,
      status: request.status.name,
    );
    return checkApprovalItem(item, assessment);
  }
}

/// Hộp thoại Báo cáo kiểm tra sai sót chứng từ bằng AI trước khi in/xuất.
class AiVoucherAuditDialog extends StatelessWidget {
  const AiVoucherAuditDialog({
    super.key,
    required this.item,
    required this.result,
  });

  final ApprovalItem item;
  final VoucherAuditResult result;

  /// Hiển thị hộp thoại cảnh báo sai sót. Trả về `true` nếu người dùng chọn vẫn tiếp tục xuất.
  static Future<bool> show(
    BuildContext context, {
    required ApprovalItem item,
    required VoucherAuditResult result,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AiVoucherAuditDialog(item: item, result: result),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: Color(0xFFDC2626),
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AI Kiểm Tra Chứng Từ & Báo Cáo Sai Sót',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Mô hình: Qwen2.5-1.5B Fine-Tuned (Production) · Phiếu #${item.id.length > 8 ? item.id.substring(0, 8) : item.id}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Summary status banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  border: Border.all(color: const Color(0xFFFECACA)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 18, color: Color(0xFFB91C1C)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Phát hiện ${result.warnings.length} điểm cần lưu ý/sai sót trước khi xuất hoá đơn!',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF991B1B),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Danh sách sai sót phát hiện
              const Text(
                'Chi tiết sai sót & cảnh báo phát hiện:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: result.warnings.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, idx) {
                    final warning = result.warnings[idx];
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(Icons.circle, size: 6, color: Color(0xFFDC2626)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            warning,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

              if (result.recommendations.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text(
                  'Khuyến nghị xử lý của AI:',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                for (final rec in result.recommendations)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.lightbulb_outline, size: 15, color: Color(0xFFD97706)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            rec,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFB45309),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],

              const SizedBox(height: 24),
              // Buttons
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      key: const Key('voucher-audit-cancel-btn'),
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      child: const Text('Xem lại & Hủy in'),
                    ),
                    ElevatedButton.icon(
                      key: const Key('voucher-audit-confirm-btn'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: const Icon(Icons.print_outlined, size: 18),
                      label: const Text('Vẫn in & Đóng dấu Cảnh báo AI'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
