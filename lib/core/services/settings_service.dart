import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../providers/drawing_state.dart';

/// Settings service for persisting user preferences
class SettingsService {
  static SettingsService? _instance;
  static SettingsService get instance {
    _instance ??= SettingsService._();
    return _instance!;
  }

  SettingsService._();

  String? _settingsPath;
  Map<String, dynamic> _settings = {};

  // Default favorite colors
  static const List<int> defaultFavoriteColors = [
    0xFF000000, // Black
    0xFF1976D2, // Blue
    0xFFD32F2F, // Red
    0xFF388E3C, // Green
    0xFFF57C00, // Orange
    0xFF7B1FA2, // Purple
    0xFFFFEB3B, // Yellow
  ];

  /// Initialize settings
  Future<void> initialize() async {
    final appDir = await getApplicationDocumentsDirectory();
    _settingsPath = '${appDir.path}${Platform.pathSeparator}Winote${Platform.pathSeparator}settings.json';

    final file = File(_settingsPath!);
    if (await file.exists()) {
      try {
        final jsonString = await file.readAsString();
        _settings = jsonDecode(jsonString) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('[SettingsService] Error loading settings: $e');
        _settings = {};
      }
    }

    // Set defaults if not present
    if (!_settings.containsKey('favoriteColors')) {
      _settings['favoriteColors'] = defaultFavoriteColors;
    }
    if (!_settings.containsKey('defaultPenWidth')) {
      _settings['defaultPenWidth'] = 2.0;
    }
    if (!_settings.containsKey('defaultTemplate')) {
      _settings['defaultTemplate'] = PageTemplate.grid.index;
    }
    if (!_settings.containsKey('autoSaveEnabled')) {
      _settings['autoSaveEnabled'] = true;
    }
    if (!_settings.containsKey('autoSaveDelay')) {
      _settings['autoSaveDelay'] = 3;
    }
  }

  /// Save settings to file
  Future<void> _save() async {
    if (_settingsPath == null) return;

    try {
      final file = File(_settingsPath!);
      final dir = file.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      await file.writeAsString(jsonEncode(_settings));
    } catch (e) {
      debugPrint('[SettingsService] Error saving settings: $e');
    }
  }

  // Favorite Colors
  List<Color> get favoriteColors {
    final colorInts = _settings['favoriteColors'] as List<dynamic>? ?? defaultFavoriteColors;
    return colorInts.map((c) => Color(c as int)).toList();
  }

  Future<void> setFavoriteColors(List<Color> colors) async {
    _settings['favoriteColors'] = colors.map((c) => c.value).toList();
    await _save();
  }

  Future<void> addFavoriteColor(Color color) async {
    final colors = List<int>.from(_settings['favoriteColors'] as List<dynamic>);
    if (!colors.contains(color.value)) {
      colors.add(color.value);
      _settings['favoriteColors'] = colors;
      await _save();
    }
  }

  Future<void> removeFavoriteColor(Color color) async {
    final colors = List<int>.from(_settings['favoriteColors'] as List<dynamic>);
    colors.remove(color.value);
    _settings['favoriteColors'] = colors;
    await _save();
  }

  // Default Pen Width
  double get defaultPenWidth => (_settings['defaultPenWidth'] as num?)?.toDouble() ?? 2.0;

  Future<void> setDefaultPenWidth(double width) async {
    _settings['defaultPenWidth'] = width;
    await _save();
  }

  // Default Template
  PageTemplate get defaultTemplate {
    final index = _settings['defaultTemplate'] as int? ?? PageTemplate.grid.index;
    return PageTemplate.values[index];
  }

  Future<void> setDefaultTemplate(PageTemplate template) async {
    _settings['defaultTemplate'] = template.index;
    await _save();
  }

  // Auto Save
  bool get autoSaveEnabled => _settings['autoSaveEnabled'] as bool? ?? true;

  Future<void> setAutoSaveEnabled(bool enabled) async {
    _settings['autoSaveEnabled'] = enabled;
    await _save();
  }

  int get autoSaveDelay => _settings['autoSaveDelay'] as int? ?? 3;

  Future<void> setAutoSaveDelay(int seconds) async {
    _settings['autoSaveDelay'] = seconds;
    await _save();
  }

  // Recent colors (last used colors, auto-managed)
  List<Color> get recentColors {
    final colorInts = _settings['recentColors'] as List<dynamic>? ?? [];
    return colorInts.map((c) => Color(c as int)).toList();
  }

  Future<void> addRecentColor(Color color) async {
    var colors = List<int>.from(_settings['recentColors'] as List<dynamic>? ?? []);
    colors.remove(color.value); // Remove if exists
    colors.insert(0, color.value); // Add to front
    if (colors.length > 10) {
      colors = colors.sublist(0, 10); // Keep only last 10
    }
    _settings['recentColors'] = colors;
    await _save();
  }
}
