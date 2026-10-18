import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kho_tra_sua/src/features/auth/accept_invite_screen.dart';
import 'package:kho_tra_sua/src/features/auth/auth_service.dart';
import 'package:provider/provider.dart';

class _FakeStorage extends FlutterSecureStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}

void main() {
  Widget buildTestWidget({
    required AuthService auth,
    String? initialToken,
    VoidCallback? onBackToLogin,
    VoidCallback? onSuccess,
  }) {
    return ChangeNotifierProvider<AuthService>.value(
      value: auth,
      child: MaterialApp(
        home: AcceptInviteScreen(
          initialToken: initialToken,
          onBackToLogin: onBackToLogin,
          onSuccess: onSuccess,
        ),
      ),
    );
  }

  testWidgets('AcceptInviteScreen displays prefilled token and validation',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final client = MockClient((req) async => http.Response('{}', 200));
    final auth = AuthService(
      baseUrl: 'http://localhost:8000',
      storage: _FakeStorage(),
      httpClient: client,
    );

    await tester.pumpWidget(
      buildTestWidget(auth: auth, initialToken: 'valid-test-token-123'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Kích Hoạt Tài Khoản'), findsOneWidget);
    expect(find.text('valid-test-token-123'), findsOneWidget);
    expect(find.byIcon(Icons.vpn_key_rounded), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(3));

    final submitBtn = find.text('Kích Hoạt & Đăng Nhập Ngay');
    await tester.ensureVisible(submitBtn);
    await tester.tap(submitBtn);
    await tester.pumpAndSettle();

    expect(find.text('Mật khẩu phải có tối thiểu 6 ký tự'), findsOneWidget);
  });

  testWidgets('AcceptInviteScreen validates password confirmation mismatch',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final client = MockClient((req) async => http.Response('{}', 200));
    final auth = AuthService(
      baseUrl: 'http://localhost:8000',
      storage: _FakeStorage(),
      httpClient: client,
    );

    await tester.pumpWidget(
      buildTestWidget(auth: auth, initialToken: 'tok-abc'),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(1), 'Secret123!');
    await tester.enterText(fields.at(2), 'Different123!');
    await tester.pump();

    final submitBtn = find.text('Kích Hoạt & Đăng Nhập Ngay');
    await tester.ensureVisible(submitBtn);
    await tester.tap(submitBtn);
    await tester.pumpAndSettle();

    expect(find.text('Mật khẩu xác nhận không trùng khớp'), findsOneWidget);
  });

  testWidgets('AcceptInviteScreen accepts invite and logs in successfully',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    var successCallbackFired = false;
    final storage = _FakeStorage();
    final client = MockClient((req) async {
      if (req.url.path.endsWith('/auth/accept-invite')) {
        final body = json.decode(req.body);
        expect(body['invite_token'], 'valid-token-xyz');
        expect(body['new_password'], 'PhaChe2026!');

        return http.Response(
          json.encode({
            'access_token': 'jwt-access-token-999',
            'refresh_token': 'jwt-refresh-token-999',
            'user': {
              'id': 'user-uuid-1',
              'username': 'nhanvien_moi',
              'display_name': 'Nhân Viên Mới',
              'roles': ['staff'],
              'capabilities': ['inventory:view_balances'],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('Not found', 404);
    });

    final auth = AuthService(
      baseUrl: 'http://localhost:8000',
      storage: storage,
      httpClient: client,
    );

    await tester.pumpWidget(
      buildTestWidget(
        auth: auth,
        initialToken: 'valid-token-xyz',
        onSuccess: () => successCallbackFired = true,
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(1), 'PhaChe2026!');
    await tester.enterText(fields.at(2), 'PhaChe2026!');
    await tester.pump();

    final submitBtn = find.text('Kích Hoạt & Đăng Nhập Ngay');
    await tester.ensureVisible(submitBtn);
    await tester.tap(submitBtn);
    await tester.pumpAndSettle();

    expect(auth.user, isNotNull);
    expect(auth.user!.username, 'nhanvien_moi');
    expect(storage.values['access_token'], 'jwt-access-token-999');
    expect(find.text('Kích hoạt tài khoản thành công! Chào mừng bạn.'),
        findsOneWidget);
    expect(successCallbackFired, isTrue);
  });

  testWidgets(
      'AcceptInviteScreen displays error when token is expired or invalid',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final client = MockClient((req) async {
      return http.Response(
        json.encode(
            {'detail': 'Mã mời đã hết hạn. Vui lòng liên hệ quản trị viên.'}),
        400,
        headers: {'content-type': 'application/json'},
      );
    });

    final auth = AuthService(
      baseUrl: 'http://localhost:8000',
      storage: _FakeStorage(),
      httpClient: client,
    );

    await tester.pumpWidget(
      buildTestWidget(auth: auth, initialToken: 'expired-token'),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(1), 'Password123!');
    await tester.enterText(fields.at(2), 'Password123!');
    await tester.pump();

    final submitBtn = find.text('Kích Hoạt & Đăng Nhập Ngay');
    await tester.ensureVisible(submitBtn);
    await tester.tap(submitBtn);
    await tester.pumpAndSettle();

    expect(find.text('Mã mời đã hết hạn. Vui lòng liên hệ quản trị viên.'),
        findsOneWidget);
    expect(auth.user, isNull);
  });
}
