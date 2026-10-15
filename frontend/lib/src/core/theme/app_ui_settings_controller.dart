import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme_mode_controller.dart';

/// 4 Bộ màu sắc thương hiệu đặc trưng của Quán Trà Sữa
enum AppColorPreset {
  matcha,    // Xanh Matcha Tươi (Emerald/Forest)
  milktea,   // Trà Sữa Truyền Thống (Caramel/Warm Chestnut)
  oolong,    // Ô Long Thượng Hạng (Royal Slate/Navy)
  berry,     // Trà Dâu/Sakura (Rose/Ruby)
}

/// Mật độ hiển thị giao diện
enum AppDensity {
  comfortable, // Tiêu chuẩn cho màn hình cảm ứng quầy POS
  compact,     // Gọn gàng cho kiểm kê & kiểm soát dữ liệu
}

/// Bộ điều khiển toàn diện các tuỳ chọn UI/UX ứng dụng
/// Tự động đồng bộ với SharedPreferences để duy trì cấu hình cá nhân hoá.
class AppUiSettingsController extends ThemeModeController {
  AppUiSettingsController() {
    _loadFromPrefs();
  }

  static const String _prefThemeMode = 'app_theme_mode';
  static const String _prefColorPreset = 'app_color_preset';
  static const String _prefDensity = 'app_layout_density';
  static const String _prefShowTicker = 'app_show_live_ticker';

  AppColorPreset _colorPreset = AppColorPreset.matcha;
  AppDensity _density = AppDensity.comfortable;
  bool _showLiveTicker = true;

  AppColorPreset get colorPreset => _colorPreset;
  AppDensity get density => _density;
  bool get showLiveTicker => _showLiveTicker;

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Theme mode
      final modeStr = prefs.getString(_prefThemeMode);
      if (modeStr != null) {
        if (modeStr == 'light') setMode(ThemeMode.light);
        if (modeStr == 'dark') setMode(ThemeMode.dark);
        if (modeStr == 'system') setMode(ThemeMode.system);
      }

      // Color preset
      final presetStr = prefs.getString(_prefColorPreset);
      if (presetStr != null) {
        for (final p in AppColorPreset.values) {
          if (p.name == presetStr) {
            _colorPreset = p;
            break;
          }
        }
      }

      // Density
      final densityStr = prefs.getString(_prefDensity);
      if (densityStr != null) {
        for (final d in AppDensity.values) {
          if (d.name == densityStr) {
            _density = d;
            break;
          }
        }
      }

      // Live Ticker
      final tickerVal = prefs.getBool(_prefShowTicker);
      if (tickerVal != null) {
        _showLiveTicker = tickerVal;
      }

      notifyListeners();
    } catch (_) {}
  }

  @override
  void setMode(ThemeMode mode) {
    super.setMode(mode);
    _savePrefString(_prefThemeMode, mode.name);
  }

  Future<void> setColorPreset(AppColorPreset preset) async {
    if (preset == _colorPreset) return;
    _colorPreset = preset;
    notifyListeners();
    await _savePrefString(_prefColorPreset, preset.name);
  }

  Future<void> setDensity(AppDensity density) async {
    if (density == _density) return;
    _density = density;
    notifyListeners();
    await _savePrefString(_prefDensity, density.name);
  }

  Future<void> setShowLiveTicker(bool show) async {
    if (show == _showLiveTicker) return;
    _showLiveTicker = show;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefShowTicker, show);
    } catch (_) {}
  }

  Future<void> _savePrefString(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (_) {}
  }
}
