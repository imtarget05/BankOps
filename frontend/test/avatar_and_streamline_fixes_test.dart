import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:kho_tra_sua/src/app/app_shell.dart';
import 'package:kho_tra_sua/src/app/theme_mode_controller.dart';
import 'package:kho_tra_sua/src/core/i18n/locale_controller.dart';
import 'package:kho_tra_sua/src/core/theme/app_ui_settings_controller.dart';
import 'package:kho_tra_sua/src/core/widgets/app_screen.dart';
import 'package:kho_tra_sua/src/core/widgets/user_avatar.dart';
import 'package:kho_tra_sua/src/data/models/dtos.dart';
import 'package:kho_tra_sua/src/data/repositories/bankops_repository.dart';
import 'package:kho_tra_sua/src/data/repositories/fake_repository.dart';
import 'package:kho_tra_sua/src/features/auth/auth_service.dart';
import 'package:kho_tra_sua/src/features/settings/settings_screen.dart';
import 'package:kho_tra_sua/src/features/settings/widgets/avatar_editor_sheet.dart';

class _MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return _MockHttpClient();
  }
}

class _MockHttpClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #getUrl ||
        invocation.memberName == #openUrl ||
        invocation.memberName == #open) {
      return Future.value(_MockHttpClientRequest());
    }
    return super.noSuchMethod(invocation);
  }
}

class _MockHttpClientRequest implements HttpClientRequest {
  @override
  final HttpHeaders headers = _MockHttpHeaders();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #close) {
      return Future.value(_MockHttpClientResponse());
    }
    return null;
  }
}

class _MockHttpHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _MockHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  static final _png1x1 = Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
    0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
    0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);

  @override
  int get statusCode => 200;

  @override
  int get contentLength => _png1x1.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(_png1x1).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Widget _buildTestApp({
  required Widget child,
  AppUser? user,
  BankOpsRepository? repo,
}) {
  final repository = repo ?? FakeBankOpsRepository(latency: Duration.zero);
  final authService = AuthService();
  if (user != null) {
    authService.setUserForTest(user);
  }

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeModeController>(
          create: (_) => ThemeModeController()),
      ChangeNotifierProvider<LocaleController>(
          create: (_) => LocaleController()),
      ChangeNotifierProvider<AppUiSettingsController>(
          create: (_) => AppUiSettingsController()),
      ChangeNotifierProvider<AuthService>.value(value: authService),
    ],
    child: RepositoryScope(
      repository: repository,
      child: MaterialApp(
        home: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    HttpOverrides.global = _MockHttpOverrides();
  });

  group('1. UserAvatar Gravatar & Email resolution', () {
    test('Calculates consistent Gravatar MD5 URL from email', () {
      final url = UserAvatar.gravatarUrl('tanmainguyenbinh@gmail.com');
      expect(url, startsWith('https://www.gravatar.com/avatar/'));
      expect(url, contains('?s=160&d=identicon'));

      // Case-insensitivity & whitespace trimming
      final urlUpper = UserAvatar.gravatarUrl('  TanMaiNguyenBinh@GMAIL.com ');
      expect(urlUpper, equals(url));
    });

    test('Resolves effective avatar URL properly', () {
      // Custom avatarUrl takes precedence
      expect(
        UserAvatar.resolveEffectiveAvatarUrl(
          avatarUrl: 'https://example.com/photo.png',
          email: 'test@example.com',
        ),
        equals('https://example.com/photo.png'),
      );

      // Falls back to email Gravatar when avatarUrl is null
      final gravatar = UserAvatar.resolveEffectiveAvatarUrl(
        avatarUrl: null,
        email: 'test@example.com',
      );
      expect(gravatar, startsWith('https://www.gravatar.com/avatar/'));

      // Falls back to null when neither is provided
      expect(
        UserAvatar.resolveEffectiveAvatarUrl(avatarUrl: null, email: null),
        isNull,
      );
    });

    testWidgets('Renders initials when no avatar URL is resolved',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UserAvatar(name: 'Tan Mai Nguyen Binh', size: 48),
          ),
        ),
      );

      expect(find.text('TB'), findsOneWidget);
    });

    testWidgets('Renders edit badge when showEditBadge is true',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UserAvatar(
              name: 'Tan Mai',
              size: 56,
              showEditBadge: true,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.camera_alt_rounded), findsOneWidget);
    });
  });

  group('2. Settings Profile Card Mobile Streamlining', () {
    testWidgets('Renders clean streamlined profile card on mobile screen',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const testUser = AppUser(
        id: 'u-1',
        username: 'tanmainguyenbinh',
        displayName: 'Tan Mai Nguyen Binh',
        email: 'tanmainguyenbinh@gmail.com',
        roles: ['maker', 'checker', 'admin'],
        branch: 'Chi nhánh Bến Thành (Hội sở)',
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const SettingsScreen(),
          user: testUser,
        ),
      );
      await tester.pumpAndSettle();

      // Profile details rendered
      expect(find.text('Tan Mai Nguyen Binh'), findsOneWidget);
      expect(find.textContaining('tanmainguyenbinh'), findsAtLeastNWidgets(1));

      // Mobile action buttons exist without text clipping
      expect(find.byKey(const Key('settings-edit-profile-mobile-btn')),
          findsOneWidget);
      expect(find.byKey(const Key('settings-change-avatar-btn')), findsOneWidget);

      // Verify no exceptions or overflow occurred
      expect(tester.takeException(), isNull);
    });
  });

  group('3. AvatarEditorSheet Component Tests', () {
    testWidgets('Displays options to upload from device, email, and presets',
        (tester) async {
      const testUser = AppUser(
        id: 'u-1',
        username: 'tanmainguyenbinh',
        displayName: 'Tan Mai Nguyen Binh',
        email: 'tanmainguyenbinh@gmail.com',
        roles: ['admin'],
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const AvatarEditorSheet(currentUser: testUser),
          user: testUser,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('avatar-pick-device-btn')), findsOneWidget);
      expect(find.byKey(const Key('avatar-sync-email-btn')), findsOneWidget);
      expect(find.byKey(const Key('avatar-url-input')), findsOneWidget);
      expect(find.byKey(const Key('avatar-url-apply-btn')), findsOneWidget);
      expect(find.text('Hoặc chọn ảnh nhận diện quầy vận hành:'), findsOneWidget);
    });
  });

  group('4. Single Drag Handle & Single Refresh Indicator Verification', () {
    testWidgets(
        'AppScreen does not inject duplicate RefreshIndicator when onRefresh is null',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppScreen(
              body: Text('Content'),
            ),
          ),
        ),
      );

      // No RefreshIndicator created when onRefresh is null
      expect(find.byType(RefreshIndicator), findsNothing);
      expect(find.text('Content'), findsOneWidget);
    });

    testWidgets(
        'AppScreen injects single RefreshIndicator only when onRefresh is provided',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppScreen(
              body: const Text('Content'),
              onRefresh: () async {},
            ),
          ),
        ),
      );

      expect(find.byType(RefreshIndicator), findsOneWidget);
    });
  });
}
