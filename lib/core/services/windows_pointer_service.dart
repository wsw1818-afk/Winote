import 'dart:io';
import 'package:flutter/services.dart';

/// Windows Pointer Type constants
/// From WinUser.h: PT_POINTER = 1, PT_TOUCH = 2, PT_PEN = 3, PT_MOUSE = 4, PT_TOUCHPAD = 5
enum WindowsPointerType {
  pointer(1),
  touch(2),
  pen(3), // S-Pen, stylus
  mouse(4),
  touchpad(5),
  unknown(0);

  final int value;
  const WindowsPointerType(this.value);

  static WindowsPointerType fromValue(int value) {
    return WindowsPointerType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => WindowsPointerType.unknown,
    );
  }
}

/// Pointer info received from native Windows API
class PointerInfo {
  final int pointerId;
  final WindowsPointerType type;
  final int pressure; // 0-1024 for pen
  final DateTime timestamp;

  PointerInfo({
    required this.pointerId,
    required this.type,
    required this.pressure,
    required this.timestamp,
  });

  bool get isPen => type == WindowsPointerType.pen;
  bool get isTouch => type == WindowsPointerType.touch;
}

/// Service to detect pointer type using Windows native API via MethodChannel
/// This receives pointer type info from C++ before Flutter processes the event
class WindowsPointerService {
  static WindowsPointerService? _instance;
  static WindowsPointerService get instance {
    _instance ??= WindowsPointerService._();
    return _instance!;
  }

  WindowsPointerService._();

  static const _channel = MethodChannel('winote/pointer_type');

  bool _initialized = false;
  bool _available = false;

  // Cache of pointer types (Windows pointer ID -> PointerInfo)
  // Windows pointer IDs are different from Flutter pointer IDs!
  final Map<int, PointerInfo> _pointerCache = {};

  // Recent pointer events (for matching with Flutter events)
  final List<PointerInfo> _recentPointers = [];
  static const _maxRecentPointers = 20;

  /// Initialize the service and setup MethodChannel handler
  void initialize() {
    if (_initialized) return;
    _initialized = true;

    if (!Platform.isWindows) {
      _available = false;
      print('[WindowsPointerService] Not Windows platform');
      return;
    }

    _channel.setMethodCallHandler(_handleMethodCall);
    _available = true;
    print('[WindowsPointerService] MethodChannel initialized');
  }

  /// Handle method calls from native C++
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onPointerTypeDetected') {
      final args = call.arguments as Map<Object?, Object?>;
      final pointerId = args['pointerId'] as int;
      final pointerType = args['pointerType'] as int;
      final pressure = args['pressure'] as int;

      final info = PointerInfo(
        pointerId: pointerId,
        type: WindowsPointerType.fromValue(pointerType),
        pressure: pressure,
        timestamp: DateTime.now(),
      );

      // Cache by Windows pointer ID
      _pointerCache[pointerId] = info;

      // Add to recent list (for time-based matching)
      _recentPointers.add(info);
      if (_recentPointers.length > _maxRecentPointers) {
        _recentPointers.removeAt(0);
      }

      print('[WindowsPointerService] Received: pointer=$pointerId, '
          'type=${info.type.name}, pressure=$pressure');
    }
    return null;
  }

  /// Check if the service is available
  bool get isAvailable => _available;

  /// Get the most recent pointer type
  /// Since Flutter pointer IDs differ from Windows IDs,
  /// we use the most recent DOWN event within a time window
  WindowsPointerType? getMostRecentPointerType() {
    if (_recentPointers.isEmpty) return null;

    // Get most recent pointer within last 100ms
    final now = DateTime.now();
    for (int i = _recentPointers.length - 1; i >= 0; i--) {
      final info = _recentPointers[i];
      final age = now.difference(info.timestamp).inMilliseconds;
      if (age < 100) {
        return info.type;
      }
    }
    return null;
  }

  /// Get the most recent pointer info
  PointerInfo? getMostRecentPointerInfo() {
    if (_recentPointers.isEmpty) return null;

    final now = DateTime.now();
    for (int i = _recentPointers.length - 1; i >= 0; i--) {
      final info = _recentPointers[i];
      final age = now.difference(info.timestamp).inMilliseconds;
      if (age < 100) {
        return info;
      }
    }
    return null;
  }

  /// Get the most recent pen pressure (normalized 0.0 - 1.0)
  /// Returns null if no pen data available
  double? getMostRecentPressure() {
    final info = getMostRecentPointerInfo();
    if (info == null || info.type != WindowsPointerType.pen) return null;
    // Windows pen pressure is 0-1024, normalize to 0.0-1.0
    return (info.pressure / 1024.0).clamp(0.0, 1.0);
  }

  /// Check if the most recent pointer is a pen (S-Pen)
  bool isMostRecentPen() {
    final type = getMostRecentPointerType();
    return type == WindowsPointerType.pen;
  }

  /// Check if the most recent pointer is touch (finger)
  bool isMostRecentTouch() {
    final type = getMostRecentPointerType();
    return type == WindowsPointerType.touch;
  }

  /// Get cached pointer type by Windows pointer ID
  WindowsPointerType? getPointerType(int windowsPointerId) {
    return _pointerCache[windowsPointerId]?.type;
  }

  /// Clear old cache entries (call periodically)
  void cleanupCache() {
    final now = DateTime.now();
    _pointerCache.removeWhere((_, info) {
      return now.difference(info.timestamp).inSeconds > 5;
    });
    _recentPointers.removeWhere((info) {
      return now.difference(info.timestamp).inSeconds > 1;
    });
  }
}
