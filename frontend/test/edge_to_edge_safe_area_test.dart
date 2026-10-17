import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kho_tra_sua/src/core/theme/app_theme.dart';
import 'package:kho_tra_sua/src/core/widgets/app_screen.dart';

void main() {
  group('Edge-to-Edge and Safe Area Configuration Tests', () {
    test('AppTheme.light sets transparent system overlay with dark icons', () {
      final theme = AppTheme.light();
      final overlay = theme.appBarTheme.systemOverlayStyle;
      expect(overlay, isNotNull);
      expect(overlay!.statusBarColor, Colors.transparent);
      expect(overlay.statusBarIconBrightness, Brightness.dark);
      expect(overlay.systemNavigationBarColor, Colors.transparent);
      expect(overlay.systemNavigationBarDividerColor, Colors.transparent);
      expect(overlay.systemNavigationBarIconBrightness, Brightness.dark);
      expect(overlay.systemNavigationBarContrastEnforced, isFalse);
      expect(overlay.systemStatusBarContrastEnforced, isFalse);
    });

    test('AppTheme.dark sets transparent system overlay with light icons', () {
      final theme = AppTheme.dark();
      final overlay = theme.appBarTheme.systemOverlayStyle;
      expect(overlay, isNotNull);
      expect(overlay!.statusBarColor, Colors.transparent);
      expect(overlay.statusBarIconBrightness, Brightness.light);
      expect(overlay.systemNavigationBarColor, Colors.transparent);
      expect(overlay.systemNavigationBarIconBrightness, Brightness.light);
    });

    test('AppTheme.navigationBarTheme matches surface seamlessly with 0 elevation', () {
      final lightTheme = AppTheme.light();
      expect(lightTheme.navigationBarTheme.backgroundColor, lightTheme.colorScheme.surface);
      expect(lightTheme.navigationBarTheme.elevation, 0);

      final darkTheme = AppTheme.dark();
      expect(darkTheme.navigationBarTheme.backgroundColor, darkTheme.colorScheme.surface);
      expect(darkTheme.navigationBarTheme.elevation, 0);
    });

    testWidgets('AppScreen wraps content in SafeArea with left/right enabled for landscape cutouts',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppScreen(
              body: const Text('Inventory Content'),
            ),
          ),
        ),
      );

      final safeAreaFinder = find.byType(SafeArea);
      expect(safeAreaFinder, findsOneWidget);
      final safeArea = tester.widget<SafeArea>(safeAreaFinder);
      expect(safeArea.top, isFalse, reason: 'Top inset is handled by AppBar to avoid double padding');
      expect(safeArea.bottom, isFalse, reason: 'Bottom inset is handled by NavigationBar');
      expect(safeArea.left, isTrue, reason: 'Left cutout must be padded for notches/islands');
      expect(safeArea.right, isTrue, reason: 'Right cutout must be padded for notches/islands');
    });

    test('web/index.html includes viewport-fit=cover and dynamic theme-color', () {
      final indexFile = File('web/index.html');
      expect(indexFile.existsSync(), isTrue);
      final content = indexFile.readAsStringSync();

      expect(content, contains('viewport-fit=cover'));
      expect(content, contains('name="viewport"'));
      expect(content, contains('<meta name="theme-color" content="#FFFFFF" media="(prefers-color-scheme: light)">'));
      expect(content, contains('<meta name="theme-color" content="#0F172A" media="(prefers-color-scheme: dark)">'));
      expect(content.contains('#4A2C2A'), isFalse, reason: 'Legacy brown must be completely removed');
    });

    test('web/manifest.json sets clean theme_color without legacy brown', () {
      final manifestFile = File('web/manifest.json');
      expect(manifestFile.existsSync(), isTrue);
      final content = manifestFile.readAsStringSync();

      expect(content, contains('"theme_color": "#FFFFFF"'));
      expect(content.contains('#4A2C2A'), isFalse, reason: 'Legacy brown must be completely removed');
    });
  });
}
