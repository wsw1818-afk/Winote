import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../../../domain/entities/stroke.dart';
import '../../../domain/entities/stroke_point.dart';
import '../../../core/services/windows_pointer_service.dart';

/// Drawing Canvas Widget
/// Phase 0 PoC: Receives touch/pen input and draws on screen
/// Palm Rejection: Only first pointer is allowed to draw
class DrawingCanvas extends StatefulWidget {
  final Color strokeColor;
  final double strokeWidth;
  final ToolType toolType;
  final void Function(List<Stroke>)? onStrokesChanged;
  final bool showDebugOverlay;

  const DrawingCanvas({
    super.key,
    this.strokeColor = Colors.black,
    this.strokeWidth = 2.0,
    this.toolType = ToolType.pen,
    this.onStrokesChanged,
    this.showDebugOverlay = true,
  });

  @override
  DrawingCanvasState createState() => DrawingCanvasState();
}

class DrawingCanvasState extends State<DrawingCanvas> {
  final List<Stroke> _strokes = [];
  Stroke? _currentStroke;

  // Debug info
  int _inputCount = 0;
  double _lastPressure = 0.0;
  String _lastDeviceKind = '';
  double _lastVelocity = 0.0;
  bool _showDebug = true;

  // Velocity calculation
  Offset? _lastPosition;
  int? _lastTimestamp;

  // Log file
  File? _logFile;

  // Palm rejection: track first pointer only
  int? _activePointerId;

  // Windows pointer service for S-Pen detection
  final WindowsPointerService _windowsPointerService = WindowsPointerService.instance;

  @override
  void initState() {
    super.initState();
    _initLogFile();
    // Initialize Windows pointer service
    if (Platform.isWindows) {
      _windowsPointerService.initialize();
    }
  }

  Future<void> _initLogFile() async {
    try {
      // Windows desktop path
      final homeDir = Platform.environment['USERPROFILE'] ?? '';
      final desktopPath = '$homeDir\\Desktop';
      final logPath = '$desktopPath\\winote_log.txt';

      _logFile = File(logPath);

      // Initialize log file
      final now = DateTime.now();
      await _logFile!.writeAsString(
        '=== Winote Input Log ===\n'
        'Start: ${now.toString()}\n'
        'Platform: ${Platform.operatingSystem}\n'
        'Palm Rejection: First pointer only\n'
        '---\n\n',
      );

      _log('Log file initialized: $logPath');
    } catch (e) {
      debugPrint('Log file init failed: $e');
    }
  }

  Future<void> _log(String message) async {
    final timestamp = DateTime.now().toString().substring(11, 23);
    final logLine = '[$timestamp] $message';

    debugPrint(logLine);

    if (_logFile != null) {
      try {
        await _logFile!.writeAsString('$logLine\n', mode: FileMode.append);
      } catch (e) {
        debugPrint('Log write failed: $e');
      }
    }
  }

  void _logPointerEvent(String eventType, PointerEvent event, bool allowed) {
    final info = 'EVENT: $eventType | '
        'id: ${event.pointer} | '
        'kind: ${event.kind.name} | '
        'pressure: ${event.pressure.toStringAsFixed(3)} | '
        'size: ${event.size.toStringAsFixed(3)} | '
        'radiusMajor: ${event.radiusMajor.toStringAsFixed(1)} | '
        'pos: (${event.localPosition.dx.toInt()}, ${event.localPosition.dy.toInt()}) | '
        'buttons: ${event.buttons} | '
        'allowed: $allowed';
    _log(info);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Canvas background (grid paper style)
        CustomPaint(
          painter: _GridPainter(),
          size: Size.infinite,
        ),
        // Drawing area
        Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: CustomPaint(
            painter: _StrokePainter(
              strokes: _strokes,
              currentStroke: _currentStroke,
            ),
            size: Size.infinite,
          ),
        ),
        // Debug overlay (toggleable)
        if (widget.showDebugOverlay && _showDebug)
          Positioned(
            top: 8,
            left: 8,
            child: GestureDetector(
              onTap: () => setState(() => _showDebug = false),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Input: $_inputCount | Strokes: ${_strokes.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                    Text(
                      'Pressure: ${_lastPressure.toStringAsFixed(2)} | Velocity: ${_lastVelocity.toStringAsFixed(0)}',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                    Text(
                      'Device: $_lastDeviceKind',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                    const Text(
                      '(Tap to hide)',
                      style: TextStyle(color: Colors.white54, fontSize: 9),
                    ),
                  ],
                ),
              ),
            ),
          ),
        // Debug show button (when hidden)
        if (widget.showDebugOverlay && !_showDebug)
          Positioned(
            top: 8,
            left: 8,
            child: GestureDetector(
              onTap: () => setState(() => _showDebug = true),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.bug_report, color: Colors.white54, size: 16),
              ),
            ),
          ),
      ],
    );
  }

  /// Input filtering with Windows native API S-Pen detection
  /// S-Pen/stylus: allowed for drawing
  /// Finger touch: blocked (only for zoom/pan)
  ///
  /// Uses MethodChannel to receive pointer type from C++ before Flutter processes the event.
  /// The C++ code intercepts WM_POINTER messages and calls GetPointerType() to determine
  /// if the input is from a pen (PT_PEN=3) or finger touch (PT_TOUCH=2).
  bool _isAllowedInput(PointerEvent event) {
    // Stylus/pen is always allowed (Flutter detection - may work on some devices)
    if (event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus) {
      return true;
    }

    // Mouse is always allowed (for development/testing)
    if (event.kind == PointerDeviceKind.mouse) {
      return true;
    }

    // For touch events on Windows, use native API to check real pointer type
    if (event.kind == PointerDeviceKind.touch && Platform.isWindows) {
      if (!_windowsPointerService.isAvailable) {
        // Fallback: first-pointer rule (palm rejection)
        if (_activePointerId == null) {
          return true;
        }
        return event.pointer == _activePointerId;
      }

      // Check most recent pointer type from native API
      // C++ sends this info BEFORE Flutter processes the event
      final recentType = _windowsPointerService.getMostRecentPointerType();

      if (recentType != null) {
        if (recentType == WindowsPointerType.pen) {
          _log('Native API: PEN (S-Pen) detected - ALLOWED');
          return true;
        }
        if (recentType == WindowsPointerType.touch) {
          _log('Native API: TOUCH (finger) detected - BLOCKED');
          return false;
        }
      }

      // No recent info from native API, fallback to first-pointer rule
      if (_activePointerId == null) {
        return true;
      }
      return event.pointer == _activePointerId;
    }

    // Non-Windows or non-touch: use original palm rejection
    if (event.kind == PointerDeviceKind.touch) {
      if (_activePointerId == null) {
        return true;
      }
      return event.pointer == _activePointerId;
    }

    // Others (unknown, trackpad, etc.) are allowed
    return true;
  }

  void _onPointerDown(PointerDownEvent event) {
    final allowed = _isAllowedInput(event);
    _logPointerEvent('DOWN', event, allowed);

    // Ignore new touches while drawing (palm rejection)
    if (_activePointerId != null && event.pointer != _activePointerId) {
      _log('Palm rejection: pointer ${event.pointer} ignored (active: $_activePointerId)');
      setState(() {
        _lastDeviceKind = '${_getDeviceKindName(event.kind)} (ignored)';
      });
      return;
    }

    // Touch input check
    if (!allowed) {
      setState(() {
        _lastDeviceKind = '${_getDeviceKindName(event.kind)} (ignored)';
      });
      return;
    }

    // Activate first pointer
    _activePointerId = event.pointer;
    _log('Pointer activated: ${event.pointer}');

    final point = _createStrokePoint(event, 0);

    _currentStroke = Stroke(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      toolType: widget.toolType,
      color: widget.strokeColor,
      width: widget.strokeWidth,
      points: [point],
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    _lastPosition = event.localPosition;
    _lastTimestamp = DateTime.now().millisecondsSinceEpoch;

    setState(() {
      _inputCount++;
      _lastPressure = event.pressure;
      _lastDeviceKind = _getDeviceKindName(event.kind);
      _lastVelocity = 0;
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    // Ignore non-active pointers (palm rejection)
    if (_activePointerId != null && event.pointer != _activePointerId) {
      return;
    }

    final allowed = _isAllowedInput(event);

    // Log every 10th move (performance optimization)
    if (_inputCount % 10 == 0) {
      _logPointerEvent('MOVE', event, allowed);
    }

    // Ignore if touch input or no current stroke
    if (!allowed || _currentStroke == null) return;

    // Calculate velocity
    final now = DateTime.now().millisecondsSinceEpoch;
    double velocity = 0;
    if (_lastPosition != null && _lastTimestamp != null) {
      final dt = (now - _lastTimestamp!).toDouble();
      if (dt > 0) {
        final distance = (event.localPosition - _lastPosition!).distance;
        velocity = distance / dt * 1000; // pixels per second
      }
    }

    final point = _createStrokePoint(event, velocity);

    _lastPosition = event.localPosition;
    _lastTimestamp = now;

    setState(() {
      _currentStroke = _currentStroke!.copyWithNewPoint(point);
      _inputCount++;
      _lastPressure = event.pressure;
      _lastDeviceKind = _getDeviceKindName(event.kind);
      _lastVelocity = velocity;
    });
  }

  void _onPointerUp(PointerUpEvent event) {
    // Ignore non-active pointers
    if (_activePointerId != null && event.pointer != _activePointerId) {
      _log('UP ignored: pointer ${event.pointer} (active: $_activePointerId)');
      return;
    }

    _logPointerEvent('UP', event, true);
    _log('Stroke complete: ${_currentStroke?.points.length ?? 0} points');

    // Release active pointer
    _activePointerId = null;

    if (_currentStroke == null) return;

    if (_currentStroke!.points.length >= 2) {
      setState(() {
        _strokes.add(_currentStroke!);
        widget.onStrokesChanged?.call(_strokes);
      });
    }

    _currentStroke = null;
    _lastPosition = null;
    _lastTimestamp = null;
  }

  void _onPointerCancel(PointerCancelEvent event) {
    // If active pointer is cancelled, release it
    if (event.pointer == _activePointerId) {
      _activePointerId = null;
    }
    _currentStroke = null;
    _lastPosition = null;
    _lastTimestamp = null;
    setState(() {});
  }

  StrokePoint _createStrokePoint(PointerEvent event, double velocity) {
    // For mouse, simulate pressure based on velocity
    double pressure = event.pressure;
    if (event.kind == PointerDeviceKind.mouse) {
      // Faster velocity = lower pressure simulation
      // Velocity range: 0 ~ 2000 pixels/sec
      // Pressure range: 0.3 ~ 1.0
      pressure = 1.0 - (velocity / 3000).clamp(0.0, 0.7);
    }

    return StrokePoint(
      x: event.localPosition.dx,
      y: event.localPosition.dy,
      pressure: pressure,
      tilt: event.tilt,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  String _getDeviceKindName(PointerDeviceKind kind) {
    switch (kind) {
      case PointerDeviceKind.touch:
        return 'Touch';
      case PointerDeviceKind.mouse:
        return 'Mouse (pen sim)';
      case PointerDeviceKind.stylus:
        return 'Stylus';
      case PointerDeviceKind.invertedStylus:
        return 'Eraser (pen)';
      case PointerDeviceKind.trackpad:
        return 'Trackpad';
      case PointerDeviceKind.unknown:
        return 'Unknown';
    }
  }

  void clear() {
    setState(() {
      _strokes.clear();
      _currentStroke = null;
      _inputCount = 0;
    });
    widget.onStrokesChanged?.call(_strokes);
  }

  void undo() {
    if (_strokes.isEmpty) return;
    setState(() {
      _strokes.removeLast();
    });
    widget.onStrokesChanged?.call(_strokes);
  }

  void toggleDebug() {
    setState(() {
      _showDebug = !_showDebug;
    });
  }
}

/// Grid paper background painter
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withOpacity(0.15)
      ..strokeWidth = 0.5;

    const gridSize = 25.0;

    // Vertical lines
    for (double x = 0; x < size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Horizontal lines
    for (double y = 0; y < size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Stroke renderer (Catmull-Rom spline applied)
class _StrokePainter extends CustomPainter {
  final List<Stroke> strokes;
  final Stroke? currentStroke;

  _StrokePainter({
    required this.strokes,
    this.currentStroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke);
    }

    if (currentStroke != null) {
      _drawStroke(canvas, currentStroke!);
    }
  }

  void _drawStroke(Canvas canvas, Stroke stroke) {
    if (stroke.points.isEmpty) return;

    final paint = Paint()
      ..color = stroke.color
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // Single point: draw circle
    if (stroke.points.length == 1) {
      final point = stroke.points[0];
      final pressure = point.pressure.clamp(0.1, 1.0);
      paint.strokeWidth = stroke.width * (0.5 + pressure * 0.5);
      canvas.drawCircle(Offset(point.x, point.y), paint.strokeWidth / 2, paint);
      return;
    }

    // Two points: draw line
    if (stroke.points.length == 2) {
      final p0 = stroke.points[0];
      final p1 = stroke.points[1];
      final avgPressure = ((p0.pressure + p1.pressure) / 2).clamp(0.1, 1.0);
      paint.strokeWidth = stroke.width * (0.5 + avgPressure * 0.5);
      canvas.drawLine(Offset(p0.x, p0.y), Offset(p1.x, p1.y), paint);
      return;
    }

    // 3+ points: Catmull-Rom spline for smooth curves
    _drawCatmullRomSpline(canvas, stroke, paint);
  }

  void _drawCatmullRomSpline(Canvas canvas, Stroke stroke, Paint paint) {
    final points = stroke.points;

    for (int i = 0; i < points.length - 1; i++) {
      // 4 points needed for Catmull-Rom
      final p0 = i > 0 ? points[i - 1] : points[i];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = i + 2 < points.length ? points[i + 2] : points[i + 1];

      // Pressure-based thickness
      final pressure = p1.pressure.clamp(0.1, 1.0);
      paint.strokeWidth = stroke.width * (0.5 + pressure * 0.5);

      // Split segment for smoothness
      const segments = 8;
      Offset? prevPoint;

      for (int j = 0; j <= segments; j++) {
        final t = j / segments;
        final point = _catmullRom(
          Offset(p0.x, p0.y),
          Offset(p1.x, p1.y),
          Offset(p2.x, p2.y),
          Offset(p3.x, p3.y),
          t,
        );

        if (prevPoint != null) {
          canvas.drawLine(prevPoint, point, paint);
        }
        prevPoint = point;
      }
    }
  }

  /// Catmull-Rom spline interpolation
  Offset _catmullRom(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
    final t2 = t * t;
    final t3 = t2 * t;

    final x = 0.5 * ((2 * p1.dx) +
        (-p0.dx + p2.dx) * t +
        (2 * p0.dx - 5 * p1.dx + 4 * p2.dx - p3.dx) * t2 +
        (-p0.dx + 3 * p1.dx - 3 * p2.dx + p3.dx) * t3);

    final y = 0.5 * ((2 * p1.dy) +
        (-p0.dy + p2.dy) * t +
        (2 * p0.dy - 5 * p1.dy + 4 * p2.dy - p3.dy) * t2 +
        (-p0.dy + 3 * p1.dy - 3 * p2.dy + p3.dy) * t3);

    return Offset(x, y);
  }

  @override
  bool shouldRepaint(covariant _StrokePainter oldDelegate) {
    return strokes != oldDelegate.strokes ||
        currentStroke != oldDelegate.currentStroke;
  }
}
