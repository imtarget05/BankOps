import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Quản lý ngôn ngữ ứng dụng toàn cục (Tiếng Việt / English)
/// Tự động lưu và khôi phục từ SharedPreferences.
class LocaleController extends ChangeNotifier {
  LocaleController({Locale initialLocale = const Locale('vi')})
      : _locale = initialLocale {
    _loadFromPrefs();
  }

  static const String _prefKey = 'app_language_code';
  Locale _locale;

  Locale get locale => _locale;
  bool get isVietnamese => _locale.languageCode == 'vi';

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCode = prefs.getString(_prefKey);
      if (savedCode != null && (savedCode == 'vi' || savedCode == 'en')) {
        if (_locale.languageCode != savedCode) {
          _locale = Locale(savedCode);
          notifyListeners();
        }
      }
    } catch (_) {
      // Fallback yên lặng nếu storage không khả dụng
    }
  }

  Future<void> setLocale(Locale newLocale) async {
    if (newLocale.languageCode == _locale.languageCode) return;
    _locale = newLocale;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, newLocale.languageCode);
    } catch (_) {}
  }

  Future<void> toggleLanguage() async {
    final next = isVietnamese ? const Locale('en') : const Locale('vi');
    await setLocale(next);
  }
}
