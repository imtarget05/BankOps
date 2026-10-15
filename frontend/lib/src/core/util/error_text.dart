import '../../data/repositories/bankops_repository.dart';

/// Chuyển một lỗi bất kỳ thành câu hiển thị an toàn cho người dùng.
///
/// Quy tắc: chỉ tin cậy thông điệp do server trả về có chủ đích
/// ([ApiException], [FormatException]). Mọi lỗi khác (transport/socket/
/// unexpected) **không bao giờ** được lộ nguyên văn — chúng thường chứa URL
/// nội bộ, ví dụ `ClientException: Failed to fetch,
/// uri=https://…modal.run/api/v1/…`.
String friendlyError(Object? error) {
  if (error is ApiException) return error.message;
  if (error is FormatException) return error.message;
  return 'Không kết nối được máy chủ. Vui lòng kiểm tra kết nối mạng và thử lại.';
}
