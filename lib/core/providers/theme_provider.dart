import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/settings_service.dart';

/// Theme mode notifier for managing app theme
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(_getInitialThemeMode());

  static ThemeMode _getInitialThemeMode() {
    final index = SettingsService.instance.themeModeIndex;
    return _indexToThemeMode(index);
  }

  static ThemeMode _indexToThemeMode(int index) {
    switch (index) {
      case 1:
        return ThemeMode.light;
      case 2:
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static int _themeModeToIndex(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 1;
      case ThemeMode.dark:
        return 2;
      default:
        return 0;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await SettingsService.instance.setThemeModeIndex(_themeModeToIndex(mode));
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (ref) => ThemeModeNotifier(),
);
