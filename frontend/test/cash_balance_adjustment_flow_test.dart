import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kho_tra_sua/src/app/app_shell.dart';
import 'package:kho_tra_sua/src/core/theme/app_theme.dart';
import 'package:kho_tra_sua/src/core/util/role_visibility.dart';
import 'package:kho_tra_sua/src/data/models/dtos.dart';
import 'package:kho_tra_sua/src/data/repositories/bankops_repository.dart';
import 'package:kho_tra_sua/src/data/repositories/fake_repository.dart';
import 'package:kho_tra_sua/src/data/repositories/http_bankops_repository.dart';
import 'package:kho_tra_sua/src/features/cash/cash_adjustment.dart';
import 'package:kho_tra_sua/src/features/cash/cash_screen.dart';
import 'package:kho_tra_sua/src/features/dashboard/dashboard_screen.dart';

/// Repository demo ném lỗi khi tạo phiếu điều chỉnh — dùng để kiểm tra
/// UI xử lý lỗi có cấu trúc từ backend (422 / 403).
class _ThrowingAdjustmentRepository extends FakeBankOpsRepository {
  _ThrowingAdjustmentRepository(this.error) : super(latency: Duration.zero);

  final Object error;

  @override
  Future<CashRequest> createCashAdjustmentRequest({
    required String cashboxId,
    required String amount,
    required bool increase,
    String? reason,
  }) async {
    throw error;
  }
}

http.Response _jsonResp(Map<String, dynamic> body, [int status = 200]) =>
    http.Response.bytes(
      utf8.encode(json.encode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

const AppUser _adminUser = AppUser(
  id: 'u-admin',
  username: 'tanmainguyen',
  email: 'tanmainguyenbinhtan@gmail.com',
  displayName: 'Admin Quản Trị',
  roles: ['admin'],
  capabilities: ['cash:post_adjustment', 'cash:create_request'],
);

void main() {
  group('Repository — không bao giờ ghi số dư trực tiếp', () {
    test(
        'updateCashbox KHÔNG gửi field số dư (balance/amount/opening_balance)',
        () async {
      Map<String, dynamic>? putBody;
      final mockClient = MockClient((request) async {
        if (request.method == 'PUT' &&
            request.url.path == '/api/v1/cash-sim/boxes/cb-1') {
          putBody = json.decode(request.body) as Map<String, dynamic>;
          return _jsonResp({
            'id': 'cb-1',
            'code': 'POS-01',
            'name': 'Két A',
            'balance': '4250000.00',
          });
        }
        return _jsonResp({}, 404);
      });

      final repo = HttpBankOpsRepository(
        baseUrl: 'http://localhost:8000',
        client: mockClient,
        tokenProvider: () async => 'test-jwt-token',
      );

      await repo.updateCashbox(id: 'cb-1', name: 'Két A');

      expect(putBody, isNotNull, reason: 'PUT /cash-sim/boxes/{id} phải được gọi');
      expect(putBody!.containsKey('balance'), isFalse,
          reason: 'backend trả 422 DIRECT_BALANCE_WRITE_FORBIDDEN nếu gửi balance');
      expect(putBody!.containsKey('amount'), isFalse);
      expect(putBody!.containsKey('opening_balance'), isFalse);
      expect(putBody!['name'], 'Két A');
      repo.dispose();
    });

    test('Mã nguồn repository không còn gửi key `balance` xuống API két', () {
      final src = File('lib/src/data/repositories/http_bankops_repository.dart')
          .readAsStringSync();
      expect(
        src.contains("'balance':"),
        isFalse,
        reason: 'Không được gửi field số dư (balance) trong body của API két — '
            'số dư chỉ đổi qua phiếu điều chỉnh (journal).',
      );
    });

    test('Fake repository cũng không cho ghi số dư qua updateCashbox', () async {
      final repo = FakeBankOpsRepository(latency: Duration.zero);
      final before = (await repo.getCashBalances())
          .firstWhere((b) => b.cashboxId == '11111111-1111-4111-8111-111111111111')
          .amount;

      final box = (await repo.getCashboxes()).first;
      await repo.updateCashbox(id: box.id, name: 'Tên mới');

      final after = (await repo.getCashBalances())
          .firstWhere((b) => b.cashboxId == box.id)
          .amount;
      expect(after, before,
          reason: 'updateCashbox chỉ sửa metadata, không đụng số dư');
    });

    test('Số dư chỉ đổi khi phiếu điều chỉnh được DUYỆT (journal)', () async {
      final repo = FakeBankOpsRepository(latency: Duration.zero);
      final box = (await repo.getCashboxes()).first;
      final before = double.parse(
          (await repo.getCashBalances()).firstWhere((b) => b.cashboxId == box.id).amount);

      final created = await repo.createCashAdjustmentRequest(
        cashboxId: box.id,
        amount: '500000.00',
        increase: false,
        reason: 'Điều chỉnh số dư quỹ (giảm) — kiểm đếm lệch',
      );
      await repo.submitCashRequest(created.id);

      final mid = double.parse(
          (await repo.getCashBalances()).firstWhere((b) => b.cashboxId == box.id).amount);
      expect(mid, before,
          reason: 'phiếu mới tạo/send duyệt thì số dư KHÔNG đổi');

      await repo.approveCashRequest(created.id);
      final after = double.parse(
          (await repo.getCashBalances()).firstWhere((b) => b.cashboxId == box.id).amount);
      expect(after, before - 500000,
          reason: 'duyệt phiếu điều chỉnh (giảm quỹ) thì mới post journal');

      // Bút toán phải xuất hiện trong sổ nhật ký quỹ (audit).
      final journals = await repo.getJournals();
      expect(journals.any((j) => j.cashboxId == box.id), isTrue);
    });
  });

  group('Luồng phiếu điều chỉnh (journal có kiểm soát)', () {
    test('Giảm quỹ -> POST /cash-sim/requests với kind=adjustment rồi submit',
        () async {
      final bodies = <Map<String, dynamic>>[];
      final paths = <String>[];

      final mockClient = MockClient((request) async {
        paths.add('${request.method} ${request.url.path}');
        if (request.url.path == '/api/v1/cash-sim/requests' &&
            request.method == 'POST') {
          final body = json.decode(request.body) as Map<String, dynamic>;
          bodies.add(body);
          expect(request.headers['Idempotency-Key'], isNotEmpty);
          return _jsonResp({
            'id': 'cr-adj-1',
            'kind': 'adjustment',
            'status': 'draft',
            'version': 1,
            'maker_id': 'u-maker',
            'cashbox_id': 'cb-1',
            'amount': '500000.00',
            'currency': 'VND',
            'reason': 'Kiểm đếm lệch',
          }, 201);
        }
        if (request.url.path == '/api/v1/cash-sim/requests/cr-adj-1/submit') {
          return _jsonResp({
            'id': 'cr-adj-1',
            'kind': 'adjustment',
            'status': 'submitted',
            'version': 2,
            'maker_id': 'u-maker',
            'cashbox_id': 'cb-1',
            'amount': '500000.00',
            'currency': 'VND',
            'reason': 'Kiểm đếm lệch',
          });
        }
        return _jsonResp({}, 404);
      });

      final repo = HttpBankOpsRepository(
        baseUrl: 'http://localhost:8000',
        client: mockClient,
        tokenProvider: () async => 'test-jwt-token',
      );

      final created = await submitCashAdjustment(
        repo: repo,
        cashboxId: 'cb-1',
        amount: '500000.00',
        increase: false,
        reason: 'Kiểm đếm lệch',
      );

      expect(bodies, hasLength(1));
      expect(bodies.single['kind'], 'adjustment',
          reason: 'phiếu điều chỉnh phải dùng kind=adjustment');
      expect(bodies.single['cashbox_id'], 'cb-1');
      expect(bodies.single['amount'], '500000.00');
      expect(bodies.single.containsKey('balance'), isFalse);
      expect(created.id, 'cr-adj-1');
      expect(created.status, RequestStatus.pending,
          reason: 'phiếu phải ở trạng thái chờ duyệt sau khi submit');
      expect(paths, contains('POST /api/v1/cash-sim/requests'));
      expect(paths, contains('POST /api/v1/cash-sim/requests/cr-adj-1/submit'));
      repo.dispose();
    });

    test('Tăng quỹ -> dùng kind=receipt (backend chỉ có receipt cho dòng vào quỹ)',
        () async {
      Map<String, dynamic>? posted;
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/cash-sim/requests' &&
            request.method == 'POST') {
          posted = json.decode(request.body) as Map<String, dynamic>;
          return _jsonResp({
            'id': 'cr-adj-2',
            'kind': 'receipt',
            'status': 'draft',
            'version': 1,
            'maker_id': 'u-maker',
            'cashbox_id': 'cb-1',
            'amount': '250000.00',
            'currency': 'VND',
            'reason': 'Điều chỉnh số dư quỹ (tăng) — kiểm đếm dư',
          }, 201);
        }
        if (request.url.path == '/api/v1/cash-sim/requests/cr-adj-2/submit') {
          return _jsonResp({
            'id': 'cr-adj-2',
            'kind': 'receipt',
            'status': 'submitted',
            'version': 2,
            'maker_id': 'u-maker',
            'cashbox_id': 'cb-1',
            'amount': '250000.00',
            'currency': 'VND',
          });
        }
        return _jsonResp({}, 404);
      });

      final repo = HttpBankOpsRepository(
        baseUrl: 'http://localhost:8000',
        client: mockClient,
        tokenProvider: () async => 'test-jwt-token',
      );

      await submitCashAdjustment(
        repo: repo,
        cashboxId: 'cb-1',
        amount: '250000.00',
        increase: true,
        reason: 'kiểm đếm dư',
      );

      expect(posted, isNotNull);
      expect(posted!['kind'], 'receipt',
          reason: 'backend coi `adjustment` là bút toán RA quỹ; dòng tiền VÀO '
              'quỹ chỉ có `receipt` — xem backend/app/api/routes/cash_sim.py');
      expect(posted!['reason'], contains(kCashAdjustmentReasonPrefix));
      repo.dispose();
    });
  });

  group('Phân quyền UI theo capability cash:post_adjustment', () {
    test('Đọc capability từ auth store (không chế quyền mới)', () {
      expect(
        RoleVisibility.canPostCashAdjustment(const AppUser(
          id: 'u-1',
          username: 'op',
          displayName: 'Cash Operator',
          roles: ['cash_sim_operator'],
          capabilities: ['cash:post_adjustment'],
        )),
        isTrue,
      );
      expect(
        RoleVisibility.canPostCashAdjustment(const AppUser(
          id: 'u-2',
          username: 'staff',
          displayName: 'Nhân viên',
          roles: ['staff'],
          capabilities: ['cash:create_request', 'cash:view_balances'],
        )),
        isFalse,
        reason: 'nhân viên không có cash:post_adjustment thì không được điều chỉnh',
      );
      expect(
        RoleVisibility.canPostCashAdjustment(const AppUser(
          id: 'u-3',
          username: 'offline',
          displayName: 'Offline',
          roles: ['admin'],
        )),
        isTrue,
        reason: 'chưa có danh sách capability (offline/test) -> fallback vai trò',
      );
      expect(
        RoleVisibility.canPostCashAdjustment(const AppUser(
          id: 'u-4',
          username: 'offline-staff',
          displayName: 'Offline staff',
          roles: ['staff'],
        )),
        isFalse,
      );
    });
  });

  group('UI — xử lý lỗi có cấu trúc từ backend', () {
    Future<void> pumpDashboard(
      WidgetTester tester,
      BankOpsRepository repo,
    ) async {
      tester.view.physicalSize = const Size(1400, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        RepositoryScope(
          repository: repo,
          child: SessionScope(
            user: _adminUser,
            child: MaterialApp(
              theme: AppTheme.light(),
              home: Scaffold(
                body: DashboardScreen(
                  onNavigate: (index,
                      {category,
                      stockFilter,
                      viewMode,
                      locationId,
                      autoOpenCash = false,
                      autoOpenStock = false}) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> submitCountedAmount(
      WidgetTester tester, {
      required String amount,
    }) async {
      await tester.tap(find.text('Kiểm tra & Tùy chỉnh').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, amount);
      await tester.tap(find.text('Lưu & Cập nhật'));
      await tester.pumpAndSettle();
    }

    testWidgets(
        '422 DIRECT_BALANCE_WRITE_FORBIDDEN -> hiện message tiếng Việt, không crash',
        (tester) async {
      await pumpDashboard(
        tester,
        _ThrowingAdjustmentRepository(ApiException(
          'DIRECT_BALANCE_WRITE_FORBIDDEN',
          'Số dư quỹ chỉ đổi qua phiếu (journal), không ghi trực tiếp từ API két.',
        )),
      );

      await submitCountedAmount(tester, amount: '2500000');

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Số dư quỹ chỉ được đổi qua phiếu điều chỉnh'),
          findsOneWidget);
      expect(find.textContaining('ghi số dư trực tiếp'), findsOneWidget);
    });

    testWidgets('403 -> báo rõ thiếu quyền cash:post_adjustment', (tester) async {
      await pumpDashboard(
        tester,
        _ThrowingAdjustmentRepository(ApiException(
          'FORBIDDEN',
          'Bạn không có quyền tạo bút toán điều chỉnh tài chính '
          '(cash:post_adjustment).',
        )),
      );

      await submitCountedAmount(tester, amount: '2500000');

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining(
            'Bạn không có quyền tạo phiếu điều chỉnh tài chính'),
        findsOneWidget,
      );
    });
  });

  group('CashScreen — tạo phiếu điều chỉnh thay vì ghi số dư', () {
    testWidgets('Bấm "Điều chỉnh số dư" tạo phiếu và báo đang chờ duyệt',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final repo = FakeBankOpsRepository(latency: Duration.zero);

      await tester.pumpWidget(
        RepositoryScope(
          repository: repo,
          child: SessionScope(
            user: _adminUser,
            child: MaterialApp(
              theme: AppTheme.light(),
              home: const Scaffold(body: CashScreen()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final adjustBtn = find.byKey(const Key('btn-admin-adjust-cashbox'));
      expect(adjustBtn, findsOneWidget);
      await tester.ensureVisible(adjustBtn);
      await tester.tap(adjustBtn);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cash-adjustment-amount')), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('cash-adjustment-amount')), '500000');
      await tester.tap(find.byKey(const Key('cash-adjustment-submit')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Đã tạo phiếu điều chỉnh'), findsOneWidget);
      expect(find.textContaining('đang chờ duyệt'), findsWidgets);

      // Phiếu điều chỉnh nằm trong danh sách phiếu quỹ của repo (draft -> chờ duyệt).
      final requests = await repo.getCashRequests();
      expect(
        requests.any((r) => r.kind == RequestKind.adjustment ||
            r.reason.startsWith(kCashAdjustmentReasonPrefix)),
        isTrue,
        reason: 'phải tạo phiếu điều chỉnh thay vì ghi số dư trực tiếp',
      );
    });
  });

  group('Contract frontend <-> backend (đọc file backend thật)', () {
    test('Backend vẫn chặn ghi số dư trực tiếp và hỗ trợ kind=adjustment',
        () {
      const path = '../backend/app/api/routes/cash_sim.py';
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: 'không tìm thấy file backend: $path');
      final src = file.readAsStringSync();

      expect(src.contains('_DIRECT_BALANCE_FIELDS'), isTrue);
      expect(src.contains('"balance"'), isTrue,
          reason: 'backend phải chặn field balance');
      expect(src.contains('DIRECT_BALANCE_WRITE_FORBIDDEN'), isTrue);
      expect(src.contains('_ADJUSTMENT_KINDS = ("adjustment",)'), isTrue);
      expect(src.contains('_ADJUSTMENT_CAPS = ("cash:post_adjustment",)'), isTrue);
      expect(src.contains('payload.get("kind"'), isTrue);
      expect(src.contains('is_receipt = req.kind == "receipt"'), isTrue,
          reason: 'backend coi receipt là dòng tiền VÀO quỹ, adjustment là RA quỹ');
    });
  });
}
