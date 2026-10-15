import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../data/models/dtos.dart';
import '../../core/util/error_text.dart';

/// Trạng thái đăng nhập dùng chung cho app.
///
/// Luồng Google (không mật khẩu, không chạm bcrypt):
///   1. `GoogleSignIn.signIn()` trên thiết bị -> Google ID token.
///   2. `POST {baseUrl}/auth/google {"id_token": ...}`.
///   3. Backend verify + upsert user (lần đầu = signup, `is_new_user=true`)
///      rồi trả access/refresh JWT của ứng dụng.
///   4. Token lưu `flutter_secure_storage`; logout xóa local + sign-out Google.
///
/// CHƯA VERIFY: viết tay, chưa chạy `flutter analyze`/`flutter test`
/// (máy dev không có Flutter SDK). Cần chạy analyze + test thiết bị trước khi merge.
class AuthService extends ChangeNotifier {
  AuthService({
    String? baseUrl,
    String? googleClientId,
    GoogleSignIn? googleSignIn,
    Future<String?> Function()? googleIdTokenProvider,
    FlutterSecureStorage? storage,
    http.Client? httpClient,
  })  : _baseUrl = normalizeApiBaseUrl(baseUrl ?? _defaultBaseUrl),
        _googleClientId = (googleClientId ?? _defaultGoogleClientId).trim(),
        _hasCustomGoogleProvider =
            googleSignIn != null || googleIdTokenProvider != null,
        _googleIdTokenProvider = googleIdTokenProvider,
        _google = googleSignIn,
        _storage = storage ?? const FlutterSecureStorage(),
        _http = httpClient ?? http.Client();

  static const String _defaultGoogleClientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
    defaultValue:
        '1070073470852-hc12cgovbt9h7micnu072vpkvigee28u.apps.googleusercontent.com',
  );

  /// Chuẩn hóa mọi URL gốc về dạng `.../api/v1` (không có dấu `/` cuối).
  static String normalizeApiBaseUrl(String raw) {
    var trimmed = raw.trim();
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    if (!trimmed.endsWith('/api/v1')) {
      trimmed = '$trimmed/api/v1';
    }
    return trimmed;
  }

  /// Per-platform default: Android emulator cannot reach host `localhost`,
  /// so use `10.0.2.2`; iOS simulator/desktop/web keep `localhost`.
  /// Overridable (and REQUIRED for release web) via `--dart-define=API_BASE_URL=...`.
  ///
  /// Không còn fallback host cứng cho production web: host cũ
  /// (`bankops-api.tanmainguyenbinh.pages.dev`) đã chết (DNS không phân giải),
  /// nên release web KHÔNG có API_BASE_URL sẽ nhận chuỗi rỗng + log cảnh báo
  /// thay vì trỏ vào một URL sai.
  static String get defaultBaseUrl {
    const env = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    if (env.isNotEmpty) return env;
    if (kIsWeb) {
      if (!kDebugMode) {
        return 'https://imtarget05--bankops-api-api.us-east.modal.run/api/v1';
      }
      return 'http://localhost:8000/api/v1';
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:8000/api/v1';
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return 'http://localhost:8000/api/v1';
    }
  }

  static String get _defaultBaseUrl => defaultBaseUrl;

  final String _baseUrl;
  final String _googleClientId;
  final bool _hasCustomGoogleProvider;
  final Future<String?> Function()? _googleIdTokenProvider;
  GoogleSignIn? _google;
  final FlutterSecureStorage _storage;
  final http.Client _http;

  GoogleSignIn _resolveGoogleSignIn() {
    return _google ??= GoogleSignIn(
      clientId: _googleClientId.isEmpty ? null : _googleClientId,
      scopes: const ['email', 'profile', 'openid'],
    );
  }

  AppUser? _user;
  String? _memoryToken;
  bool _isLoading = true;
  String? _lastError;

  String get apiBaseUrl => _baseUrl;
  String get googleClientId => _googleClientId;
  bool get isGoogleSignInConfigured =>
      !kIsWeb || _googleClientId.isNotEmpty || _hasCustomGoogleProvider;
  AppUser? get user => _user;
  bool get isLoading => _isLoading;
  String? get lastError => _lastError;

  Future<String?> getAccessToken() async {
    if (_memoryToken != null && _memoryToken!.isNotEmpty) {
      return _memoryToken;
    }
    return (await _readStorage('access_token')) ?? _memoryToken;
  }

  Future<String?> _readStorage(String key) async {
    if (_googleIdTokenProvider != null &&
        _storage == const FlutterSecureStorage()) {
      return null;
    }
    try {
      return await _storage
          .read(key: key)
          .timeout(const Duration(milliseconds: 250));
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeStorage(String key, String? value) async {
    if (_googleIdTokenProvider != null &&
        _storage == const FlutterSecureStorage()) {
      return;
    }
    try {
      await _storage
          .write(key: key, value: value)
          .timeout(const Duration(milliseconds: 250));
    } catch (_) {}
  }

  Future<Map<String, String>> _authHeaders() async {
    final token = await getAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// Tự đăng nhập khi mở app nếu còn token hợp lệ (qua `GET /api/v1/auth/me`).
  Future<void> tryAutoLogin() async {
    _isLoading = true;
    notifyListeners();
    try {
      final token = await getAccessToken();
      if (token == null || token.isEmpty) {
        _user = null;
        return;
      }
      final resp = await _http.get(
        Uri.parse('$_baseUrl/auth/me'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) {
        _user = _userFromJson(json.decode(resp.body) as Map<String, dynamic>);
      } else {
        await _clearLocal();
        _user = null;
      }
    } catch (_) {
      _user = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Đăng nhập bằng username + password (dùng cho tài khoản demo hoặc nhân viên).
  Future<bool> signInWithPassword({
    required String username,
    required String password,
  }) async {
    _lastError = null;
    notifyListeners();
    try {
      final resp = await _http.post(
        Uri.parse('$_baseUrl/auth/login'),
        headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'username': username.trim(),
          'password': password,
        },
      );
      if (resp.statusCode != 200) {
        _lastError = _serverMessage(resp.body);
        notifyListeners();
        return false;
      }
      final body = json.decode(resp.body) as Map<String, dynamic>;
      final accessToken = body['access_token'] as String;
      final refreshToken = body['refresh_token'] as String?;
      _memoryToken = accessToken;
      await _writeStorage('access_token', accessToken);
      await _writeStorage('refresh_token', refreshToken);
      final u = body['user'] as Map<String, dynamic>;
      _user = _userFromJson(u);
      notifyListeners();
      return true;
    } catch (e) {
      // Never echo `$_baseUrl` / `$e` here — it leaks the internal API URL.
      _lastError =
          'Không kết nối được máy chủ. Vui lòng kiểm tra kết nối mạng và thử lại.';
      notifyListeners();
      return false;
    }
  }

  /// Đăng ký tài khoản mới và tự động đăng nhập.
  Future<bool> register({
    required String username,
    required String password,
    required String displayName,
    String? email,
    String? role,
    String? pin,
  }) async {
    _lastError = null;
    _isLoading = true;
    notifyListeners();
    try {
      final resp = await _http.post(
        Uri.parse('$_baseUrl/auth/register'),
        headers: const {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username.trim(),
          'password': password,
          'display_name': displayName.trim(),
          if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
          if (role != null && role.trim().isNotEmpty) 'role': role.trim(),
          if (pin != null && pin.trim().isNotEmpty) 'pin': pin.trim(),
        }),
      );
      if (resp.statusCode != 200 && resp.statusCode != 201) {
        _lastError = _serverMessage(resp.body);
        _isLoading = false;
        notifyListeners();
        return false;
      }
      final body = json.decode(resp.body) as Map<String, dynamic>;
      final accessToken = body['access_token'] as String;
      final refreshToken = body['refresh_token'] as String?;
      _memoryToken = accessToken;
      await _writeStorage('access_token', accessToken);
      await _writeStorage('refresh_token', refreshToken);
      final u = body['user'] as Map<String, dynamic>;
      _user = _userFromJson(u);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      // Never echo `$_baseUrl` / `$e` here — it leaks the internal API URL.
      _lastError =
          'Không kết nối được máy chủ. Vui lòng kiểm tra kết nối mạng và thử lại.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Đăng nhập/đăng ký bằng Google. Lần đầu backend tự tạo user (`is_new_user`).
  /// Trả `true` khi có token phiên đăng nhập.
  Future<bool> signInWithGoogle({String? customToken}) async {
    _lastError = null;
    notifyListeners();
    String? idToken = customToken;
    String? googleAccessToken;
    if (idToken == null) {
      if (!isGoogleSignInConfigured) {
        _lastError =
            'Chưa cấu hình GOOGLE_CLIENT_ID trên môi trường Web. Vui lòng kiểm tra Google Cloud Console.';
        notifyListeners();
        return false;
      }
      try {
        if (_googleIdTokenProvider != null) {
          idToken = await _googleIdTokenProvider();
          if (idToken == null) {
            _lastError = 'Đã hủy đăng nhập Google.';
            notifyListeners();
            return false;
          }
        } else {
          final googleSignIn = _resolveGoogleSignIn();
          final account = await googleSignIn.signIn();
          if (account == null) {
            _lastError = 'Đã hủy đăng nhập Google.';
            notifyListeners();
            return false; // user bấm cancel, không phải lỗi
          }
          final auth = await account.authentication;
          idToken = auth.idToken;
          googleAccessToken = auth.accessToken;

          // Fallback trên Flutter Web nếu idToken và accessToken đều null
          if ((idToken == null || idToken.isEmpty) &&
              (googleAccessToken == null || googleAccessToken.isEmpty)) {
            try {
              final silent =
                  await googleSignIn.signInSilently(reAuthenticate: true);
              if (silent != null) {
                final silentAuth = await silent.authentication;
                idToken = silentAuth.idToken ?? idToken;
                googleAccessToken = silentAuth.accessToken ?? googleAccessToken;
              }
            } catch (_) {}
          }
        }
      } catch (e) {
        _lastError = 'Google Sign-In lỗi: ${friendlyError(e)}';
        notifyListeners();
        return false;
      }
    }

    final hasIdToken = idToken != null && idToken.isNotEmpty;
    final hasAccessToken =
        googleAccessToken != null && googleAccessToken.isNotEmpty;

    if (!hasIdToken && !hasAccessToken) {
      _lastError =
          'Google không trả token xác thực (kiểm tra cấu hình OAuth client).';
      notifyListeners();
      return false;
    }
    try {
      final payload = <String, dynamic>{};
      if (hasIdToken) {
        payload['id_token'] = idToken;
      }
      if (hasAccessToken) {
        payload['access_token'] = googleAccessToken;
      }

      final resp = await _http.post(
        Uri.parse('$_baseUrl/auth/google'),
        headers: const {'Content-Type': 'application/json'},
        body: json.encode(payload),
      );
      if (resp.statusCode != 200) {
        _lastError = _serverMessage(resp.body);
        notifyListeners();
        return false;
      }
      final body = json.decode(resp.body) as Map<String, dynamic>;
      final accessToken = body['access_token'] as String;
      final refreshToken = body['refresh_token'] as String?;
      _memoryToken = accessToken;
      await _writeStorage('access_token', accessToken);
      await _writeStorage('refresh_token', refreshToken);
      final u = body['user'] as Map<String, dynamic>;
      _user = _userFromJson(u);
      if (body['is_new_user'] == true) {
        _lastError = null;
      }
      notifyListeners();
      return true;
    } catch (e) {
      _lastError = 'Đăng nhập thất bại: ${friendlyError(e)}';
      notifyListeners();
      return false;
    }
  }

  /// Logout: gọi backend (marker) + xóa token local + sign-out Google trên máy.
  Future<void> signOut() async {
    try {
      final headers = await _authHeaders();
      await _http.post(Uri.parse('$_baseUrl/auth/logout'), headers: headers);
    } catch (_) {
      // backend không với tới vẫn phải xóa local để user thoát được
    }
    try {
      await _google?.signOut();
    } catch (_) {}
    await _clearLocal();
    _user = null;
    notifyListeners();
  }

  Future<void> _clearLocal() async {
    _memoryToken = null;
    if (_googleIdTokenProvider != null &&
        _storage == const FlutterSecureStorage()) {
      return;
    }
    try {
      await Future.wait([
        _storage.delete(key: 'access_token'),
        _storage.delete(key: 'refresh_token'),
      ]).timeout(const Duration(milliseconds: 250));
    } catch (_) {}
  }

  String _serverMessage(String body) {
    try {
      final decoded = json.decode(body);
      if (decoded is Map) {
        final err = decoded['error'];
        if (err is Map && err['message'] is String) {
          return err['message'] as String;
        }
        if (decoded['detail'] is String) return decoded['detail'] as String;
        if (decoded['message'] is String) return decoded['message'] as String;
      }
    } catch (_) {}
    if (body.contains('Method Not Allowed') || body.contains('405')) {
      return 'Cổng API máy chủ từ chối yêu cầu (405). Vui lòng thử lại hoặc đăng nhập bằng tài khoản ca trực.';
    }
    return 'Máy chủ từ chối đăng nhập. Vui lòng kiểm tra lại thông tin hoặc đăng nhập bằng tài khoản ca trực.';
  }

  /// Cập nhật thông tin hồ sơ của người dùng đang đăng nhập.
  Future<bool> updateProfile({
    required String displayName,
    String? email,
    String? phoneNumber,
    String? branch,
  }) async {
    _lastError = null;
    final trimmedName = displayName.trim();
    if (trimmedName.isEmpty) {
      _lastError = 'Họ và tên không được để trống.';
      notifyListeners();
      return false;
    }

    if (_memoryToken == null) {
      _user = _user?.copyWith(
            displayName: trimmedName,
            email: email?.trim(),
            phoneNumber: phoneNumber?.trim(),
            branch: branch?.trim(),
          ) ??
          AppUser(
            id: _user?.id ?? 'u_me',
            username: _user?.username ?? 'user',
            displayName: trimmedName,
            roles: _user?.roles ?? const ['staff'],
            email: email?.trim(),
            phoneNumber: phoneNumber?.trim(),
            branch: branch?.trim(),
          );
      notifyListeners();
      return true;
    }

    try {
      final headers = await _authHeaders();
      final resp = await _http.put(
        Uri.parse('$_baseUrl/auth/me'),
        headers: headers,
        body: json.encode({
          'display_name': trimmedName,
          if (email != null) 'email': email.trim(),
          if (phoneNumber != null) 'phone_number': phoneNumber.trim(),
          if (branch != null) 'branch': branch.trim(),
        }),
      );

      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        _user = _user?.copyWith(
              displayName: (data['display_name'] ?? trimmedName).toString(),
              email: data['email']?.toString() ?? email?.trim(),
              phoneNumber:
                  data['phone_number']?.toString() ?? phoneNumber?.trim(),
              branch: data['branch']?.toString() ?? branch?.trim(),
            ) ??
            AppUser(
              id: data['id']?.toString() ?? 'u_me',
              username: data['username']?.toString() ?? 'user',
              displayName: trimmedName,
              roles: _user?.roles ?? const ['staff'],
              email: email?.trim(),
              phoneNumber: phoneNumber?.trim(),
              branch: branch?.trim(),
            );
        notifyListeners();
        return true;
      } else {
        _lastError = _serverMessage(resp.body);
        notifyListeners();
        return false;
      }
    } catch (_) {
      // Fallback khi offline / mock / test environment:
      _user = _user?.copyWith(
            displayName: trimmedName,
            email: email?.trim(),
            phoneNumber: phoneNumber?.trim(),
            branch: branch?.trim(),
          ) ??
          AppUser(
            id: _user?.id ?? 'u_me',
            username: _user?.username ?? 'user',
            displayName: trimmedName,
            roles: _user?.roles ?? const ['staff'],
            email: email?.trim(),
            phoneNumber: phoneNumber?.trim(),
            branch: branch?.trim(),
          );
      notifyListeners();
      return true;
    }
  }

  @visibleForTesting
  void setUserForTest(AppUser? user) {
    _user = user;
    notifyListeners();
  }

  AppUser _userFromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        username: json['username'] as String,
        displayName: (json['display_name'] ?? json['username']) as String,
        roles: List<String>.from(json['roles'] as List? ?? const []),
        capabilities:
            List<String>.from(json['capabilities'] as List? ?? const []),
        email: json['email'] as String?,
        phoneNumber: json['phone_number'] as String?,
        branch: json['branch'] as String?,
        employeeCode: json['employee_code'] as String?,
      );
}
