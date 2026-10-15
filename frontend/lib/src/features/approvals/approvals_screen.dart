import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_shell.dart';
import '../../core/util/approval_pdf.dart';
import '../../core/util/report_share.dart';
import '../../core/util/role_visibility.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/dtos.dart';
import '../../data/repositories/bankops_repository.dart';
import '../../data/repositories/fake_repository.dart';
import '../ai/ai_voucher_audit.dart';

/// Màn duyệt phiếu điều chỉnh kho cho Quản lý.
class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  Future<List<ApprovalItem>>? _future;
  bool _busy = false;
  final Set<String> _selected = {};
  final Map<String, AiRiskAssessment> _assessments = {};
  StreamSubscription<String>? _approvalSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = RepositoryScope.of(context);
    if (_future == null) {
      _future = repo.getApprovalInbox().then((items) {
        _loadAiAssessments(items, repo);
        return items;
      });
      _approvalSub?.cancel();
      _approvalSub = repo.approvalNotifications.listen((_) {
        if (mounted) _reload();
      });
    }
  }

  @override
  void dispose() {
    _approvalSub?.cancel();
    super.dispose();
  }

  void _loadAiAssessments(List<ApprovalItem> items, BankOpsRepository repo) {
    for (final item in items) {
      if (!_assessments.containsKey(item.id)) {
        repo.assessApprovalItem(item).then((assessment) {
          if (mounted) {
            setState(() {
              _assessments[item.id] = assessment;
            });
          }
        }).catchError((_) {});
      }
    }
  }

  void _reload() {
    final repo = RepositoryScope.of(context);
    setState(() {
      _future = repo.getApprovalInbox().then((items) {
        _loadAiAssessments(items, repo);
        return items;
      });
    });
  }

  bool _isCash(ApprovalItem item) =>
      item.kind.toLowerCase() == 'cash' ||
      item.kind.toLowerCase().contains('quỹ');

  bool _isHighRisk(ApprovalItem item) {
    final assessment = _assessments[item.id];
    if (assessment != null) return assessment.isHighRisk;
    var rawImpact = item.impact;
    final decimalMatch =
        RegExp(r'[\.,]\d{1,2}(?:\s|[a-zA-Z]|$)').firstMatch(rawImpact);
    if (decimalMatch != null) {
      rawImpact = rawImpact.substring(0, decimalMatch.start);
    }
    final digits = rawImpact.replaceAll(RegExp(r'[^\d]'), '');
    final val = int.tryParse(digits) ?? 0;
    if (_isCash(item) && val >= 500000000) return true;
    if (!_isCash(item) && val >= 50) return true;
    return false;
  }

  Future<String?> _showDualControlPinDialog(
    ApprovalItem item,
    AiRiskAssessment? assessment, {
    bool isBatch = false,
    int batchCount = 1,
  }) {
    final repo = RepositoryScope.of(context);
    final isDemoRepository = repo is FakeBankOpsRepository;
    final demoPin =
        repo is FakeBankOpsRepository ? repo.supervisorPin : '123456';
    return showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DualControlPinDialog(
        item: item,
        assessment: assessment,
        isBatch: isBatch,
        batchCount: batchCount,
        isDemoRepository: isDemoRepository,
        demoPin: demoPin,
      ),
    );
  }

  Future<void> _approve(ApprovalItem item) async {
    final repo = RepositoryScope.of(context);
    final assessment = _assessments[item.id];
    final highRisk = _isHighRisk(item);

    String? supervisorPin;
    if (highRisk) {
      supervisorPin = await _showDualControlPinDialog(item, assessment);
      if (supervisorPin == null || !mounted) return;
    }

    setState(() => _busy = true);
    try {
      if (_isCash(item)) {
        await repo.approveCashRequest(item.id, supervisorPin: supervisorPin);
      } else {
        await repo.approveStockRequest(item.id, supervisorPin: supervisorPin);
      }
      if (!mounted) return;
      AppToast.success(context, 'Đã duyệt và ghi sổ phiếu ${item.id}');
      _reload();
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Không thể duyệt: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject(ApprovalItem item) async {
    final repo = RepositoryScope.of(context);
    final reasonCtrl =
        TextEditingController(text: 'Chưa đủ chứng từ đối chiếu');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Từ chối phiếu ${item.id}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nhập lý do để người lập phiếu biết cần bổ sung gì:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('reject-reason-input'),
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Lý do từ chối',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            key: const Key('reject-dialog-confirm-btn'),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Xác nhận từ chối'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final reason = reasonCtrl.text.trim().isEmpty
          ? 'Từ chối khi kiểm duyệt'
          : reasonCtrl.text.trim();
      if (_isCash(item)) {
        await repo.rejectCashRequest(item.id, reason);
      } else {
        await repo.rejectStockRequest(item.id, reason);
      }
      if (!mounted) return;
      AppToast.info(context, 'Đã từ chối phiếu ${item.id}');
      _reload();
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Không thể từ chối: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _returnForRework(ApprovalItem item) async {
    final repo = RepositoryScope.of(context);
    final reasonCtrl = TextEditingController(
        text: 'Cần bổ sung thêm thông tin chứng từ đối chiếu');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.assignment_return_outlined,
                color: Color(0xFFD97706)),
            const SizedBox(width: 8),
            Text('Trả về phiếu ${item.id}'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Phiếu sẽ chuyển về trạng thái [Cần chỉnh sửa]. Maker sẽ nhận được ý kiến để hiệu chỉnh và gửi duyệt lại.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('return-reason-input'),
              controller: reasonCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Ý kiến yêu cầu chỉnh sửa *',
                hintText: 'Nhập nội dung cần Maker bổ sung...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            key: const Key('return-dialog-confirm-btn'),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD97706)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Xác nhận trả về'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final reason = reasonCtrl.text.trim().isEmpty
          ? 'Yêu cầu kiểm tra và chỉnh sửa lại nội dung'
          : reasonCtrl.text.trim();
      if (_isCash(item)) {
        await repo.returnCashRequest(item.id, reason: reason);
      } else {
        await repo.returnStockRequest(item.id, reason: reason);
      }
      if (!mounted) return;
      AppToast.info(context, 'Đã trả về phiếu ${item.id} cho Maker chỉnh sửa');
      _reload();
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Không thể trả về phiếu: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportVoucherWithAiCheck(ApprovalItem item) async {
    final repo = RepositoryScope.of(context);
    AiRiskAssessment? assessment = _assessments[item.id];
    if (assessment == null) {
      try {
        final res = await repo.assessApprovalItem(item);
        assessment = res;
        if (mounted) {
          setState(() => _assessments[item.id] = res);
        }
      } catch (_) {
        // Heuristic fallback
      }
    }

    final audit = AiVoucherAuditor.checkApprovalItem(item, assessment);

    if (audit.hasErrors) {
      if (!mounted) return;
      final proceed = await AiVoucherAuditDialog.show(
        context,
        item: item,
        result: audit,
      );
      if (!proceed) {
        if (mounted) {
          AppToast.info(
              context, 'Đã hủy in để rà soát lại thông tin chứng từ.');
        }
        return;
      }
    } else {
      if (mounted) {
        AppToast.success(context,
            'AI kiểm tra: Chứng từ hợp lệ 100%, không phát hiện sai sót.');
      }
    }

    if (!mounted) return;
    await ReportShare.printPdf(
      context,
      filename: 'phieu-${item.id}.pdf',
      build: () => ApprovalPdf.encode(
        item,
        assessment: assessment,
        auditWarnings: audit.hasErrors ? audit.warnings : null,
      ),
    );
  }

  /// Duyệt hàng loạt: mỗi phiếu duyệt & ghi sổ độc lập, phiếu lỗi không
  /// chặn phiếu khác. Nếu có phiếu rủi ro cao, yêu cầu xác thực PIN một lần cho cả lô.
  Future<void> _approveSelected(List<ApprovalItem> items) async {
    final targets = items.where((i) => _selected.contains(i.id)).toList();
    if (targets.isEmpty) return;

    final hasHighRisk = targets.any(_isHighRisk);
    String? supervisorPin;
    if (hasHighRisk) {
      final highRiskItem = targets.firstWhere(_isHighRisk);
      supervisorPin = await _showDualControlPinDialog(
        highRiskItem,
        _assessments[highRiskItem.id],
        isBatch: true,
        batchCount: targets.length,
      );
      if (supervisorPin == null || !mounted) return;
    } else {
      final confirmed = await showConfirmDialog(
        context,
        title: 'Duyệt hàng loạt ${targets.length} phiếu',
        message:
            'Mỗi phiếu được kiểm tra và ghi sổ riêng. Phiếu xử lý lỗi không ảnh hưởng các phiếu còn lại.',
        confirmLabel: 'Duyệt ${targets.length} phiếu',
      );
      if (!confirmed || !mounted) return;
    }

    final repo = RepositoryScope.of(context);
    setState(() => _busy = true);
    var ok = 0;
    final failed = <String>[];
    for (final item in targets) {
      try {
        if (_isCash(item)) {
          await repo.approveCashRequest(item.id, supervisorPin: supervisorPin);
        } else {
          await repo.approveStockRequest(item.id, supervisorPin: supervisorPin);
        }
        ok++;
      } catch (_) {
        failed.add(item.id);
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _selected.clear();
    });
    if (failed.isEmpty) {
      AppToast.success(
          context, 'Đã duyệt & ghi sổ thành công $ok/${targets.length} phiếu');
    } else {
      AppToast.error(context,
          'Đã duyệt $ok/${targets.length} phiếu; lỗi: ${failed.join(', ')}');
    }
    _reload();
  }

  Color _riskColor(AiRiskAssessment? assessment) {
    if (assessment == null) return const Color(0xFF64748B);
    if (assessment.isHighRisk) return const Color(0xFFDC2626);
    if (assessment.isMediumRisk) return const Color(0xFFD97706);
    return const Color(0xFF059669);
  }

  Widget _buildRiskLevelBadge(AiRiskAssessment? assessment) {
    final color = _riskColor(assessment);
    final label = assessment == null
        ? 'AI ĐANG THẨM ĐỊNH'
        : 'AI RỦI RO ${assessment.riskLevel.toUpperCase()} (${assessment.riskScore}/100)';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            assessment?.isHighRisk == true
                ? Icons.shield_rounded
                : Icons.verified_user_outlined,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAiAssessmentSheet(ApprovalItem item) {
    final assessment = _assessments[item.id];
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.auto_awesome,
                      color: Color(0xFF2563EB), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Đánh giá rủi ro bằng AI',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        'Phiếu: ${item.id} · Người lập: ${item.maker}',
                        style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                      if (assessment != null)
                        Text(
                          assessment.assessmentSource == 'cloudflare'
                              ? 'AI Cloudflare · tư vấn, không quyết định phê duyệt'
                              : 'Thẩm định dự phòng theo quy tắc · AI chưa khả dụng',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (assessment != null) _buildRiskLevelBadge(assessment),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Đóng',
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
            const Divider(height: 28),
            if (assessment == null)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: LoadingView()),
              )
            else
              Expanded(
                child: ListView(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _riskColor(assessment).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color:
                                _riskColor(assessment).withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: _riskColor(assessment),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  '${assessment.riskScore}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900),
                                ),
                                const Text(
                                  'ĐIỂM RỦI RO',
                                  style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              assessment.summary,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF1E293B),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Quy tắc kiểm soát nội bộ cảnh báo:',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    if (assessment.flaggedRules.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF10B981).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.check_circle_outline,
                                color: Color(0xFF059669), size: 18),
                            SizedBox(width: 8),
                            Text('Không vi phạm ngưỡng cảnh báo quy chế.',
                                style: TextStyle(
                                    fontSize: 12.5, color: Color(0xFF059669))),
                          ],
                        ),
                      )
                    else
                      for (final rule in assessment.flaggedRules)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.report_problem_outlined,
                                  color: Color(0xFFDC2626), size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(rule,
                                      style: const TextStyle(fontSize: 12.5))),
                            ],
                          ),
                        ),
                    const SizedBox(height: 16),
                    const Text(
                      'Kiến nghị hành động cho Kiểm soát viên:',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    for (final rec in assessment.recommendations)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.lightbulb_outline,
                                color: Color(0xFFD97706), size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(rec,
                                    style: const TextStyle(fontSize: 12.5))),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    const Text(
                      'Dấu kiểm toán số (Audit Stamp SHA-256):',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        assessment.auditStamp,
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ApprovalItem>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: LoadingView());
        }
        if (snapshot.hasError) {
          return Center(
            child: ErrorView(
              message: '${snapshot.error}',
              onRetry: _reload,
            ),
          );
        }
        final items = snapshot.data!;
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final user = SessionScope.maybeOf(context)?.user;
        final roles = RoleVisibility.rolesOf(user);
        final canApprove = RoleVisibility.canApprove(roles);

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hộp Thư Phê Duyệt Kiểm Soát Kép (Maker–Checker)',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Kiểm soát viên độc lập thẩm định chứng từ và quyết định phê duyệt ghi sổ',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color:
                              const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.shield_outlined,
                            size: 16, color: Color(0xFFD97706)),
                        const SizedBox(width: 6),
                        Text(
                          '${items.length} YÊU CẦU CHỜ DUYỆT',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFD97706),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Principle Banner
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E3A8A).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xFF1E3A8A).withValues(alpha: 0.2)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 20, color: Color(0xFF1E3A8A)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Người lập phiếu không được tự duyệt. Mọi quyết định đều được lưu vào nhật ký kiểm toán.',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E3A8A),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              if (!canApprove) ...[
                Container(
                  key: const Key('approvals-readonly-banner'),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.remove_red_eye_outlined,
                          size: 20, color: Color(0xFFB45309)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Chế độ chỉ xem theo dõi tiến độ',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFB45309),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Bạn đang theo dõi hàng đợi duyệt. Chỉ nhân viên được phân quyền thẩm định (Kiểm soát viên, Quản trị viên) mới có quyền Phê duyệt, Từ chối hoặc Trả về chứng từ.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              if (items.isNotEmpty && canApprove) ...[
                _SelectionBar(
                  allIds: [for (final i in items) i.id],
                  selected: _selected,
                  busy: _busy,
                  onToggleAll: (selectAll) {
                    setState(() {
                      _selected.clear();
                      if (selectAll) {
                        _selected.addAll([for (final i in items) i.id]);
                      }
                    });
                  },
                  onApproveSelected: () => _approveSelected(items),
                ),
                const SizedBox(height: 16),
              ],

              if (items.isEmpty)
                Container(
                  padding: const EdgeInsets.all(48),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.5),
                    ),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF10B981).withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_circle_rounded,
                            size: 40,
                            color: Color(0xFF10B981),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Hộp thư phê duyệt hoàn toàn trống',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tất cả các phiếu xuất/nhập kho và nạp/rút quỹ đã được kiểm soát xử lý xong.',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                for (final item in items)
                  Builder(
                    builder: (context) {
                      final isCash = _isCash(item);
                      final accentColor = isCash
                          ? const Color(0xFF059669)
                          : const Color(0xFF2563EB);

                      return Container(
                        key: Key('approval-card-${item.id}'),
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color:
                              isDark ? const Color(0xFF1E293B) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant
                                .withValues(alpha: 0.5),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black
                                  .withValues(alpha: isDark ? 0.2 : 0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(color: accentColor, width: 4),
                              ),
                            ),
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color:
                                            accentColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            isCash
                                                ? Icons.savings_outlined
                                                : Icons.inventory_2_outlined,
                                            size: 14,
                                            color: accentColor,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            isCash
                                                ? 'ĐIỀU CHỈNH KHO'
                                                : 'KHO NGUYÊN LIỆU',
                                            style: TextStyle(
                                              color: accentColor,
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Mã phiếu: ${item.id}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF59E0B)
                                            .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'CHỜ CHECKER DUYỆT',
                                        style: TextStyle(
                                          color: Color(0xFFB45309),
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (canApprove) ...[
                                      Checkbox(
                                        key: Key('approval-select-${item.id}'),
                                        value: _selected.contains(item.id),
                                        onChanged: _busy
                                            ? null
                                            : (v) => setState(() {
                                                  if (v == true) {
                                                    _selected.add(item.id);
                                                  } else {
                                                    _selected.remove(item.id);
                                                  }
                                                }),
                                      ),
                                    ],
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text.rich(
                                            TextSpan(
                                              children: [
                                                WidgetSpan(
                                                  alignment:
                                                      PlaceholderAlignment
                                                          .middle,
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            right: 6),
                                                    child: Icon(
                                                      Icons.person_outline,
                                                      size: 16,
                                                      color: theme.colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                                  ),
                                                ),
                                                TextSpan(
                                                  text: 'Người lập phiếu: ',
                                                  style: TextStyle(
                                                    fontSize: 12.5,
                                                    color: theme.colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                ),
                                                TextSpan(
                                                  text: item.maker,
                                                  style: const TextStyle(
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 6),
                                          Text.rich(
                                            TextSpan(
                                              children: [
                                                WidgetSpan(
                                                  alignment:
                                                      PlaceholderAlignment
                                                          .middle,
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            right: 6),
                                                    child: Icon(
                                                      Icons.trending_up_rounded,
                                                      size: 16,
                                                      color: accentColor,
                                                    ),
                                                  ),
                                                ),
                                                TextSpan(
                                                  text: 'Tác động số dư: ',
                                                  style: TextStyle(
                                                    fontSize: 12.5,
                                                    color: theme.colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                ),
                                                TextSpan(
                                                  text: item.impact,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w900,
                                                    color: accentColor,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (item.detail.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              'Chi tiết: ${item.detail}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: theme.colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 10),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 6,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              _buildRiskLevelBadge(
                                                  _assessments[item.id]),
                                              InkWell(
                                                key: Key(
                                                    'btn-ai-assess-${item.id}'),
                                                onTap: () =>
                                                    _showAiAssessmentSheet(
                                                        item),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                child: Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8,
                                                      vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        const Color(0xFF2563EB)
                                                            .withValues(
                                                                alpha: 0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6),
                                                    border: Border.all(
                                                      color: const Color(
                                                              0xFF2563EB)
                                                          .withValues(
                                                              alpha: 0.25),
                                                    ),
                                                  ),
                                                  child: const Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.auto_awesome,
                                                          size: 12,
                                                          color: Color(
                                                              0xFF2563EB)),
                                                      SizedBox(width: 4),
                                                      Text(
                                                        'Xem đánh giá AI',
                                                        style: TextStyle(
                                                          fontSize: 10.5,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color:
                                                              Color(0xFF2563EB),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    Wrap(
                                      spacing: 8,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        IconButton(
                                          key: Key('print-approval-${item.id}'),
                                          onPressed: () =>
                                              _exportVoucherWithAiCheck(item),
                                          icon: const Icon(Icons.print_outlined,
                                              size: 20),
                                          tooltip:
                                              'In phiếu ${item.id} (AI Kiểm Duyệt)',
                                        ),
                                        if (canApprove) ...[
                                          OutlinedButton.icon(
                                            key: Key('btn-return-${item.id}'),
                                            onPressed: _busy
                                                ? null
                                                : () => _returnForRework(item),
                                            icon: const Icon(
                                                Icons
                                                    .assignment_return_outlined,
                                                size: 16,
                                                color: Color(0xFFD97706)),
                                            label: const Text(
                                              'Trả về',
                                              style: TextStyle(
                                                  color: Color(0xFFD97706),
                                                  fontWeight: FontWeight.w700),
                                            ),
                                            style: OutlinedButton.styleFrom(
                                              side: const BorderSide(
                                                  color: Color(0xFFFDE68A)),
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          10)),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 14,
                                                      vertical: 10),
                                            ),
                                          ),
                                          OutlinedButton.icon(
                                            key: Key('btn-reject-${item.id}'),
                                            onPressed: _busy
                                                ? null
                                                : () => _reject(item),
                                            icon: const Icon(
                                                Icons.close_rounded,
                                                size: 16,
                                                color: Color(0xFFDC2626)),
                                            label: const Text(
                                              'Từ chối',
                                              style: TextStyle(
                                                  color: Color(0xFFDC2626),
                                                  fontWeight: FontWeight.w700),
                                            ),
                                            style: OutlinedButton.styleFrom(
                                              side: const BorderSide(
                                                  color: Color(0xFFFCA5A5)),
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          10)),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 14,
                                                      vertical: 10),
                                            ),
                                          ),
                                          FilledButton.icon(
                                            key: Key('btn-approve-${item.id}'),
                                            onPressed: _busy
                                                ? null
                                                : () => _approve(item),
                                            icon: const Icon(
                                                Icons.verified_rounded,
                                                size: 16),
                                            label: const Text(
                                              'Phê duyệt & Ghi sổ',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.w700),
                                            ),
                                            style: FilledButton.styleFrom(
                                              backgroundColor:
                                                  const Color(0xFF059669),
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          10)),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 10),
                                            ),
                                          ),
                                        ] else ...[
                                          Container(
                                            key: Key(
                                                'approval-readonly-tag-${item.id}'),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: theme.colorScheme
                                                  .surfaceContainerHighest
                                                  .withValues(alpha: 0.6),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: theme
                                                    .colorScheme.outlineVariant
                                                    .withValues(alpha: 0.5),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.lock_clock_outlined,
                                                  size: 15,
                                                  color: theme.colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'Chờ kiểm soát viên duyệt (Chỉ xem)',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: theme.colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
            ],
          ),
        );
      },
    );
  }
}

/// Thanh chọn + duyệt hàng loạt phía trên danh sách phiếu chờ.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.allIds,
    required this.selected,
    required this.busy,
    required this.onToggleAll,
    required this.onApproveSelected,
  });

  final List<String> allIds;
  final Set<String> selected;
  final bool busy;
  final ValueChanged<bool> onToggleAll;
  final VoidCallback onApproveSelected;

  @override
  Widget build(BuildContext context) {
    final allSelected = selected.isNotEmpty && selected.length == allIds.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Checkbox(
            key: const Key('approval-select-all'),
            tristate: true,
            value: selected.isEmpty ? false : (allSelected ? true : null),
            onChanged: busy ? null : (v) => onToggleAll(v == true),
          ),
          Text(
            selected.isEmpty
                ? 'Chọn để duyệt hàng loạt'
                : 'Đã chọn ${selected.length}/${allIds.length}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const Spacer(),
          if (selected.isNotEmpty)
            FilledButton.icon(
              key: const Key('approve-selected-btn'),
              onPressed: busy ? null : onApproveSelected,
              icon: const Icon(Icons.verified_rounded, size: 16),
              label: Text('Duyệt ${selected.length} phiếu'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
        ],
      ),
    );
  }
}

class _DualControlPinDialog extends StatefulWidget {
  const _DualControlPinDialog({
    required this.item,
    required this.assessment,
    required this.isBatch,
    required this.batchCount,
    required this.isDemoRepository,
    this.demoPin = '123456',
  });

  final ApprovalItem item;
  final AiRiskAssessment? assessment;
  final bool isBatch;
  final int batchCount;
  final bool isDemoRepository;
  final String demoPin;

  @override
  State<_DualControlPinDialog> createState() => _DualControlPinDialogState();
}

class _DualControlPinDialogState extends State<_DualControlPinDialog> {
  late final TextEditingController _pinCtrl;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _pinCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  void _onConfirm() {
    if (widget.isDemoRepository && _pinCtrl.text.trim() == widget.demoPin) {
      Navigator.of(context).pop(_pinCtrl.text.trim());
    } else if (widget.isDemoRepository) {
      setState(() {
        _errorText = 'Mã PIN không đúng (Demo: ${widget.demoPin})';
      });
    } else if (_pinCtrl.text.trim().isNotEmpty) {
      Navigator.of(context).pop(_pinCtrl.text.trim());
    } else {
      setState(() {
        _errorText = 'Vui lòng nhập PIN Kiểm soát viên.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFDC2626).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.security_rounded,
                color: Color(0xFFDC2626), size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.isBatch
                  ? 'Xác Thực Kiểm Soát Kép Lô ${widget.batchCount} Phiếu'
                  : 'Xác Thực Quyền Kiểm Soát Kép (Supervisor Authorization)',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Color(0xFFDC2626), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.isBatch
                          ? 'Lô duyệt có phiếu giá trị lớn hoặc rủi ro cao. Bắt buộc Kiểm soát viên nhập PIN để cấp phép.'
                          : 'Phiếu ${widget.item.id} có rủi ro cao (${widget.item.impact}). Kiểm tra chứng từ và nhập PIN kiểm soát viên trước khi duyệt.',
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF991B1B),
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (widget.assessment != null) ...[
              Text(
                'Mã kiểm tra đánh giá:',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  widget.assessment!.auditStamp,
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 14),
            ],
            Text(
              widget.isDemoRepository
                  ? 'Nhập PIN demo Kiểm soát viên (${widget.demoPin}):'
                  : 'Nhập PIN Kiểm soát viên được cấu hình bảo mật:',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('supervisor-pin-input'),
              controller: _pinCtrl,
              keyboardType: TextInputType.number,
              obscureText: true,
              decoration: InputDecoration(
                hintText: 'Nhập 6 số PIN',
                border: const OutlineInputBorder(),
                errorText: _errorText,
                prefixIcon: const Icon(Icons.pin_outlined),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Huỷ bỏ'),
        ),
        FilledButton(
          key: const Key('confirm-supervisor-pin-btn'),
          style:
              FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
          onPressed: _onConfirm,
          child: const Text('Ký Số & Phê Duyệt'),
        ),
      ],
    );
  }
}
