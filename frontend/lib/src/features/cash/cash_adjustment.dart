import '../../core/util/error_text.dart';
import '../../data/models/dtos.dart';
import '../../data/repositories/bankops_repository.dart';

/// Mã lỗi backend trả về khi client cố ghi số dư quỹ TRỰC TIẾP vào API két
/// (`PUT /cash-sim/boxes/{id}`) — xem `backend/app/api/routes/cash_sim.py`
/// (`_reject_direct_balance_write`).
const String kDirectBalanceWriteForbidden = 'DIRECT_BALANCE_WRITE_FORBIDDEN';

/// Thông điệp tiếng Việt cho lỗi 422 `DIRECT_BALANCE_WRITE_FORBIDDEN`.
const String kDirectBalanceWriteMessage =
    'Số dư quỹ chỉ được đổi qua phiếu điều chỉnh (journal) có kiểm soát và '
    'phải được duyệt. Hệ thống đã từ chối thao tác ghi số dư trực tiếp — '
    'vui lòng tạo phiếu điều chỉnh thay vì sửa số dư.';

/// Thông điệp tiếng Việt khi user thiếu capability `cash:post_adjustment`.
const String kNoAdjustmentPermissionMessage =
    'Bạn không có quyền tạo phiếu điều chỉnh tài chính '
    '(cash:post_adjustment). Vui lòng liên hệ quản trị viên để được cấp quyền.';

/// Lỗi backend là user thiếu quyền (403).
bool isPermissionDenied(Object? error) =>
    error is ApiException &&
    (error.code == 'FORBIDDEN' ||
        error.code == 'HTTP_403' ||
        error.code == 'SELF_APPROVAL_FORBIDDEN');

/// Lỗi backend khi client gửi field số dư trực tiếp (422).
bool isDirectBalanceWriteForbidden(Object? error) =>
    error is ApiException && error.code == kDirectBalanceWriteForbidden;

/// Phiếu quỹ này là phiếu điều chỉnh số dư (theo kind hoặc theo tiền tố lý do).
bool isCashAdjustmentRequest(CashRequest request) =>
    request.kind == RequestKind.adjustment ||
    request.reason.startsWith(kCashAdjustmentReasonPrefix);

/// Message tiếng Việt an toàn cho lỗi của luồng điều chỉnh số dư quỹ.
///
/// - 422 `DIRECT_BALANCE_WRITE_FORBIDDEN` → giải thích số dư phải qua phiếu.
/// - 403 → báo rõ thiếu quyền `cash:post_adjustment`.
/// - còn lại → `friendlyError` (không lộ lỗi kỹ thuật).
String cashAdjustmentErrorMessage(Object? error) {
  if (isDirectBalanceWriteForbidden(error)) return kDirectBalanceWriteMessage;
  if (isPermissionDenied(error)) return kNoAdjustmentPermissionMessage;
  return friendlyError(error);
}

/// Tạo + gửi duyệt phiếu điều chỉnh số dư quỹ (draft → submitted).
///
/// Số dư KHÔNG đổi ngay: phiếu phải được người khác duyệt thì backend mới
/// post journal (bút toán) và cập nhật số dư. Đây là nghiệp vụ có kiểm soát,
/// phân quyền và audit — thay cho ghi số dư trực tiếp.
///
/// [reason] là lý do người dùng nhập; hệ thống tự thêm tiền tố nhận diện
/// phiếu điều chỉnh để phục vụ đối soát/audit.
Future<CashRequest> submitCashAdjustment({
  required BankOpsRepository repo,
  required String cashboxId,
  required String amount,
  required bool increase,
  required String reason,
}) async {
  final created = await repo.createCashAdjustmentRequest(
    cashboxId: cashboxId,
    amount: amount,
    increase: increase,
    reason: buildCashAdjustmentReason(reason, increase: increase),
  );
  if (created.status != RequestStatus.draft) return created;
  return repo.submitCashRequest(created.id);
}

/// Lý do phiếu điều chỉnh (có tiền tố nhận diện + hướng điều chỉnh).
String buildCashAdjustmentReason(String userReason, {required bool increase}) {
  final dir = increase ? 'tăng' : 'giảm';
  final clean = userReason.trim();
  final head = '$kCashAdjustmentReasonPrefix ($dir)';
  return clean.isEmpty ? head : '$head — $clean';
}

/// Parse số tiền VND từ ô nhập (chấp nhận "1.500.000", "1,500,000", "1500000 ₫").
double? parseVndAmount(String? raw) {
  if (raw == null) return null;
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  return double.tryParse(digits);
}
