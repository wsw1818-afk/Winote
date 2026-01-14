import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../../../domain/entities/stroke.dart';
import '../../../domain/entities/stroke_point.dart';
import '../../../domain/entities/canvas_image.dart';
import '../../../domain/entities/canvas_text.dart';
import '../../../core/services/windows_pointer_service.dart';
import '../../../core/services/stroke_smoothing_service.dart';
import '../../../core/providers/drawing_state.dart';

/// Drawing Canvas Widget
/// Supports: S-Pen/finger differentiation, pressure sensitivity,
/// pen/highlighter/eraser tools, undo/redo, pinch zoom/pan
class DrawingCanvas extends StatefulWidget {
  final Color strokeColor;
  final double strokeWidth;
  final ToolType toolType;
  final DrawingTool drawingTool;
  final void Function(List<Stroke>)? onStrokesChanged;
  final bool showDebugOverlay;
  final List<Stroke>? initialStrokes;
  final void Function()? onUndo;
  final void Function()? onRedo;
  final bool canUndo;
  final bool canRedo;
  final PageTemplate pageTemplate;
  final List<CanvasImage>? initialImages;
  final void Function(List<CanvasImage>)? onImagesChanged;
  final List<CanvasText>? initialTexts;
  final void Function(List<CanvasText>)? onTextsChanged;

  const DrawingCanvas({
    super.key,
    this.strokeColor = Colors.black,
    this.strokeWidth = 2.0,
    this.toolType = ToolType.pen,
    this.drawingTool = DrawingTool.pen,
    this.onStrokesChanged,
    this.showDebugOverlay = true,
    this.initialStrokes,
    this.onUndo,
    this.onRedo,
    this.canUndo = false,
    this.canRedo = false,
    this.pageTemplate = PageTemplate.grid,
    this.initialImages,
    this.onImagesChanged,
    this.initialTexts,
    this.onTextsChanged,
  });

  @override
  DrawingCanvasState createState() => DrawingCanvasState();
}

class DrawingCanvasState extends State<DrawingCanvas> {
  List<Stroke> _strokes = [];
  Stroke? _currentStroke;

  // Undo/Redo stacks
  final List<List<Stroke>> _undoStack = [];
  final List<List<Stroke>> _redoStack = [];
  static const int _maxHistorySize = 50;

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

  // Stroke smoothing service (필기 보정)
  final StrokeSmoothingService _smoothingService = StrokeSmoothingService.instance;

  // Zoom and Pan (for finger gestures)
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  double _baseScale = 1.0;
  Offset _baseOffset = Offset.zero;
  Offset? _lastFocalPoint;

  // Multi-touch tracking for gestures
  final Map<int, Offset> _activePointers = {};
  bool _isGesturing = false;
  double _baseSpan = 1.0; // Initial distance between two fingers for pinch zoom

  // Two-finger tap detection for Undo
  int? _twoFingerTapStartTime;
  Offset? _twoFingerTapStartPos1;
  Offset? _twoFingerTapStartPos2;
  bool _twoFingerMoved = false;
  static const int _tapMaxDuration = 300; // ms
  static const double _tapMaxMovement = 30.0; // pixels

  // Palm rejection: S-Pen drawing state
  bool _isPenDrawing = false; // True when S-Pen is actively drawing
  int? _penDrawStartTime; // Time when pen started drawing

  // Auto-scroll when drawing near edge (for zoomed-in state)
  static const double _edgeScrollMargin = 60.0; // pixels from edge to trigger scroll
  static const double _edgeScrollSpeed = 8.0; // pixels per frame
  Size? _canvasSize;

  // Eraser tracking
  Offset? _lastErasePoint;

  // Lasso selection
  List<Offset> _lassoPath = [];
  Set<String> _selectedStrokeIds = {};
  bool _isDraggingSelection = false;
  Offset? _selectionDragStart;
  Offset _selectionOffset = Offset.zero;

  // Images on canvas
  List<CanvasImage> _images = [];
  final Map<String, ui.Image> _loadedImages = {};
  String? _selectedImageId;
  bool _isDraggingImage = false;
  Offset? _imageDragStart;
  bool _isResizingImage = false;
  String? _resizeCorner; // 'tl', 'tr', 'bl', 'br'

  // Text boxes on canvas
  List<CanvasText> _texts = [];
  String? _selectedTextId;
  bool _isDraggingText = false;
  Offset? _textDragStart;

  @override
  void initState() {
    super.initState();
    _initLogFile();
    // Initialize Windows pointer service
    if (Platform.isWindows) {
      _windowsPointerService.initialize();
    }
    // Load initial strokes if provided
    if (widget.initialStrokes != null) {
      _strokes = List.from(widget.initialStrokes!);
    }
    // Load initial images if provided
    if (widget.initialImages != null) {
      _images = List.from(widget.initialImages!);
      _loadAllImages();
    }
    // Load initial texts if provided
    if (widget.initialTexts != null) {
      _texts = List.from(widget.initialTexts!);
    }
  }

  /// Load all images from file paths
  Future<void> _loadAllImages() async {
    for (final canvasImage in _images) {
      await _loadImage(canvasImage.imagePath);
    }
    if (mounted) setState(() {});
  }

  /// Load a single image from file path
  Future<ui.Image?> _loadImage(String path) async {
    if (_loadedImages.containsKey(path)) {
      return _loadedImages[path];
    }

    try {
      final file = File(path);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      _loadedImages[path] = frame.image;
      return frame.image;
    } catch (e) {
      debugPrint('[DrawingCanvas] Error loading image: $e');
      return null;
    }
  }

  /// Save current state for undo
  void _saveState() {
    _undoStack.add(List.from(_strokes.map((s) => s.copyWith())));
    if (_undoStack.length > _maxHistorySize) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  Future<void> _initLogFile() async {
    try {
      // Windows desktop path
      final homeDir = Platform.environment['USERPROFILE'] ?? '';
      final desktopPath = '$homeDir\\Desktop';
      final logPath = '$desktopPath\\winote_log.txt';

      _logFile = File(logPath);

      // Initialize log file (sync to ensure it's created immediately)
      final now = DateTime.now();
      _logFile!.writeAsStringSync(
        '=== Winote Input Log ===\n'
        'Start: ${now.toString()}\n'
        'Platform: ${Platform.operatingSystem}\n'
        'Palm Rejection: First pointer only\n'
        '---\n\n',
      );

      print('[WINOTE] Log file created: $logPath');
    } catch (e) {
      print('[WINOTE] Log file init failed: $e');
    }
  }

  void _log(String message) {
    if (!_enableVerboseLogging) return;

    final timestamp = DateTime.now().toString().substring(11, 23);
    final logLine = '[DART $timestamp] $message\n';

    // 파일에 로그 저장 (Release 빌드에서도 확인 가능)
    _logFile?.writeAsStringSync(logLine, mode: FileMode.append);
  }

  void _perfLog(String event, {int? durationMs, String? inputType, Offset? pos}) {
    if (!_enablePerformanceLog) return;

    final now = DateTime.now();
    final timestamp = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';

    final parts = <String>[];
    parts.add('[DART $timestamp] $event');

    if (durationMs != null) {
      parts.add('${durationMs}ms');
    }
    if (inputType != null) {
      parts.add(inputType);
    }
    if (pos != null) {
      parts.add('(${pos.dx.toInt()},${pos.dy.toInt()})');
    }
    parts.add('strokes:${_strokes.length}');
    parts.add('pts:${_currentStroke?.points.length ?? 0}');
    parts.add('offset:(${_offset.dx.toInt()},${_offset.dy.toInt()})');
    parts.add('scale:${_scale.toStringAsFixed(2)}');

    // 파일에 로그 저장 (Release 빌드에서도 확인 가능)
    _logFile?.writeAsStringSync('${parts.join(' | ')}\n', mode: FileMode.append);
  }

  // Enable performance profiling log
  static const bool _enableVerboseLogging = true;  // 올가미 디버깅용
  static const bool _enablePerformanceLog = true;

  // Performance tracking
  int _frameCount = 0;
  int _lastFrameTime = 0;
  final List<int> _frameTimes = [];
  static const int _maxFrameSamples = 60;

  void _logPointerEvent(String eventType, PointerEvent event, bool allowed) {
    if (!_enableVerboseLogging) return;

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
    return LayoutBuilder(
      builder: (context, constraints) {
        _canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(
      children: [
        // Listener OUTSIDE Transform to get screen coordinates
        Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          behavior: HitTestBehavior.opaque,
          child: ClipRect(
            child: Transform(
              transform: Matrix4.identity()
                ..translate(_offset.dx, _offset.dy)
                ..scale(_scale),
              child: Stack(
                children: [
                  // Canvas background (template-based)
                  CustomPaint(
                    painter: _TemplatePainter(template: widget.pageTemplate),
                    size: Size.infinite,
                  ),
                  // Images layer
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: _ImagePainter(
                        images: _images,
                        loadedImages: _loadedImages,
                        selectedImageId: _selectedImageId,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                  // Text layer
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: _TextPainter(
                        texts: _texts,
                        selectedTextId: _selectedTextId,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                  // Drawing area with RepaintBoundary for performance
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: _StrokePainter(
                        strokes: _strokes,
                        currentStroke: _currentStroke,
                        eraserPosition: widget.drawingTool == DrawingTool.eraser ? _lastErasePoint : null,
                        eraserRadius: widget.strokeWidth / 2,
                        lassoPath: _lassoPath,
                        selectedStrokeIds: _selectedStrokeIds,
                        selectionOffset: _selectionOffset,
                        selectionBounds: _getSelectionBounds(),
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Lasso overlay - OUTSIDE RepaintBoundary for immediate updates
        if (_lassoPath.isNotEmpty && widget.drawingTool == DrawingTool.lasso)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _LassoOverlayPainter(
                  lassoPath: _lassoPath,
                  scale: _scale,
                  offset: _offset,
                ),
              ),
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
                      'Device: $_lastDeviceKind | Zoom: ${(_scale * 100).toInt()}%',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                    Text(
                      'Tool: ${widget.drawingTool.name}',
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
        // Zoom controls
        Positioned(
          bottom: 16,
          right: 16,
          child: Column(
            children: [
              _buildZoomButton(Icons.add, () => _zoom(1.2)),
              const SizedBox(height: 8),
              _buildZoomButton(Icons.remove, () => _zoom(0.8)),
              const SizedBox(height: 8),
              _buildZoomButton(Icons.center_focus_strong, _resetTransform),
            ],
          ),
        ),
      ],
    );
      },
    );
  }

  Widget _buildZoomButton(IconData icon, VoidCallback onPressed) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, size: 20),
        onPressed: onPressed,
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(),
      ),
    );
  }

  void _zoom(double factor) {
    setState(() {
      _scale = (_scale * factor).clamp(1.0, 1.5);
    });
  }

  /// Auto-scroll canvas when pen is near screen edge (while zoomed in)
  void _autoScrollIfNearEdge(Offset screenPos) {
    if (_scale <= 1.0 || _canvasSize == null) return;

    double dx = 0;
    double dy = 0;

    // Check horizontal edges
    if (screenPos.dx < _edgeScrollMargin) {
      dx = _edgeScrollSpeed; // scroll right (move canvas left in view)
    } else if (screenPos.dx > _canvasSize!.width - _edgeScrollMargin) {
      dx = -_edgeScrollSpeed; // scroll left
    }

    // Check vertical edges
    if (screenPos.dy < _edgeScrollMargin) {
      dy = _edgeScrollSpeed; // scroll down
    } else if (screenPos.dy > _canvasSize!.height - _edgeScrollMargin) {
      dy = -_edgeScrollSpeed; // scroll up
    }

    if (dx != 0 || dy != 0) {
      setState(() {
        _offset += Offset(dx, dy);
      });
    }
  }

  void _resetTransform() {
    setState(() {
      _scale = 1.0;
      _offset = Offset.zero;
    });
  }

  /// Check if input is a finger touch (for gesture handling)
  bool _isFingerTouch(PointerEvent event) {
    if (event.kind != PointerDeviceKind.touch) return false;

    if (Platform.isWindows && _windowsPointerService.isAvailable) {
      final recentType = _windowsPointerService.getMostRecentPointerType();
      final isTouch = recentType == WindowsPointerType.touch;
      _perfLog('_isFingerTouch', inputType: isTouch ? 'TOUCH' : 'PEN');
      return isTouch;
    }

    return true; // Assume touch is finger on non-Windows
  }

  /// Check if input is a pen/stylus
  bool _isPenInput(PointerEvent event) {
    // Flutter detects stylus directly
    if (event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus) {
      return true;
    }

    // Mouse for development
    if (event.kind == PointerDeviceKind.mouse) {
      return true;
    }

    // Windows touch might be pen (S-Pen)
    if (event.kind == PointerDeviceKind.touch && Platform.isWindows) {
      if (_windowsPointerService.isAvailable) {
        final recentType = _windowsPointerService.getMostRecentPointerType();
        return recentType == WindowsPointerType.pen;
      }
      // Fallback: first pointer is allowed
      return _activePointerId == null || event.pointer == _activePointerId;
    }

    return false;
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
          // Only log once per stroke (on pointer down)
          return true;
        }
        if (recentType == WindowsPointerType.touch) {
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

  /// Transform screen coordinates to canvas coordinates
  Offset _screenToCanvas(Offset screenPos) {
    return (screenPos - _offset) / _scale;
  }

  void _onPointerDown(PointerDownEvent event) {
    final startTime = DateTime.now().millisecondsSinceEpoch;

    // === 올가미 디버그: 항상 현재 도구 상태 로깅 ===
    final nativeType = _windowsPointerService.getMostRecentPointerType();
    final isFingerTouch = _isFingerTouch(event);
    final allowed = _isAllowedInput(event);
    _log('=== DOWN START === tool: ${widget.drawingTool}, isLasso: ${widget.drawingTool == DrawingTool.lasso}, isFingerTouch: $isFingerTouch, allowed: $allowed, nativeType: ${nativeType?.name ?? "null"}, eventKind: ${event.kind}');
    _logPointerEvent('DOWN', event, allowed);

    _perfLog('DOWN start', inputType: nativeType?.name ?? 'unknown', pos: event.localPosition);

    // 올가미 도구: S-Pen이 touch로 감지되어도 첫 포인터는 올가미로 처리
    // Windows에서 S-Pen은 종종 touch로 감지되므로, 올가미 도구 선택 시 첫 터치를 허용
    if (widget.drawingTool == DrawingTool.lasso && _activePointerId == null) {
      // S-Pen 또는 첫 번째 터치인 경우 올가미 도구 처리로 진행
      // (아래 올가미 처리 코드로 fall through)
      _log('=== LASSO TOOL ACTIVE === Allowing first pointer for lasso, isFingerTouch: $isFingerTouch');
    }
    // Track all finger touches for gestures (올가미 도구가 아닐 때만)
    else if (isFingerTouch) {
      _log('=== FINGER TOUCH DETECTED === Entering pan/gesture mode, NOT reaching lasso handler!');
      // PALM REJECTION: Ignore finger touches while S-Pen is drawing
      // or shortly after S-Pen was used (500ms grace period)
      if (_isPenDrawing) {
        _perfLog('FINGER IGNORED (pen drawing)', inputType: 'TOUCH', pos: event.localPosition);
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      if (_penDrawStartTime != null && (now - _penDrawStartTime!) < 500) {
        _perfLog('FINGER IGNORED (pen grace period)', inputType: 'TOUCH', pos: event.localPosition);
        return;
      }

      _activePointers[event.pointer] = event.localPosition;
      _perfLog('FINGER-PAN start', inputType: 'TOUCH', pos: event.localPosition);

      // If 2+ fingers, start gesture mode (pinch zoom + pan)
      if (_activePointers.length >= 2) {
        _isGesturing = true;
        _baseScale = _scale;
        _baseOffset = _offset;
        _baseSpan = _getGestureSpan();
        _lastFocalPoint = _getGestureFocalPoint();

        // Start two-finger tap detection
        final positions = _activePointers.values.toList();
        _twoFingerTapStartTime = DateTime.now().millisecondsSinceEpoch;
        _twoFingerTapStartPos1 = positions[0];
        _twoFingerTapStartPos2 = positions[1];
        _twoFingerMoved = false;

        _perfLog('GESTURE-ZOOM start', inputType: 'MULTI-TOUCH');
        return;
      }

      // Single finger touch - pan mode
      _lastFocalPoint = event.localPosition;
      setState(() {
        _lastDeviceKind = '${_getDeviceKindName(event.kind)} (gesture)';
      });
      return;
    }

    // Ignore new touches while drawing (palm rejection)
    if (_activePointerId != null && event.pointer != _activePointerId) {
      _log('Palm rejection: pointer ${event.pointer} ignored (active: $_activePointerId)');
      setState(() {
        _lastDeviceKind = '${_getDeviceKindName(event.kind)} (ignored)';
      });
      return;
    }

    // Touch input check (올가미 도구는 예외 - 첫 터치 허용)
    final isLassoFirstTouch = widget.drawingTool == DrawingTool.lasso && _activePointerId == null;
    if (!allowed && !isLassoFirstTouch) {
      setState(() {
        _lastDeviceKind = '${_getDeviceKindName(event.kind)} (ignored)';
      });
      return;
    }

    // Activate first pointer
    _activePointerId = event.pointer;
    _isPenDrawing = true;
    _penDrawStartTime = DateTime.now().millisecondsSinceEpoch;
    _log('Pointer activated: ${event.pointer}, currentTool: ${widget.drawingTool}, isLassoFirstTouch: $isLassoFirstTouch');

    // Handle eraser tool
    if (widget.drawingTool == DrawingTool.eraser) {
      _saveState();
      final canvasPos = _screenToCanvas(event.localPosition);
      _lastErasePoint = canvasPos;
      _eraseAt(canvasPos);
      setState(() {
        _inputCount++;
        _lastDeviceKind = 'Eraser';
      });
      return;
    }

    // Handle lasso tool
    if (widget.drawingTool == DrawingTool.lasso) {
      final canvasPos = _screenToCanvas(event.localPosition);
      _log('Lasso DOWN at $canvasPos, pointer: ${event.pointer}, activePointerId: $_activePointerId');
      _perfLog('LASSO DOWN', inputType: 'PEN', pos: event.localPosition);

      // Check if tapping inside existing selection to drag
      final bounds = _getSelectionBounds();
      if (bounds != null && bounds.contains(canvasPos)) {
        _isDraggingSelection = true;
        _selectionDragStart = canvasPos;
        _log('Lasso: Start dragging selection');
        setState(() {
          _lastDeviceKind = 'Lasso (drag)';
        });
        return;
      }

      // Start new lasso selection
      _log('Lasso: Start new selection path at $canvasPos');
      setState(() {
        _lassoPath = [canvasPos];
        _selectedStrokeIds.clear();
        _selectionOffset = Offset.zero;
        _inputCount++;
        _lastDeviceKind = 'Lasso';
      });
      _log('Lasso: _lassoPath initialized with ${_lassoPath.length} points');
      return;
    }

    // Create stroke point
    final canvasPos = _screenToCanvas(event.localPosition);
    final point = _createStrokePoint(event, 0, canvasPos);

    // Determine color based on tool
    Color strokeColor = widget.strokeColor;
    if (widget.drawingTool == DrawingTool.highlighter) {
      strokeColor = widget.strokeColor.withOpacity(0.4);
    }

    _currentStroke = Stroke(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      toolType: widget.toolType,
      color: strokeColor,
      width: widget.strokeWidth,
      points: [point],
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    _lastPosition = event.localPosition;
    _lastTimestamp = DateTime.now().millisecondsSinceEpoch;

    final duration = DateTime.now().millisecondsSinceEpoch - startTime;
    setState(() {
      _inputCount++;
      _lastPressure = event.pressure;
      _lastDeviceKind = _getDeviceKindName(event.kind);
      _lastVelocity = 0;
    });

    _perfLog('DOWN complete', durationMs: duration, inputType: 'PEN-DRAW', pos: _screenToCanvas(event.localPosition));
  }

  /// Get focal point of active gesture pointers
  Offset _getGestureFocalPoint() {
    if (_activePointers.isEmpty) return Offset.zero;
    Offset sum = Offset.zero;
    for (final pos in _activePointers.values) {
      sum += pos;
    }
    return sum / _activePointers.length.toDouble();
  }

  /// Get distance between two gesture pointers (for pinch zoom)
  double _getGestureSpan() {
    if (_activePointers.length < 2) return 1.0;
    final positions = _activePointers.values.toList();
    return (positions[0] - positions[1]).distance;
  }

  /// Erase strokes at a point
  void _eraseAt(Offset point) {
    final eraserRadius = widget.strokeWidth / 2;
    final toRemove = <Stroke>[];

    for (final stroke in _strokes) {
      for (final p in stroke.points) {
        final distance = (Offset(p.x, p.y) - point).distance;
        if (distance <= eraserRadius + stroke.width / 2) {
          toRemove.add(stroke);
          break;
        }
      }
    }

    if (toRemove.isNotEmpty) {
      for (final stroke in toRemove) {
        _strokes.remove(stroke);
      }
      widget.onStrokesChanged?.call(_strokes);
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    final moveStartTime = DateTime.now().millisecondsSinceEpoch;
    final isFingerTouch = _isFingerTouch(event);

    // === 올가미 디버그: MOVE 시작 ===
    if (widget.drawingTool == DrawingTool.lasso && _inputCount % 20 == 0) {
      _log('=== MOVE === tool: ${widget.drawingTool}, isFingerTouch: $isFingerTouch, activePointerId: $_activePointerId, pointer: ${event.pointer}');
    }

    // 올가미 도구: activePointerId와 일치하면 먼저 올가미 처리
    // (S-Pen이 touch로 감지되어도 올가미 경로 그리기 허용)
    if (widget.drawingTool == DrawingTool.lasso && event.pointer == _activePointerId) {
      final canvasPos = _screenToCanvas(event.localPosition);

      // Dragging selection
      if (_isDraggingSelection && _selectionDragStart != null) {
        setState(() {
          _selectionOffset += canvasPos - _selectionDragStart!;
          _selectionDragStart = canvasPos;
        });
        return;
      }

      // Drawing lasso path
      if (_lassoPath.isNotEmpty) {
        // Log every 5 points for debugging
        if (_lassoPath.length % 5 == 0) {
          _log('Lasso MOVE (early): adding point at $canvasPos, total ${_lassoPath.length + 1} points');
        }
        setState(() {
          _lassoPath.add(canvasPos);
          _inputCount++;
        });
      } else {
        _log('Lasso MOVE (early): _lassoPath is EMPTY! Cannot add points.');
      }
      return;
    }

    // Handle finger gesture (pan/zoom)
    if (isFingerTouch && _activePointers.containsKey(event.pointer)) {
      _activePointers[event.pointer] = event.localPosition;

      if (_isGesturing && _activePointers.length >= 2) {
        final currentFocal = _getGestureFocalPoint();
        final currentSpan = _getGestureSpan();

        // Check if fingers moved significantly (for tap vs gesture detection)
        if (_twoFingerTapStartPos1 != null && _twoFingerTapStartPos2 != null) {
          final positions = _activePointers.values.toList();
          final move1 = (positions[0] - _twoFingerTapStartPos1!).distance;
          final move2 = (positions[1] - _twoFingerTapStartPos2!).distance;
          if (move1 > _tapMaxMovement || move2 > _tapMaxMovement) {
            _twoFingerMoved = true;
          }
        }

        if (_lastFocalPoint != null && _baseSpan > 0) {
          // Calculate scale factor from pinch gesture
          final scaleFactor = currentSpan / _baseSpan;
          final newScale = (_baseScale * scaleFactor).clamp(1.0, 1.5);

          // Calculate pan delta
          final delta = currentFocal - _lastFocalPoint!;

          // Update scale and offset together for smooth zoom-pan
          // Zoom toward focal point
          final focalCanvasPos = (_lastFocalPoint! - _baseOffset) / _baseScale;
          final newOffset = currentFocal - focalCanvasPos * newScale;

          _scale = newScale;
          _offset = newOffset;

          _perfLog('PINCH-ZOOM', inputType: 'scale:${_scale.toStringAsFixed(2)}');
        }

        _lastFocalPoint = currentFocal;
        setState(() {});
        return;
      }

      // Single finger pan
      if (_activePointers.length == 1 && _lastFocalPoint != null) {
        final delta = event.localPosition - _lastFocalPoint!;
        setState(() {
          _offset += delta;
        });
        _lastFocalPoint = event.localPosition;
        // Log every 10th move for finger pan
        if (_inputCount % 10 == 0) {
          _perfLog('FINGER-PAN', inputType: 'TOUCH', pos: event.localPosition);
        }
        return;
      }

      _lastFocalPoint = event.localPosition;
      return;
    }

    // Ignore non-active pointers (palm rejection)
    if (_activePointerId != null && event.pointer != _activePointerId) {
      return;
    }

    final allowed = _isAllowedInput(event);

    // Log every 10th move (performance optimization)
    if (_inputCount % 10 == 0) {
      _logPointerEvent('MOVE', event, allowed);
    }

    // Handle eraser
    if (widget.drawingTool == DrawingTool.eraser && event.pointer == _activePointerId) {
      final canvasPos = _screenToCanvas(event.localPosition);
      _lastErasePoint = canvasPos;
      _eraseAt(canvasPos);
      setState(() {
        _inputCount++;
      });
      return;
    }

    // Handle lasso tool
    if (widget.drawingTool == DrawingTool.lasso) {
      _log('Lasso MOVE check: pointer=${event.pointer}, activePointerId=$_activePointerId, lassoPath.length=${_lassoPath.length}');

      if (event.pointer != _activePointerId) {
        _log('Lasso MOVE: pointer mismatch, ignoring');
        return;
      }

      final canvasPos = _screenToCanvas(event.localPosition);

      // Dragging selection
      if (_isDraggingSelection && _selectionDragStart != null) {
        setState(() {
          _selectionOffset += canvasPos - _selectionDragStart!;
          _selectionDragStart = canvasPos;
        });
        return;
      }

      // Drawing lasso path
      if (_lassoPath.isNotEmpty) {
        // Log every 5 points for debugging
        if (_lassoPath.length % 5 == 0) {
          _log('Lasso MOVE: adding point at $canvasPos, total ${_lassoPath.length + 1} points');
        }
        setState(() {
          _lassoPath.add(canvasPos);
          _inputCount++;
        });
      } else {
        _log('Lasso MOVE: _lassoPath is EMPTY! Cannot add points.');
      }
      return;
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

    // Auto-scroll if near edge while drawing
    _autoScrollIfNearEdge(event.localPosition);

    final canvasPos = _screenToCanvas(event.localPosition);
    final rawPoint = _createStrokePoint(event, velocity, canvasPos);

    // Apply stroke smoothing (필기 보정)
    final smoothedPoint = _smoothingService.filterPoint(
      rawPoint,
      _currentStroke!.points,
    );

    // Skip if filtered out (jitter/noise removal)
    if (smoothedPoint == null) {
      return;
    }

    _lastPosition = event.localPosition;
    _lastTimestamp = now;

    final setStateStart = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      _currentStroke = _currentStroke!.copyWithNewPoint(smoothedPoint);
      _inputCount++;
      _lastPressure = event.pressure;
      _lastDeviceKind = _getDeviceKindName(event.kind);
      _lastVelocity = velocity;
    });

    final totalDuration = DateTime.now().millisecondsSinceEpoch - moveStartTime;
    // Log every 20 moves to avoid log spam
    if (_inputCount % 20 == 0) {
      _perfLog('MOVE', durationMs: totalDuration, inputType: 'PEN-DRAW', pos: canvasPos);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    final upStartTime = DateTime.now().millisecondsSinceEpoch;
    final nativeType = _windowsPointerService.getMostRecentPointerType();
    _perfLog('UP start', inputType: nativeType?.name ?? 'unknown', pos: event.localPosition);

    // Handle finger gesture end
    if (_activePointers.containsKey(event.pointer)) {
      _activePointers.remove(event.pointer);

      // Check for two-finger tap (Undo gesture)
      if (_activePointers.isEmpty && _twoFingerTapStartTime != null) {
        final tapDuration = DateTime.now().millisecondsSinceEpoch - _twoFingerTapStartTime!;

        if (tapDuration < _tapMaxDuration && !_twoFingerMoved) {
          // Two-finger tap detected - trigger Undo
          _perfLog('TWO-FINGER TAP', inputType: 'UNDO');
          undo();
        }

        // Reset tap detection
        _twoFingerTapStartTime = null;
        _twoFingerTapStartPos1 = null;
        _twoFingerTapStartPos2 = null;
        _twoFingerMoved = false;
      }

      if (_activePointers.isEmpty) {
        _isGesturing = false;
        _lastFocalPoint = null;
        _log('Gesture mode ended');
      } else if (_activePointers.length == 1) {
        // Back to single finger - update base for continued pan
        _lastFocalPoint = _activePointers.values.first;
      }
      return;
    }

    // Ignore non-active pointers
    if (_activePointerId != null && event.pointer != _activePointerId) {
      _log('UP ignored: pointer ${event.pointer} (active: $_activePointerId)');
      return;
    }

    _logPointerEvent('UP', event, true);

    // Handle eraser end
    if (widget.drawingTool == DrawingTool.eraser) {
      _activePointerId = null;
      _isPenDrawing = false;
      _lastErasePoint = null;
      setState(() {});
      return;
    }

    // Handle lasso end
    if (widget.drawingTool == DrawingTool.lasso) {
      _log('Lasso UP: ${_lassoPath.length} points in path');
      _activePointerId = null;
      _isPenDrawing = false;

      // Finished dragging - apply the move
      if (_isDraggingSelection) {
        _log('Lasso: Apply selection move');
        _applySelectionMove();
        _isDraggingSelection = false;
        _selectionDragStart = null;
        return;
      }

      // Finished drawing lasso - select strokes inside
      if (_lassoPath.length >= 3) {
        final selectedIds = <String>{};
        for (final stroke in _strokes) {
          if (_isStrokeInLasso(stroke, _lassoPath)) {
            selectedIds.add(stroke.id);
          }
        }

        _log('Lasso: Selected ${selectedIds.length} strokes');
        setState(() {
          _selectedStrokeIds = selectedIds;
          // Keep the lasso path visible until next action
        });
        _perfLog('LASSO SELECT', inputType: '${selectedIds.length} strokes');
      } else {
        // Too short lasso - clear selection
        _log('Lasso: Path too short (${_lassoPath.length} points), clearing');
        clearSelection();
      }
      return;
    }

    _log('Stroke complete: ${_currentStroke?.points.length ?? 0} points');

    // Release active pointer
    _activePointerId = null;
    _isPenDrawing = false;

    if (_currentStroke == null) return;

    if (_currentStroke!.points.length >= 2) {
      _saveState();
      setState(() {
        _strokes.add(_currentStroke!);
        widget.onStrokesChanged?.call(_strokes);
      });
    }

    final duration = DateTime.now().millisecondsSinceEpoch - upStartTime;
    _perfLog('STROKE SAVED', durationMs: duration, inputType: 'PEN');

    _currentStroke = null;
    _lastPosition = null;
    _lastTimestamp = null;
  }

  void _onPointerCancel(PointerCancelEvent event) {
    // Remove from gesture tracking
    _activePointers.remove(event.pointer);

    // If active pointer is cancelled, release it
    if (event.pointer == _activePointerId) {
      _activePointerId = null;
    }

    if (_activePointers.isEmpty) {
      _isGesturing = false;
      _lastFocalPoint = null;
    }

    _currentStroke = null;
    _lastPosition = null;
    _lastTimestamp = null;
    _lastErasePoint = null;
    setState(() {});
  }

  StrokePoint _createStrokePoint(PointerEvent event, double velocity, [Offset? canvasPos]) {
    double pressure = event.pressure;

    // On Windows, use native API pressure for pen input
    if (Platform.isWindows && _windowsPointerService.isAvailable) {
      final nativePressure = _windowsPointerService.getMostRecentPressure();
      if (nativePressure != null && nativePressure > 0) {
        pressure = nativePressure;
      }
    }

    // For mouse, simulate pressure based on velocity
    if (event.kind == PointerDeviceKind.mouse) {
      // Faster velocity = lower pressure simulation
      // Velocity range: 0 ~ 2000 pixels/sec
      // Pressure range: 0.3 ~ 1.0
      pressure = 1.0 - (velocity / 3000).clamp(0.0, 0.7);
    }

    // Ensure minimum pressure for visibility
    if (pressure <= 0) {
      pressure = 0.5;
    }

    // Use canvas position if provided, otherwise use screen position
    final pos = canvasPos ?? _screenToCanvas(event.localPosition);

    return StrokePoint(
      x: pos.dx,
      y: pos.dy,
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
    if (_strokes.isEmpty) return;
    _saveState();
    setState(() {
      _strokes.clear();
      _currentStroke = null;
      _inputCount = 0;
    });
    widget.onStrokesChanged?.call(_strokes);
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(List.from(_strokes.map((s) => s.copyWith())));
    setState(() {
      _strokes = _undoStack.removeLast();
    });
    widget.onStrokesChanged?.call(_strokes);
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(List.from(_strokes.map((s) => s.copyWith())));
    setState(() {
      _strokes = _redoStack.removeLast();
    });
    widget.onStrokesChanged?.call(_strokes);
  }

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// Get selected strokes
  List<Stroke> get selectedStrokes =>
      _strokes.where((s) => _selectedStrokeIds.contains(s.id)).toList();

  /// Clear selection
  void clearSelection() {
    setState(() {
      _selectedStrokeIds.clear();
      _lassoPath.clear();
      _isDraggingSelection = false;
      _selectionDragStart = null;
      _selectionOffset = Offset.zero;
    });
  }

  /// Delete selected strokes
  void deleteSelection() {
    if (_selectedStrokeIds.isEmpty) return;
    _saveState();
    setState(() {
      _strokes.removeWhere((s) => _selectedStrokeIds.contains(s.id));
      _selectedStrokeIds.clear();
      _lassoPath.clear();
      _selectionOffset = Offset.zero;
    });
    widget.onStrokesChanged?.call(_strokes);
  }

  /// Copy selected strokes (creates duplicates offset by 20 pixels)
  void copySelection() {
    if (_selectedStrokeIds.isEmpty) return;
    _saveState();

    final selectedList = selectedStrokes;
    final newStrokes = <Stroke>[];
    final newIds = <String>{};

    for (final stroke in selectedList) {
      final newId = '${DateTime.now().millisecondsSinceEpoch}_${newStrokes.length}';
      final offsetPoints = stroke.points.map((p) => StrokePoint(
        x: p.x + 20 + _selectionOffset.dx,
        y: p.y + 20 + _selectionOffset.dy,
        pressure: p.pressure,
        tilt: p.tilt,
        timestamp: p.timestamp,
      )).toList();

      newStrokes.add(Stroke(
        id: newId,
        toolType: stroke.toolType,
        color: stroke.color,
        width: stroke.width,
        points: offsetPoints,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ));
      newIds.add(newId);
    }

    setState(() {
      _strokes.addAll(newStrokes);
      _selectedStrokeIds = newIds;
      _lassoPath.clear();
      _selectionOffset = Offset.zero;
    });
    widget.onStrokesChanged?.call(_strokes);
  }

  /// Apply movement to selected strokes
  void _applySelectionMove() {
    if (_selectedStrokeIds.isEmpty || _selectionOffset == Offset.zero) return;
    _saveState();

    setState(() {
      for (int i = 0; i < _strokes.length; i++) {
        if (_selectedStrokeIds.contains(_strokes[i].id)) {
          final stroke = _strokes[i];
          final movedPoints = stroke.points.map((p) => StrokePoint(
            x: p.x + _selectionOffset.dx,
            y: p.y + _selectionOffset.dy,
            pressure: p.pressure,
            tilt: p.tilt,
            timestamp: p.timestamp,
          )).toList();

          _strokes[i] = Stroke(
            id: stroke.id,
            toolType: stroke.toolType,
            color: stroke.color,
            width: stroke.width,
            points: movedPoints,
            timestamp: stroke.timestamp,
          );
        }
      }
      _selectionOffset = Offset.zero;
      _lassoPath.clear();
    });
    widget.onStrokesChanged?.call(_strokes);
  }

  /// Check if a point is inside the lasso polygon
  bool _isPointInLasso(Offset point, List<Offset> lasso) {
    if (lasso.length < 3) return false;

    int intersections = 0;
    for (int i = 0; i < lasso.length; i++) {
      final j = (i + 1) % lasso.length;
      final p1 = lasso[i];
      final p2 = lasso[j];

      if ((p1.dy > point.dy) != (p2.dy > point.dy)) {
        final xIntersect = (p2.dx - p1.dx) * (point.dy - p1.dy) / (p2.dy - p1.dy) + p1.dx;
        if (point.dx < xIntersect) {
          intersections++;
        }
      }
    }
    return intersections % 2 == 1;
  }

  /// Check if stroke is inside lasso selection
  bool _isStrokeInLasso(Stroke stroke, List<Offset> lasso) {
    if (stroke.points.isEmpty) return false;

    // Check if any point of the stroke is inside the lasso
    for (final point in stroke.points) {
      if (_isPointInLasso(Offset(point.x, point.y), lasso)) {
        return true;
      }
    }
    return false;
  }

  /// Get bounding rect of selected strokes
  Rect? _getSelectionBounds() {
    if (_selectedStrokeIds.isEmpty) return null;

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    for (final stroke in _strokes) {
      if (!_selectedStrokeIds.contains(stroke.id)) continue;

      for (final point in stroke.points) {
        final x = point.x + _selectionOffset.dx;
        final y = point.y + _selectionOffset.dy;
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }

    if (minX == double.infinity) return null;
    return Rect.fromLTRB(minX - 10, minY - 10, maxX + 10, maxY + 10);
  }

  void toggleDebug() {
    setState(() {
      _showDebug = !_showDebug;
    });
  }

  // ===== Image Management =====

  /// Get all images
  List<CanvasImage> get images => List.from(_images);

  /// Add an image to canvas
  Future<void> addImage(String imagePath, {Offset? position}) async {
    final image = await _loadImage(imagePath);
    if (image == null) return;

    // Calculate default size (max 300px, maintain aspect ratio)
    final aspectRatio = image.width / image.height;
    double width = math.min(image.width.toDouble(), 300);
    double height = width / aspectRatio;

    final canvasImage = CanvasImage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      imagePath: imagePath,
      position: position ?? const Offset(50, 50),
      size: Size(width, height),
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    _saveState();
    setState(() {
      _images.add(canvasImage);
      _selectedImageId = canvasImage.id;
    });
    widget.onImagesChanged?.call(_images);
  }

  /// Load images from list (for loading saved notes)
  void loadImages(List<CanvasImage> images) {
    _images = List.from(images);
    _loadAllImages();
    widget.onImagesChanged?.call(_images);
  }

  /// Delete selected image
  void deleteSelectedImage() {
    if (_selectedImageId == null) return;

    _saveState();
    setState(() {
      _images.removeWhere((img) => img.id == _selectedImageId);
      _selectedImageId = null;
    });
    widget.onImagesChanged?.call(_images);
  }

  /// Clear image selection
  void clearImageSelection() {
    setState(() {
      _selectedImageId = null;
    });
  }

  /// Check if point is on a resize handle
  String? _getResizeHandle(CanvasImage image, Offset point) {
    const handleSize = 20.0;
    final bounds = image.bounds;

    final handles = {
      'tl': bounds.topLeft,
      'tr': bounds.topRight,
      'bl': bounds.bottomLeft,
      'br': bounds.bottomRight,
    };

    for (final entry in handles.entries) {
      if ((point - entry.value).distance < handleSize) {
        return entry.key;
      }
    }
    return null;
  }

  // ===== Text Management =====

  /// Get all texts
  List<CanvasText> get texts => List.from(_texts);

  /// Add a text box to canvas
  void addTextBox({Offset? position, String? initialText}) {
    final text = CanvasText(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: initialText ?? '',
      position: position ?? const Offset(50, 50),
      fontSize: 16.0,
      color: Colors.black,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    _saveState();
    setState(() {
      _texts.add(text);
      _selectedTextId = text.id;
    });
    widget.onTextsChanged?.call(_texts);

    // Show edit dialog
    _showTextEditDialog(text);
  }

  /// Load texts from list (for loading saved notes)
  void loadTexts(List<CanvasText> texts) {
    _texts = List.from(texts);
    widget.onTextsChanged?.call(_texts);
    setState(() {});
  }

  /// Edit text content
  void _showTextEditDialog(CanvasText text) {
    final controller = TextEditingController(text: text.text);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('텍스트 입력'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: '텍스트를 입력하세요...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              // Delete if empty
              if (controller.text.isEmpty) {
                deleteSelectedText();
              }
              Navigator.pop(context);
            },
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                _updateTextContent(text.id, controller.text);
              } else {
                deleteSelectedText();
              }
              Navigator.pop(context);
            },
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  /// Update text content
  void _updateTextContent(String textId, String newContent) {
    _saveState();
    setState(() {
      final index = _texts.indexWhere((t) => t.id == textId);
      if (index >= 0) {
        _texts[index] = _texts[index].copyWith(text: newContent);
      }
    });
    widget.onTextsChanged?.call(_texts);
  }

  /// Delete selected text
  void deleteSelectedText() {
    if (_selectedTextId == null) return;

    _saveState();
    setState(() {
      _texts.removeWhere((t) => t.id == _selectedTextId);
      _selectedTextId = null;
    });
    widget.onTextsChanged?.call(_texts);
  }

  /// Clear text selection
  void clearTextSelection() {
    setState(() {
      _selectedTextId = null;
    });
  }

  /// Get text bounds for hit testing
  Rect _getTextBounds(CanvasText text) {
    // Estimate text width based on character count and font size
    final width = math.max(100.0, text.text.length * text.fontSize * 0.6);
    final height = text.fontSize * 1.5;
    return Rect.fromLTWH(text.position.dx, text.position.dy, width, height);
  }

  /// Get all strokes (for saving)
  List<Stroke> get strokes => List.from(_strokes);

  /// Load strokes (for loading)
  void loadStrokes(List<Stroke> strokes) {
    _saveState();
    setState(() {
      _strokes = List.from(strokes);
    });
    widget.onStrokesChanged?.call(_strokes);
  }
}

/// Lasso overlay painter - draws OUTSIDE RepaintBoundary for immediate updates
class _LassoOverlayPainter extends CustomPainter {
  final List<Offset> lassoPath;
  final double scale;
  final Offset offset;

  _LassoOverlayPainter({
    required this.lassoPath,
    required this.scale,
    required this.offset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (lassoPath.isEmpty) return;

    debugPrint('[LASSO OVERLAY] Drawing ${lassoPath.length} points');

    // Convert canvas coordinates to screen coordinates
    final screenPath = lassoPath.map((p) {
      return Offset(
        p.dx * scale + offset.dx,
        p.dy * scale + offset.dy,
      );
    }).toList();

    // Draw lasso path
    final paint = Paint()
      ..color = Colors.blue.withOpacity(0.6)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (screenPath.length >= 2) {
      final path = Path();
      path.moveTo(screenPath.first.dx, screenPath.first.dy);
      for (int i = 1; i < screenPath.length; i++) {
        path.lineTo(screenPath[i].dx, screenPath[i].dy);
      }
      canvas.drawPath(path, paint);
    }

    // Draw start point indicator
    final startPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;
    canvas.drawCircle(screenPath.first, 5.0, startPaint);

    // Draw current point indicator
    final currentPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    canvas.drawCircle(screenPath.last, 4.0, currentPaint);
  }

  @override
  bool shouldRepaint(_LassoOverlayPainter oldDelegate) {
    return lassoPath.length != oldDelegate.lassoPath.length ||
        scale != oldDelegate.scale ||
        offset != oldDelegate.offset;
  }
}

/// Template background painter - supports multiple page templates
class _TemplatePainter extends CustomPainter {
  final PageTemplate template;

  _TemplatePainter({this.template = PageTemplate.blank});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withOpacity(0.2)
      ..strokeWidth = 0.5;

    switch (template) {
      case PageTemplate.blank:
        // No lines, just blank
        break;

      case PageTemplate.lined:
        // Horizontal lines only (like notebook)
        const lineSpacing = 30.0;
        const marginLeft = 80.0;

        // Draw left margin line (red)
        final marginPaint = Paint()
          ..color = Colors.red.withOpacity(0.3)
          ..strokeWidth = 1.0;
        canvas.drawLine(Offset(marginLeft, 0), Offset(marginLeft, size.height), marginPaint);

        // Draw horizontal lines
        for (double y = lineSpacing; y < size.height; y += lineSpacing) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
        break;

      case PageTemplate.grid:
        // Square grid
        const gridSize = 25.0;

        for (double x = 0; x < size.width; x += gridSize) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        }
        for (double y = 0; y < size.height; y += gridSize) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
        break;

      case PageTemplate.dotted:
        // Dot grid
        const dotSpacing = 25.0;
        final dotPaint = Paint()
          ..color = Colors.grey.withOpacity(0.4)
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round;

        for (double x = dotSpacing; x < size.width; x += dotSpacing) {
          for (double y = dotSpacing; y < size.height; y += dotSpacing) {
            canvas.drawCircle(Offset(x, y), 1.0, dotPaint);
          }
        }
        break;

      case PageTemplate.cornell:
        // Cornell note-taking format
        const cueColumnWidth = 150.0;
        const summaryHeight = 120.0;
        const lineSpacing = 30.0;

        final sectionPaint = Paint()
          ..color = Colors.blue.withOpacity(0.3)
          ..strokeWidth = 2.0;

        // Vertical line for cue column
        canvas.drawLine(
          Offset(cueColumnWidth, 0),
          Offset(cueColumnWidth, size.height - summaryHeight),
          sectionPaint,
        );

        // Horizontal line for summary section
        canvas.drawLine(
          Offset(0, size.height - summaryHeight),
          Offset(size.width, size.height - summaryHeight),
          sectionPaint,
        );

        // Faint horizontal lines in note-taking area
        for (double y = lineSpacing; y < size.height - summaryHeight; y += lineSpacing) {
          canvas.drawLine(
            Offset(cueColumnWidth + 10, y),
            Offset(size.width - 10, y),
            paint,
          );
        }

        // Labels
        final textPainter = TextPainter(
          textDirection: TextDirection.ltr,
        );

        // Cue label
        textPainter.text = TextSpan(
          text: 'CUE',
          style: TextStyle(
            color: Colors.blue.withOpacity(0.4),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        );
        textPainter.layout();
        textPainter.paint(canvas, const Offset(10, 10));

        // Notes label
        textPainter.text = TextSpan(
          text: 'NOTES',
          style: TextStyle(
            color: Colors.blue.withOpacity(0.4),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(cueColumnWidth + 10, 10));

        // Summary label
        textPainter.text = TextSpan(
          text: 'SUMMARY',
          style: TextStyle(
            color: Colors.blue.withOpacity(0.4),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(10, size.height - summaryHeight + 10));
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _TemplatePainter oldDelegate) =>
      template != oldDelegate.template;
}

/// Optimized stroke renderer - draws directly without spline interpolation for performance
class _StrokePainter extends CustomPainter {
  final List<Stroke> strokes;
  final Stroke? currentStroke;
  final Offset? eraserPosition;
  final double eraserRadius;
  final List<Offset> lassoPath;
  final Set<String> selectedStrokeIds;
  final Offset selectionOffset;
  final Rect? selectionBounds;

  _StrokePainter({
    required this.strokes,
    this.currentStroke,
    this.eraserPosition,
    this.eraserRadius = 10.0,
    this.lassoPath = const [],
    this.selectedStrokeIds = const {},
    this.selectionOffset = Offset.zero,
    this.selectionBounds,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw completed strokes (non-selected first)
    for (final stroke in strokes) {
      if (!selectedStrokeIds.contains(stroke.id)) {
        _drawStrokeFast(canvas, stroke);
      }
    }

    // Draw selected strokes with offset
    for (final stroke in strokes) {
      if (selectedStrokeIds.contains(stroke.id)) {
        _drawStrokeFast(canvas, stroke, offset: selectionOffset, highlight: true);
      }
    }

    // Draw current stroke being drawn
    if (currentStroke != null) {
      _drawStrokeFast(canvas, currentStroke!);
    }

    // Draw eraser cursor
    if (eraserPosition != null) {
      final eraserPaint = Paint()
        ..color = Colors.grey.withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(eraserPosition!, eraserRadius, eraserPaint);
    }

    // Draw lasso path - only when selection is complete (selectedStrokeIds.isNotEmpty)
    // During drawing, lasso path is rendered by _LassoOverlayPainter (outside RepaintBoundary)
    if (lassoPath.isNotEmpty && selectedStrokeIds.isNotEmpty) {
      // 디버그: 선택 완료 후 올가미 경로 그리기
      debugPrint('[PAINT] Drawing completed lasso path with ${lassoPath.length} points');

      // Semi-transparent fill for selected area
      final lassoFillPaint = Paint()
        ..color = Colors.blue.withOpacity(0.08)
        ..style = PaintingStyle.fill;

      // Main lasso stroke paint
      final lassoPaint = Paint()
        ..color = Colors.blue.withOpacity(0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      // White outline for better visibility
      final lassoOutlinePaint = Paint()
        ..color = Colors.white.withOpacity(0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path();
      path.moveTo(lassoPath.first.dx, lassoPath.first.dy);
      for (int i = 1; i < lassoPath.length; i++) {
        path.lineTo(lassoPath[i].dx, lassoPath[i].dy);
      }

      if (lassoPath.length >= 3) {
        path.close();
        canvas.drawPath(path, lassoFillPaint);
      }

      canvas.drawPath(path, lassoOutlinePaint);
      canvas.drawPath(path, lassoPaint);
    }

    // Draw selection bounding box
    if (selectionBounds != null && selectedStrokeIds.isNotEmpty) {
      final boundsPaint = Paint()
        ..color = Colors.blue.withOpacity(0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      final handlePaint = Paint()
        ..color = Colors.blue
        ..style = PaintingStyle.fill;

      canvas.drawRect(selectionBounds!, boundsPaint);

      // Draw corner handles
      const handleSize = 8.0;
      final corners = [
        selectionBounds!.topLeft,
        selectionBounds!.topRight,
        selectionBounds!.bottomLeft,
        selectionBounds!.bottomRight,
      ];
      for (final corner in corners) {
        canvas.drawCircle(corner, handleSize / 2, handlePaint);
      }
    }
  }

  /// Fast stroke drawing - no spline interpolation, just direct lines
  void _drawStrokeFast(Canvas canvas, Stroke stroke, {Offset offset = Offset.zero, bool highlight = false}) {
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
      canvas.drawCircle(Offset(point.x + offset.dx, point.y + offset.dy), paint.strokeWidth / 2, paint);
      return;
    }

    // Use Path for efficient batch drawing
    final path = Path();
    final firstPoint = stroke.points.first;
    path.moveTo(firstPoint.x + offset.dx, firstPoint.y + offset.dy);

    // Calculate average pressure for consistent line width
    double totalPressure = 0;
    for (final p in stroke.points) {
      totalPressure += p.pressure;
    }
    final avgPressure = (totalPressure / stroke.points.length).clamp(0.1, 1.0);
    paint.strokeWidth = stroke.width * (0.5 + avgPressure * 0.5);

    // Draw quadratic bezier curves for smoothness (simpler than Catmull-Rom)
    for (int i = 1; i < stroke.points.length; i++) {
      final p0 = stroke.points[i - 1];
      final p1 = stroke.points[i];

      if (i < stroke.points.length - 1) {
        // Use quadratic bezier with midpoint for smooth curves
        final p2 = stroke.points[i + 1];
        final midX = (p1.x + p2.x) / 2 + offset.dx;
        final midY = (p1.y + p2.y) / 2 + offset.dy;
        path.quadraticBezierTo(p1.x + offset.dx, p1.y + offset.dy, midX, midY);
      } else {
        // Last point: just draw line
        path.lineTo(p1.x + offset.dx, p1.y + offset.dy);
      }
    }

    // Draw highlight glow for selected strokes
    if (highlight) {
      final glowPaint = Paint()
        ..color = Colors.blue.withOpacity(0.3)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..strokeWidth = paint.strokeWidth + 6;
      canvas.drawPath(path, glowPaint);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _StrokePainter oldDelegate) {
    // Only repaint if strokes actually changed
    if (currentStroke != oldDelegate.currentStroke) return true;
    if (eraserPosition != oldDelegate.eraserPosition) return true;
    if (strokes.length != oldDelegate.strokes.length) return true;
    // Reference equality check for completed strokes (they don't change)
    if (!identical(strokes, oldDelegate.strokes)) return true;
    // Lasso/selection changes
    if (lassoPath.length != oldDelegate.lassoPath.length) return true;
    if (selectedStrokeIds.length != oldDelegate.selectedStrokeIds.length) return true;
    if (selectionOffset != oldDelegate.selectionOffset) return true;
    if (selectionBounds != oldDelegate.selectionBounds) return true;
    return false;
  }
}

/// Image painter for rendering images on canvas
class _ImagePainter extends CustomPainter {
  final List<CanvasImage> images;
  final Map<String, ui.Image> loadedImages;
  final String? selectedImageId;

  _ImagePainter({
    required this.images,
    required this.loadedImages,
    this.selectedImageId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final canvasImage in images) {
      final image = loadedImages[canvasImage.imagePath];
      if (image == null) continue;

      final isSelected = canvasImage.id == selectedImageId;
      final bounds = canvasImage.bounds;

      // Draw the image
      final srcRect = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
      canvas.drawImageRect(image, srcRect, bounds, Paint());

      // Draw selection border if selected
      if (isSelected) {
        final borderPaint = Paint()
          ..color = Colors.blue
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        canvas.drawRect(bounds, borderPaint);

        // Draw resize handles
        final handlePaint = Paint()
          ..color = Colors.blue
          ..style = PaintingStyle.fill;
        final handleBorderPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;

        const handleSize = 10.0;
        final corners = [bounds.topLeft, bounds.topRight, bounds.bottomLeft, bounds.bottomRight];
        for (final corner in corners) {
          canvas.drawCircle(corner, handleSize / 2 + 2, handleBorderPaint);
          canvas.drawCircle(corner, handleSize / 2, handlePaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ImagePainter oldDelegate) {
    if (images.length != oldDelegate.images.length) return true;
    if (selectedImageId != oldDelegate.selectedImageId) return true;
    if (loadedImages.length != oldDelegate.loadedImages.length) return true;
    return false;
  }
}

/// Text painter for rendering text boxes on canvas
class _TextPainter extends CustomPainter {
  final List<CanvasText> texts;
  final String? selectedTextId;

  _TextPainter({
    required this.texts,
    this.selectedTextId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final canvasText in texts) {
      final isSelected = canvasText.id == selectedTextId;

      // Create text style
      final textStyle = TextStyle(
        fontSize: canvasText.fontSize,
        color: canvasText.color,
        fontWeight: canvasText.isBold ? FontWeight.bold : FontWeight.normal,
        fontStyle: canvasText.isItalic ? FontStyle.italic : FontStyle.normal,
      );

      // Create text painter
      final textPainter = TextPainter(
        text: TextSpan(text: canvasText.text, style: textStyle),
        textDirection: TextDirection.ltr,
        maxLines: null,
      );
      textPainter.layout(maxWidth: 500);

      // Draw text
      textPainter.paint(canvas, canvasText.position);

      // Draw selection border if selected
      if (isSelected) {
        final bounds = Rect.fromLTWH(
          canvasText.position.dx - 4,
          canvasText.position.dy - 4,
          textPainter.width + 8,
          textPainter.height + 8,
        );

        final borderPaint = Paint()
          ..color = Colors.blue
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        canvas.drawRect(bounds, borderPaint);

        // Draw grab handle
        final handlePaint = Paint()
          ..color = Colors.blue
          ..style = PaintingStyle.fill;
        canvas.drawCircle(bounds.topLeft, 6, handlePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TextPainter oldDelegate) {
    if (texts.length != oldDelegate.texts.length) return true;
    if (selectedTextId != oldDelegate.selectedTextId) return true;
    // Check if any text content changed
    for (int i = 0; i < texts.length; i++) {
      if (i >= oldDelegate.texts.length) return true;
      if (texts[i].text != oldDelegate.texts[i].text) return true;
      if (texts[i].position != oldDelegate.texts[i].position) return true;
    }
    return false;
  }
}
