import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kho_tra_sua/src/features/auth/auth_service.dart';
import 'package:kho_tra_sua/src/features/auth/login_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

/// Bộ nhớ giả cho FlutterSecureStorage để test persist offline session.
/// (Trên `flutter test`, plugin thật không có platform channel nên mọi
/// read/write đều no-op.)
class FakeStorage extends FlutterSecureStorage {
  FakeStorage();

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

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }
}

void main() {
  http.Client unavailableApi() => MockClient(
        (_) async => throw http.ClientException('API unavailable'),
      );

  // NOTE: body ASCII — `http.Response(String, ...)` không nhận non-Latin1.
  http.Client statusApi(int status, [String body = '{"detail":"Server error"}']) =>
      MockClient((_) async => http.Response(body, status));

  group('AuthService offline fallback', () {
    test(
        'opens a local staff session for a known shift account when API is down',
        () async {
      final auth = AuthService(
        baseUrl: 'https://api.example.test',
        httpClient: unavailableApi(),
        googleIdTokenProvider: () async => null,
      );

      final ok = await auth.signInWithPassword(
        username: 'staff_morning',
        password: 'DemoPass123!',
      );

      expect(ok, isTrue);
      expect(auth.isOfflineSession, isTrue);
      expect(auth.user?.username, 'staff_morning');
      expect(auth.lastError, isNull);
    });

    test('does not turn unknown password credentials into an offline session',
        () async {
      final auth = AuthService(
        baseUrl: 'https://api.example.test',
        httpClient: unavailableApi(),
        googleIdTokenProvider: () async => null,
      );

      final ok = await auth.signInWithPassword(
        username: 'not-a-demo-user',
        password: 'incorrect',
      );

      expect(ok, isFalse);
      expect(auth.isOfflineSession, isFalse);
      expect(auth.user, isNull);
    });

    test('uses the explicit Google demo identity when the API is down',
        () async {
      final auth = AuthService(
        baseUrl: 'https://api.example.test',
        httpClient: unavailableApi(),
        googleIdTokenProvider: () async => null,
      );

      final ok = await auth.signInWithGoogle(
        customToken: 'mock-manager_demo@milktea.local:Quản Lý Demo',
      );

      expect(ok, isTrue);
      expect(auth.isOfflineSession, isTrue);
      expect(auth.user?.username, 'manager_demo');
      expect(auth.user?.roles, contains('admin'));
    });

    test(
        'register username la (trainee_bar) KHONG fallback offline (giu loi)',
        () async {
      final auth = AuthService(
        baseUrl: 'https://api.example.test',
        httpClient: unavailableApi(),
        googleIdTokenProvider: () async => null,
      );

      final ok = await auth.register(
        username: 'trainee_bar',
        password: 'StrongDemoPass123!',
        displayName: 'Nhân viên thử việc',
        email: 'trainee@example.test',
      );

      expect(ok, isFalse);
      expect(auth.isOfflineSession, isFalse);
      expect(auth.user, isNull);
      expect(auth.lastError, isNotNull);
    });

    test('register tai khoan ca truc VAN fallback offline khi API down',
        () async {
      final auth = AuthService(
        baseUrl: 'https://api.example.test',
        httpClient: unavailableApi(),
        googleIdTokenProvider: () async => null,
      );

      final ok = await auth.register(
        username: 'staff_morning',
        password: 'DemoPass123!',
        displayName: 'Nguyễn Thị Mai (Pha Chế Ca Sáng)',
      );

      expect(ok, isTrue);
      expect(auth.isOfflineSession, isTrue);
      expect(auth.user?.username, 'staff_morning');
      expect(auth.user?.roles, contains('staff'));
    });
  });

  group('HIGH #1: thu hep offline fallback (chi 5xx / timeout / loi mang)', () {
    tearDown(() {
      AuthService.mockTokenAllowedOverride = null;
    });

    test('404 KHONG fallback local-mode (giu nguyen loi server)', () async {
      final auth = AuthService(
        baseUrl: 'https://api.example.test',
        httpClient: statusApi(404, '{"detail":"Not found"}'),
        googleIdTokenProvider: () async => null,
      );

      final ok = await auth.signInWithPassword(
        username: 'staff_morning',
        password: 'DemoPass123!',
      );

      expect(ok, isFalse);
      expect(auth.isOfflineSession, isFalse);
      expect(auth.user, isNull);
      expect(auth.lastError, isNotNull);
      // Đi đúng nhánh status (giữ message server), không phải nhánh exception.
      expect(auth.lastError, 'Not found');
    });

    test('429 KHONG fallback local-mode (giu nguyen loi server)', () async {
      final auth = AuthService(
        baseUrl: 'https://api.example.test',
        httpClient: statusApi(429, '{"detail":"Too many requests"}'),
        googleIdTokenProvider: () async => null,
      );

      final ok = await auth.signInWithPassword(
        username: 'staff_morning',
        password: 'DemoPass123!',
      );

      expect(ok, isFalse);
      expect(auth.isOfflineSession, isFalse);
      expect(auth.user, isNull);
      expect(auth.lastError, isNotNull);
    });

    test('register gap 404 KHONG tao offline session', () async {
      final auth = AuthService(
        baseUrl: 'https://api.example.test',
        httpClient: statusApi(404, '{"detail":"Not found"}'),
        googleIdTokenProvider: () async => null,
      );

      final ok = await auth.register(
        username: 'trainee_bar',
        password: 'StrongDemoPass123!',
        displayName: 'Nhân viên thử việc',
      );

      expect(ok, isFalse);
      expect(auth.isOfflineSession, isFalse);
      expect(auth.user, isNull);
    });

    test('HTTP 500 VAN fallback local-mode cho tai khoan ca truc', () async {
      final auth = AuthService(
        baseUrl: 'https://api.example.test',
        httpClient: statusApi(500),
        googleIdTokenProvider: () async => null,
      );

      final ok = await auth.signInWithPassword(
        username: 'staff_morning',
        password: 'DemoPass123!',
      );

      expect(ok, isTrue);
      expect(auth.isOfflineSession, isTrue);
      expect(auth.user?.username, 'staff_morning');
    });
  });

  group('HIGH #2: gate mock token bang kDebugMode', () {
    tearDown(() {
      AuthService.mockTokenAllowedOverride = null;
    });

    test('allowMockTokens mac dinh bam kDebugMode (test chay o debug)', () {
      expect(AuthService.allowMockTokens, isTrue);
    });

    test('mock token bi tu choi khi prod-flag tat', () async {
      AuthService.mockTokenAllowedOverride = false;
      final auth = AuthService(
        baseUrl: 'https://api.example.test',
        httpClient: unavailableApi(),
        googleIdTokenProvider: () async => null,
      );

      final ok = await auth.signInWithGoogle(
        customToken: 'mock-manager_demo@milktea.local:Quản Lý Demo',
      );

      expect(ok, isFalse);
      expect(auth.isOfflineSession, isFalse);
      expect(auth.user, isNull);
    });
  });

  group('HIGH #3: TTL offline session + backend song lai', () {
    tearDown(() {
      AuthService.mockTokenAllowedOverride = null;
    });

    String offlineJson(int createdAtMs) => json.encode({
          'id': 'offline-trainee_bar',
          'username': 'trainee_bar',
          'display_name': 'Nhân viên thử việc',
          'roles': ['staff'],
          'offline_created_at': createdAtMs,
        });

    test('offline session qua TTL 24h bi discard', () async {
      final storage = FakeStorage();
      final expiredMs = DateTime.now().millisecondsSinceEpoch -
          const Duration(hours: 25).inMilliseconds;
      await storage.write(
        key: 'offline_session_user',
        value: offlineJson(expiredMs),
      );

      final auth = AuthService(
        baseUrl: 'https://api.example.test',
        httpClient: unavailableApi(),
        storage: storage,
      );
      await auth.tryAutoLogin();

      expect(auth.user, isNull);
      expect(auth.isOfflineSession, isFalse);
      expect(await storage.read(key: 'offline_session_user'), isNull);
    });

    test('backend song lai thi discard offline + bao can dang nhap lai',
        () async {
      final storage = FakeStorage();
      await storage.write(
        key: 'offline_session_user',
        value: offlineJson(DateTime.now().millisecondsSinceEpoch),
      );

      final auth = AuthService(
        baseUrl: 'https://api.example.test',
        // Mọi HTTP response (kể cả 401) đều chứng tỏ backend đã sống lại.
        httpClient: statusApi(401, '{"detail":"Unauthorized"}'),
        storage: storage,
      );
      await auth.tryAutoLogin();

      expect(auth.user, isNull);
      expect(auth.isOfflineSession, isFalse);
      expect(auth.needsOfflineRelogin, isTrue);
      expect(auth.offlineReloginMessage, contains('đăng nhập lại'));
      expect(await storage.read(key: 'offline_session_user'), isNull);
    });

    test('backend chet thi giu offline session con han', () async {
      final storage = FakeStorage();
      await storage.write(
        key: 'offline_session_user',
        value: offlineJson(DateTime.now().millisecondsSinceEpoch),
      );

      final auth = AuthService(
        baseUrl: 'https://api.example.test',
        httpClient: unavailableApi(),
        storage: storage,
      );
      await auth.tryAutoLogin();

      expect(auth.user?.username, 'trainee_bar');
      expect(auth.isOfflineSession, isTrue);
      expect(auth.needsOfflineRelogin, isFalse);
    });
  });

  group('LOW: 401/403 + FormatException khong fallback', () {
    test('401 giu loi server, khong fallback offline', () async {
      final auth = AuthService(
        baseUrl: 'https://api.example.test',
        httpClient: statusApi(401, '{"detail":"Unauthorized"}'),
        googleIdTokenProvider: () async => null,
      );

      final ok = await auth.signInWithPassword(
        username: 'staff_morning',
        password: 'DemoPass123!',
      );

      expect(ok, isFalse);
      expect(auth.isOfflineSession, isFalse);
      expect(auth.user, isNull);
      expect(auth.lastError, 'Unauthorized');
    });

    test('403 giu loi server, khong fallback offline', () async {
      final auth = AuthService(
        baseUrl: 'https://api.example.test',
        httpClient: statusApi(403, '{"detail":"Forbidden"}'),
        googleIdTokenProvider: () async => null,
      );

      final ok = await auth.signInWithPassword(
        username: 'staff_morning',
        password: 'DemoPass123!',
      );

      expect(ok, isFalse);
      expect(auth.isOfflineSession, isFalse);
      expect(auth.user, isNull);
      expect(auth.lastError, 'Forbidden');
    });

    test('FormatException khong fallback offline', () async {
      final auth = AuthService(
        baseUrl: 'https://api.example.test',
        httpClient: MockClient((_) async => throw const FormatException('bad body')),
        googleIdTokenProvider: () async => null,
      );

      final ok = await auth.signInWithPassword(
        username: 'staff_morning',
        password: 'DemoPass123!',
      );

      expect(ok, isFalse);
      expect(auth.isOfflineSession, isFalse);
      expect(auth.user, isNull);
      expect(auth.lastError, isNotNull);
    });
  });

  group('HIGH #2b: login banner consume needsOfflineRelogin', () {
    String offlineJson(int createdAtMs) => json.encode({
          'id': 'offline-staff-morning',
          'username': 'staff_morning',
          'display_name': 'Nguyen Thi Mai (Pha Che Ca Sang)',
          'roles': ['staff'],
          'offline_created_at': createdAtMs,
        });

    testWidgets('banner hien khi co set + nut Dang nhap lai clear co',
        (tester) async {
      final storage = FakeStorage();
      await storage.write(
        key: 'offline_session_user',
        value: offlineJson(DateTime.now().millisecondsSinceEpoch),
      );
      final auth = AuthService(
        baseUrl: 'https://api.example.test',
        httpClient: statusApi(401, '{"detail":"Unauthorized"}'),
        storage: storage,
      );
      await auth.tryAutoLogin();
      expect(auth.needsOfflineRelogin, isTrue);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AuthService>.value(
            value: auth,
            child: const LoginScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('login-relogin-banner')), findsOneWidget);
      expect(find.textContaining('đăng nhập lại'), findsWidgets);

      await tester.tap(find.byKey(const Key('login-relogin-btn')));
      await tester.pump();

      expect(auth.needsOfflineRelogin, isFalse);
      expect(find.byKey(const Key('login-relogin-banner')), findsNothing);
    });
  });

  group('REVIEW-FIX: online success clears relogin flag + register keeps roles', () {
    String offlineJson(int createdAtMs) => json.encode({
          'id': 'offline-staff-morning',
          'username': 'staff_morning',
          'display_name': 'Staff Morning',
          'roles': ['staff'],
          'offline_created_at': createdAtMs,
        });

    String onlineUserJson(String username, List<String> roles) => json.encode({
          'access_token': 'tok-online',
          'refresh_token': 'ref-online',
          'user': {
            'id': 'u-online',
            'username': username,
            'display_name': 'Online User',
            'roles': roles,
          },
        });

    test('password online success clears needsOfflineRelogin/message', () async {
      final storage = FakeStorage();
      await storage.write(
        key: 'offline_session_user',
        value: offlineJson(DateTime.now().millisecondsSinceEpoch),
      );
      final auth = AuthService(
        baseUrl: 'https://api.example.test',
        httpClient: MockClient((req) async {
          if (req.method == 'GET' && req.url.path.endsWith('/auth/me')) {
            return http.Response('{"detail":"Unauthorized"}', 401);
          }
          if (req.method == 'POST' && req.url.path.endsWith('/auth/login')) {
            return http.Response(onlineUserJson('staff_morning', ['staff']), 200);
          }
          return http.Response('{"detail":"Not found"}', 404);
        }),
        storage: storage,
        googleIdTokenProvider: () async => null,
      );
      await auth.tryAutoLogin();
      expect(auth.needsOfflineRelogin, isTrue);

      final ok = await auth.signInWithPassword(
        username: 'staff_morning',
        password: 'DemoPass123!',
      );
      expect(ok, isTrue);
      expect(auth.needsOfflineRelogin, isFalse);
      expect(auth.offlineReloginMessage, isNull);
    });

    test('register online success clears needsOfflineRelogin/message', () async {
      final storage = FakeStorage();
      await storage.write(
        key: 'offline_session_user',
        value: offlineJson(DateTime.now().millisecondsSinceEpoch),
      );
      final auth = AuthService(
        baseUrl: 'https://api.example.test',
        httpClient: MockClient((req) async {
          if (req.method == 'GET' && req.url.path.endsWith('/auth/me')) {
            return http.Response('{"detail":"Unauthorized"}', 401);
          }
          if (req.method == 'POST' &&
              req.url.path.endsWith('/auth/register')) {
            return http.Response(
                onlineUserJson('staff_morning', ['staff']), 201);
          }
          return http.Response('{"detail":"Not found"}', 404);
        }),
        storage: storage,
        googleIdTokenProvider: () async => null,
      );
      await auth.tryAutoLogin();
      expect(auth.needsOfflineRelogin, isTrue);

      final ok = await auth.register(
        username: 'staff_morning',
        password: 'DemoPass123!',
        displayName: 'Staff Morning',
      );
      expect(ok, isTrue);
      expect(auth.needsOfflineRelogin, isFalse);
      expect(auth.offlineReloginMessage, isNull);
    });

    test('Google online success clears needsOfflineRelogin/message', () async {
      final storage = FakeStorage();
      await storage.write(
        key: 'offline_session_user',
        value: offlineJson(DateTime.now().millisecondsSinceEpoch),
      );
      final auth = AuthService(
        baseUrl: 'https://api.example.test',
        httpClient: MockClient((req) async {
          if (req.method == 'GET' && req.url.path.endsWith('/auth/me')) {
            return http.Response('{"detail":"Unauthorized"}', 401);
          }
          if (req.method == 'POST' && req.url.path.endsWith('/auth/google')) {
            return http.Response(
                onlineUserJson('staff_morning', ['staff']), 200);
          }
          return http.Response('{"detail":"Not found"}', 404);
        }),
        storage: storage,
        googleIdTokenProvider: () async => null,
      );
      await auth.tryAutoLogin();
      expect(auth.needsOfflineRelogin, isTrue);

      final ok = await auth.signInWithGoogle(customToken: 'real-id-token-abc');
      expect(ok, isTrue);
      expect(auth.needsOfflineRelogin, isFalse);
      expect(auth.offlineReloginMessage, isNull);
    });

    test('register offline manager_demo keeps admin/approver roles', () async {
      final auth = AuthService(
        baseUrl: 'https://api.example.test',
        httpClient: unavailableApi(),
        googleIdTokenProvider: () async => null,
      );

      final ok = await auth.register(
        username: 'manager_demo',
        password: 'DemoPass123!',
        displayName: 'Manager Demo',
      );

      expect(ok, isTrue);
      expect(auth.isOfflineSession, isTrue);
      expect(auth.user?.roles, contains('admin'));
      expect(auth.user?.roles, contains('approver'));
    });

    test('register offline 5xx manager_demo keeps admin/approver roles',
        () async {
      final auth = AuthService(
        baseUrl: 'https://api.example.test',
        httpClient: statusApi(500),
        googleIdTokenProvider: () async => null,
      );

      final ok = await auth.register(
        username: 'manager_demo',
        password: 'DemoPass123!',
        displayName: 'Manager Demo',
      );

      expect(ok, isTrue);
      expect(auth.isOfflineSession, isTrue);
      expect(auth.user?.roles, contains('admin'));
      expect(auth.user?.roles, contains('approver'));
    });
  });
}
