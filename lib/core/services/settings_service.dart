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
    if (!_settings.containsKey('autoSyncEnabled')) {
      _settings['autoSyncEnabled'] = false; // 기본값: 비활성화
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

  // Default Eraser Width
  double get defaultEraserWidth => (_settings['defaultEraserWidth'] as num?)?.toDouble() ?? 20.0;

  Future<void> setDefaultEraserWidth(double width) async {
    _settings['defaultEraserWidth'] = width;
    await _save();
  }

  // Default Template
  PageTemplate get defaultTemplate {
    final index = _settings['defaultTemplate'] as int? ?? PageTemplate.grid.index;
    // 범위 체크: 유효하지 않은 인덱스면 기본값 반환
    if (index < 0 || index >= PageTemplate.values.length) {
      return PageTemplate.grid;
    }
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

  // Lasso Color
  Color get lassoColor => Color(_settings['lassoColor'] as int? ?? 0xFF2196F3); // Default: Blue

  Future<void> setLassoColor(Color color) async {
    _settings['lassoColor'] = color.value;
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

  // Theme Mode (0: system, 1: light, 2: dark)
  int get themeModeIndex => _settings['themeMode'] as int? ?? 0;

  Future<void> setThemeModeIndex(int index) async {
    _settings['themeMode'] = index;
    await _save();
  }

  // Debug Overlay
  bool get showDebugOverlay => _settings['showDebugOverlay'] as bool? ?? false;

  Future<void> setShowDebugOverlay(bool show) async {
    _settings['showDebugOverlay'] = show;
    await _save();
  }

  // Two-finger gesture mode: 'zoom' (default) or 'scroll'
  String get twoFingerGestureMode => _settings['twoFingerGestureMode'] as String? ?? 'zoom';

  Future<void> setTwoFingerGestureMode(String mode) async {
    _settings['twoFingerGestureMode'] = mode;
    await _save();
  }

  // Palm rejection (손바닥 무시)
  bool get palmRejectionEnabled => _settings['palmRejectionEnabled'] as bool? ?? true;

  Future<void> setPalmRejectionEnabled(bool enabled) async {
    _settings['palmRejectionEnabled'] = enabled;
    await _save();
  }

  // Palm rejection grace period (펜 사용 후 터치 무시 시간, 밀리초)
  // 500 = 짧게 (빠른 전환)
  // 1000 = 보통 (기본값)
  // 2000 = 길게 (안전한 손바닥 무시)
  int get palmRejectionGracePeriod => _settings['palmRejectionGracePeriod'] as int? ?? 1000;

  Future<void> setPalmRejectionGracePeriod(int milliseconds) async {
    _settings['palmRejectionGracePeriod'] = milliseconds.clamp(200, 3000);
    await _save();
  }

  // Touch drawing enabled (손으로 그리기 허용)
  bool get touchDrawingEnabled => _settings['touchDrawingEnabled'] as bool? ?? false;

  Future<void> setTouchDrawingEnabled(bool enabled) async {
    _settings['touchDrawingEnabled'] = enabled;
    await _save();
  }

  // Shape snap enabled (도형 각도 스냅)
  bool get shapeSnapEnabled => _settings['shapeSnapEnabled'] as bool? ?? true;

  Future<void> setShapeSnapEnabled(bool enabled) async {
    _settings['shapeSnapEnabled'] = enabled;
    await _save();
  }

  // Shape snap angle (스냅 각도 단위, 기본 15도)
  double get shapeSnapAngle => (_settings['shapeSnapAngle'] as num?)?.toDouble() ?? 15.0;

  Future<void> setShapeSnapAngle(double angle) async {
    _settings['shapeSnapAngle'] = angle;
    await _save();
  }

  // Auto Sync (자동 클라우드 동기화)
  bool get autoSyncEnabled => _settings['autoSyncEnabled'] as bool? ?? false;

  Future<void> setAutoSyncEnabled(bool enabled) async {
    _settings['autoSyncEnabled'] = enabled;
    await _save();
  }

  // Pen Presets (펜 프리셋, 최대 5개)
  // 각 프리셋: {name: String, color: int, width: double, toolType: String}
  List<Map<String, dynamic>> get penPresets {
    final presets = _settings['penPresets'] as List<dynamic>?;
    if (presets == null) {
      // 기본 프리셋 3개
      return [
        {'name': '검정 펜', 'color': 0xFF000000, 'width': 2.0, 'toolType': 'pen'},
        {'name': '빨강 펜', 'color': 0xFFD32F2F, 'width': 2.0, 'toolType': 'pen'},
        {'name': '파랑 형광펜', 'color': 0xFF2196F3, 'width': 15.0, 'toolType': 'highlighter'},
      ];
    }
    return presets.map((p) => Map<String, dynamic>.from(p as Map)).toList();
  }

  Future<void> setPenPresets(List<Map<String, dynamic>> presets) async {
    _settings['penPresets'] = presets;
    await _save();
  }

  Future<void> addPenPreset(Map<String, dynamic> preset) async {
    final presets = List<Map<String, dynamic>>.from(penPresets);
    if (presets.length >= 5) {
      presets.removeAt(0); // 5개 초과 시 가장 오래된 것 제거
    }
    presets.add(preset);
    await setPenPresets(presets);
  }

  Future<void> updatePenPreset(int index, Map<String, dynamic> preset) async {
    final presets = List<Map<String, dynamic>>.from(penPresets);
    if (index >= 0 && index < presets.length) {
      presets[index] = preset;
      await setPenPresets(presets);
    }
  }

  Future<void> removePenPreset(int index) async {
    final presets = List<Map<String, dynamic>>.from(penPresets);
    if (index >= 0 && index < presets.length) {
      presets.removeAt(index);
      await setPenPresets(presets);
    }
  }

  // Shape Recognition (도형 자동 인식: 직선/원)
  bool get shapeRecognitionEnabled => _settings['shapeRecognitionEnabled'] as bool? ?? false;

  Future<void> setShapeRecognitionEnabled(bool enabled) async {
    _settings['shapeRecognitionEnabled'] = enabled;
    await _save();
  }

  // 필압 민감도 (Pressure Sensitivity)
  // 0.4 = 부드러움 (가벼운 터치에 민감)
  // 0.6 = 보통 (기본값)
  // 0.8 = 강함 (힘줘야 굵어짐)
  double get pressureSensitivity => (_settings['pressureSensitivity'] as num?)?.toDouble() ?? 0.6;

  Future<void> setPressureSensitivity(double sensitivity) async {
    _settings['pressureSensitivity'] = sensitivity.clamp(0.3, 1.0);
    await _save();
  }

  // 3손가락 제스처 활성화
  bool get threeFingerGestureEnabled => _settings['threeFingerGestureEnabled'] as bool? ?? true;

  Future<void> setThreeFingerGestureEnabled(bool enabled) async {
    _settings['threeFingerGestureEnabled'] = enabled;
    await _save();
  }

  // S펜 호버 커서 표시
  bool get penHoverCursorEnabled => _settings['penHoverCursorEnabled'] as bool? ?? true;

  Future<void> setPenHoverCursorEnabled(bool enabled) async {
    _settings['penHoverCursorEnabled'] = enabled;
    await _save();
  }

  // 풀스크린 모드 (도구바 숨기기)
  bool get fullscreenModeEnabled => _settings['fullscreenModeEnabled'] as bool? ?? false;

  Future<void> setFullscreenModeEnabled(bool enabled) async {
    _settings['fullscreenModeEnabled'] = enabled;
    await _save();
  }

  // 다크 캔버스 모드 (검은 배경 + 밝은 잉크)
  bool get darkCanvasModeEnabled => _settings['darkCanvasModeEnabled'] as bool? ?? false;

  Future<void> setDarkCanvasModeEnabled(bool enabled) async {
    _settings['darkCanvasModeEnabled'] = enabled;
    await _save();
  }

  // 왼손잡이 모드 (도구바 위치 반전)
  bool get leftHandedModeEnabled => _settings['leftHandedModeEnabled'] as bool? ?? false;

  Future<void> setLeftHandedModeEnabled(bool enabled) async {
    _settings['leftHandedModeEnabled'] = enabled;
    await _save();
  }
}
