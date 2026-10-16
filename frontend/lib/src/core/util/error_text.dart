import '../../data/repositories/bankops_repository.dart';

/// Chuyển một lỗi bất kỳ thành câu hiển thị an toàn cho người dùng.
///
/// Quy tắc: chỉ tin cậy thông điệp do server trả về có chủ đích
/// ([ApiException], [FormatException]). Mọi lỗi khác (transport/socket/
/// unexpected) **không bao giờ** được lộ nguyên văn — chúng thường chứa URL
/// nội bộ, ví dụ `ClientException: Failed to fetch,
/// uri=https://…modal.run/api/v1/…`.
///
/// Khi server trả message generic (VD sau khi proxy trung gian viết đè),
/// ánh xạ theo code để user vẫn thấy tiếng Việt thân thiện như mọi
/// notification khác trong hệ thống.
String friendlyError(Object? error) {
  if (error is ApiException) return _friendlyApiMessage(error);
  if (error is FormatException) return error.message;
  return 'Không kết nối được máy chủ. Vui lòng kiểm tra kết nối mạng và thử lại.';
}

String _friendlyApiMessage(ApiException error) {
  switch (error.code) {
    case 'VALIDATION_ERROR':
      return 'Dữ liệu gửi lên chưa hợp lệ. Vui lòng kiểm tra lại các trường bắt buộc.';
    case 'INTERNAL_ERROR':
    case 'HTTP_500':
      return 'Máy chủ đang gặp sự cố. Vui lòng thử lại sau ít phút.';
    case 'DEPENDENCY_UNAVAILABLE':
    case 'AI_UNAVAILABLE':
      return 'Dịch vụ tạm thời gián đoạn. Vui lòng thử lại sau.';
    case 'RATE_LIMITED':
      return 'Bạn thao tác quá nhanh. Vui lòng đợi một lát rồi thử lại.';
    case 'UNAUTHENTICATED':
      return 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.';
    case 'HTTP_502':
    case 'HTTP_503':
    case 'HTTP_504':
      return 'Máy chủ đang phản hồi chậm. Vui lòng thử lại sau ít phút.';
    default:
      return error.message;
  }
}
