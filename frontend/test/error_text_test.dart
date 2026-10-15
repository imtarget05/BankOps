import 'package:kho_tra_sua/src/core/util/error_text.dart';
import 'package:kho_tra_sua/src/data/repositories/bankops_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('friendlyError — không lộ URL/exception nội bộ', () {
    test('giữ nguyên message có chủ đích của server', () {
      expect(
        friendlyError(ApiException('VALIDATION', 'Số tiền vượt hạn mức quầy')),
        'Số tiền vượt hạn mức quầy',
      );
      expect(
        friendlyError(const FormatException('Cú pháp JSON không hợp lệ')),
        contains('Cú pháp JSON'),
      );
    });

    test('che transport exception (chứa URI nội bộ)', () {
      final transport = Exception(
        'ClientException: Failed to fetch, '
        'uri=https://imtarget05--quan-ly-kho-tra-sua-api.us-east.modal.run/api/v1/inventory/items',
      );
      final msg = friendlyError(transport);
      expect(msg, isNot(contains('modal.run')));
      expect(msg, isNot(contains('ClientException')));
      expect(msg, contains('Không kết nối được máy chủ'));
    });

    test('che null và lỗi lạ', () {
      expect(friendlyError(null), contains('Không kết nối được máy chủ'));
      expect(friendlyError('boom'), contains('Không kết nối được máy chủ'));
    });
  });
}
