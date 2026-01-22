import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../../../domain/entities/stroke.dart';
import '../../../domain/entities/stroke_point.dart';
import '../../../domain/entities/canvas_image.dart';
import '../../../domain/entities/canvas_text.dart';
import '../../../domain/entities/canvas_shape.dart';
import '../../../domain/entities/canvas_table.dart';
import '../../../core/services/windows_pointer_service.dart';
import '../../../core/services/stroke_smoothing_service.dart';
import '../../../core/providers/drawing_state.dart';

/// Drawing Canvas Widget
/// Supports: S-Pen/finger differentiation, pressure sensitivity,
/// pen/highlighter/eraser tools, undo/redo, pinch zoom/pan
class DrawingCanvas extends StatefulWidget {
  final Color strokeColor;
  final double strokeWidth;
  final Color highlighterColor; // 형광펜 전용 색상
  final double highlighterWidth; // 형광펜 전용 굵기
  final double eraserWidth;
  final double highlighterOpacity; // 형광펜 투명도
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
  final String? backgroundImagePath; // 커스텀 배경 이미지 경로
  final PageTemplate? overlayTemplate; // 배경 이미지 위에 표시할 템플릿 (lined, grid 등)
  final List<CanvasImage>? initialImages;
  final void Function(List<CanvasImage>)? onImagesChanged;
  final List<CanvasText>? initialTexts;
  final void Function(List<CanvasText>)? onTextsChanged;
  final Color lassoColor;
  final Color laserPointerColor;
  final void Function(bool hasSelection)? onImageSelectionChanged;
  final List<CanvasShape>? initialShapes;
  final void Function(List<CanvasShape>)? onShapesChanged;
  final void Function(bool hasSelection)? onShapeSelectionChanged;
  final List<CanvasTable>? initialTables;
  final void Function(List<CanvasTable>)? onTablesChanged;
  final void Function(bool hasSelection)? onTableSelectionChanged;
  final void Function(double scale, Offset offset)? onTransformChanged;
  final bool presentationHighlighterFadeEnabled;
  final double presentationHighlighterFadeSpeed; // 페이드 속도 배율 (1.0 = 기본, 2.0 = 2배 빠름)
  // 패널 닫기 콜백 (캔버스 터치 시 패널 닫기)
  final VoidCallback? onCanvasTouchStart;

  const DrawingCanvas({
    super.key,
    this.strokeColor = Colors.black,
    this.strokeWidth = 2.0,
    this.highlighterColor = const Color(0xFFFFEB3B), // 기본 노랑
    this.highlighterWidth = 20.0,
    this.eraserWidth = 20.0,
    this.highlighterOpacity = 0.4,
    this.toolType = ToolType.pen,
    this.drawingTool = DrawingTool.pen,
    this.onStrokesChanged,
    this.showDebugOverlay = false,
    this.initialStrokes,
    this.onUndo,
    this.onRedo,
    this.canUndo = false,
    this.canRedo = false,
    this.pageTemplate = PageTemplate.grid,
    this.backgroundImagePath,
    this.overlayTemplate,
    this.initialImages,
    this.onImagesChanged,
    this.initialTexts,
    this.onTextsChanged,
    this.lassoColor = const Color(0xFF2196F3), // Default: Blue
    this.laserPointerColor = Colors.red, // Default: Red
    this.onImageSelectionChanged,
    this.initialShapes,
    this.onShapesChanged,
    this.onShapeSelectionChanged,
    this.initialTables,
    this.onTablesChanged,
    this.onTableSelectionChanged,
    this.onTransformChanged,
    this.presentationHighlighterFadeEnabled = true,
    this.presentationHighlighterFadeSpeed = 1.0,
    this.onCanvasTouchStart,
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

  /// 지우개 반경 계산 (커서와 실제 지우기 반경 일치)
  double get _eraserRadius => widget.eraserWidth / 2;

  // Lasso selection
  List<Offset> _lassoPath = [];
  Set<String> _selectedStrokeIds = {};
  bool _isDraggingSelection = false;
  Offset? _selectionDragStart;
  Offset _selectionOffset = Offset.zero;

  // Background image for custom template
  ui.Image? _loadedBackgroundImage;
  String? _lastBackgroundImagePath;

  // Images on canvas
  List<CanvasImage> _images = [];
  final Map<String, ui.Image> _loadedImages = {};
  String? _selectedImageId;
  bool _isDraggingImage = false;
  Offset? _imageDragStart;
  bool _isResizingImage = false;
  String? _resizeCorner; // 'tl', 'tr', 'bl', 'br'
  bool _isRotatingImage = false;
  double? _imageRotationStart;

  // Text boxes on canvas
  List<CanvasText> _texts = [];
  String? _selectedTextId;
  bool _isDraggingText = false;
  Offset? _textDragStart;

  // Double-tap detection for text editing
  int? _lastTextTapTime;
  String? _lastTappedTextId;

  // Shape drawing (temporary while drawing)
  Offset? _shapeStartPoint;
  Offset? _shapeEndPoint;
  bool _isDrawingShape = false;

  // Editable shapes on canvas
  List<CanvasShape> _shapes = [];
  String? _selectedShapeId;
  bool _isDraggingShape = false;
  Offset? _shapeDragStart;
  int? _draggingShapeHandle; // 0 = start, 1 = end

  // Tables on canvas
  List<CanvasTable> _tables = [];
  String? _selectedTableId;
  bool _isDraggingTable = false;
  Offset? _tableDragStart;

  // Long press drag for shapes/tables (1 second hold to start drag)
  static const int _longPressDuration = 1000; // 1 second in ms
  int? _elementTapStartTime;
  Offset? _elementTapStartPos;
  String? _pendingDragElementId;
  String? _pendingDragElementType; // 'shape' or 'table'
  bool _longPressTriggered = false;
  Timer? _longPressTimer; // 롱프레스 타이머

  // 드래그 준비 상태 (타이머 발동 후, 실제 이동 전)
  String? _readyToDragTableId;
  String? _readyToDragShapeId;

  // 레이저 포인터 상태
  Offset? _laserPointerPosition;
  List<Offset> _laserPointerTrail = [];
  Timer? _laserPointerFadeTimer;
  static const int _laserPointerTrailLength = 50; // 트레일 포인트 수 (더 긴 꼬리)
  static const Duration _laserPointerFadeDuration = Duration(milliseconds: 3000); // 페이드 시간 (3초)

  // 프레젠테이션 형광펜 상태
  List<Offset> _presentationHighlighterTrail = [];
  Timer? _presentationHighlighterFadeTimer;
  double _presentationHighlighterOpacity = 1.0;
  // 선긋기 중에는 트레일 길이 제한 없음 - 선긋기 완료 후에만 fade 시작
  static const Duration _presentationHighlighterFadeDuration = Duration(milliseconds: 2500); // 2.5초 페이드 (기본)

  // 삭제 버튼 표시 상태 (1초 롱프레스 후 표시)
  String? _showDeleteButtonForTableId;
  String? _showDeleteButtonForImageId;
  static const double _deleteButtonSize = 32.0;
  static const double _deleteButtonOffset = 10.0; // 오른쪽 상단에서 떨어진 거리

  // Table cell border resize state (long press activated)
  bool _isResizingTableBorder = false;
  bool _isWaitingForResizeLongPress = false; // Waiting for long press on border (visual feedback)
  bool _isPendingResizeLongPress = false; // Touch detected, waiting for 0.5s before showing visual
  Timer? _resizeLongPressTimer;
  Timer? _resizeVisualFeedbackTimer; // Timer for 0.5s visual feedback delay
  String? _resizingTableId;
  int _resizingColumnIndex = -1; // Column index being resized (-1 = none)
  int _resizingRowIndex = -1; // Row index being resized (-1 = none)
  double _resizeStartX = 0;
  double _resizeStartY = 0;
  double _originalColumnWidth = 0;
  double _originalRowHeight = 0;
  Offset _resizeBorderStartPos = Offset.zero; // Position where border was touched
  static const Duration _resizeLongPressDuration = Duration(milliseconds: 1000); // 1 second for activation
  static const Duration _resizeVisualFeedbackDelay = Duration(milliseconds: 500); // 0.5 second for visual
  static const double _resizeMovementThreshold = 20.0; // 20px movement allowed before cancel

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
    // Load initial shapes if provided
    if (widget.initialShapes != null) {
      _shapes = List.from(widget.initialShapes!);
    }
    // Load initial tables if provided
    if (widget.initialTables != null) {
      _tables = List.from(widget.initialTables!);
    }
    // Load background image if custom template
    if (widget.pageTemplate == PageTemplate.customImage && widget.backgroundImagePath != null) {
      _loadBackgroundImage(widget.backgroundImagePath!);
    }
  }

  @override
  void didUpdateWidget(covariant DrawingCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 배경 이미지 경로가 변경되었을 때 새로 로드
    if (widget.backgroundImagePath != oldWidget.backgroundImagePath ||
        widget.pageTemplate != oldWidget.pageTemplate) {
      if (widget.pageTemplate == PageTemplate.customImage && widget.backgroundImagePath != null) {
        _loadBackgroundImage(widget.backgroundImagePath!);
      } else {
        // 커스텀 이미지가 아니면 배경 이미지 정리
        _loadedBackgroundImage?.dispose();
        _loadedBackgroundImage = null;
        _lastBackgroundImagePath = null;
      }
    }
  }

  @override
  void dispose() {
    // 모든 Timer 정리 (메모리 누수 방지)
    _longPressTimer?.cancel();
    _resizeLongPressTimer?.cancel();
    _resizeVisualFeedbackTimer?.cancel();
    _imageDeleteLongPressTimer?.cancel();
    _laserPointerFadeTimer?.cancel();
    _presentationHighlighterFadeTimer?.cancel();

    // 이미지 캐시 정리
    for (final image in _loadedImages.values) {
      image.dispose();
    }
    _loadedImages.clear();

    // 배경 이미지 정리
    _loadedBackgroundImage?.dispose();
    _loadedBackgroundImage = null;

    super.dispose();
  }

  /// 롱프레스 드래그 준비 상태 트리거 (타이머에서 호출)
  /// 실제 드래그는 onPointerMove에서 이동 감지 시 시작
  void _triggerLongPressDrag() {
    if (_longPressTriggered) return;

    _longPressTriggered = true;
    _perfLog('LONG_PRESS_READY', inputType: 'timer', pos: _elementTapStartPos ?? Offset.zero);
    _log('Long press triggered for $_pendingDragElementType: $_pendingDragElementId');

    // 펜으로 그리던 스트로크가 있으면 취소
    if (_currentStroke != null) {
      _log('Canceling current stroke for element drag');
      _currentStroke = null;
    }

    // 롱프레스 대기 중에 저장된 짧은 스트로크 삭제 (점 또는 아주 짧은 선)
    if (_elementTapStartPos != null && _strokes.isNotEmpty) {
      final tapPos = _elementTapStartPos!;
      final recentStrokesToRemove = <int>[];

      // 최근 3개 스트로크만 검사 (성능 최적화)
      final startIdx = (_strokes.length - 3).clamp(0, _strokes.length);
      for (int i = startIdx; i < _strokes.length; i++) {
        final stroke = _strokes[i];
        // 점이거나 (포인트 1~2개) 롱프레스 위치 근처의 짧은 스트로크인 경우
        if (stroke.points.length <= 3) {
          final firstPoint = stroke.points.first;
          final distance = (Offset(firstPoint.x, firstPoint.y) - tapPos).distance;
          if (distance < 50) { // 50픽셀 이내
            recentStrokesToRemove.add(i);
            _log('Removing short stroke at index $i (${stroke.points.length} points, distance: ${distance.toStringAsFixed(1)})');
          }
        }
      }

      // 역순으로 삭제 (인덱스 유지)
      for (final idx in recentStrokesToRemove.reversed) {
        _strokes.removeAt(idx);
      }
    }

    // 드래그 준비 상태만 설정 (실제 드래그는 onPointerMove에서 시작)
    if (_pendingDragElementType == 'shape') {
      setState(() {
        _readyToDragShapeId = _pendingDragElementId;
        _selectedShapeId = _pendingDragElementId;
        _lastDeviceKind = 'Shape (ready to drag)';
        _selectedTableId = null;
        _selectedImageId = null;
        _selectedTextId = null;
      });
      widget.onShapeSelectionChanged?.call(true);
    } else if (_pendingDragElementType == 'table') {
      setState(() {
        _readyToDragTableId = _pendingDragElementId;
        _selectedTableId = _pendingDragElementId;
        _lastDeviceKind = 'Table (ready to drag)';
        _selectedShapeId = null;
        _selectedImageId = null;
        _selectedTextId = null;
      });
      widget.onTableSelectionChanged?.call(true);
    }
  }

  /// Load all images from file paths (병렬 로드로 성능 최적화)
  Future<void> _loadAllImages() async {
    if (_images.isEmpty) return;

    // 이미 로드된 이미지는 제외
    final imagesToLoad = _images
        .where((img) => !_loadedImages.containsKey(img.imagePath))
        .toList();

    if (imagesToLoad.isEmpty) return;

    // 병렬 로드 (최대 5개씩 동시 로드하여 메모리 관리)
    const batchSize = 5;
    for (var i = 0; i < imagesToLoad.length; i += batchSize) {
      final batch = imagesToLoad.skip(i).take(batchSize);
      await Future.wait(
        batch.map((img) => _loadImage(img.imagePath)),
        eagerError: false, // 에러 발생해도 다른 이미지 계속 로드
      );
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

  /// Load background image for custom template
  Future<void> _loadBackgroundImage(String path) async {
    // 이미 같은 이미지가 로드되어 있으면 스킵
    if (_lastBackgroundImagePath == path && _loadedBackgroundImage != null) {
      return;
    }

    try {
      final file = File(path);
      if (!await file.exists()) {
        debugPrint('[DrawingCanvas] Background image not found: $path');
        return;
      }

      // 기존 배경 이미지 정리
      _loadedBackgroundImage?.dispose();

      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();

      if (mounted) {
        setState(() {
          _loadedBackgroundImage = frame.image;
          _lastBackgroundImagePath = path;
        });
      }
      debugPrint('[DrawingCanvas] Background image loaded: $path');
    } catch (e) {
      debugPrint('[DrawingCanvas] Error loading background image: $e');
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

      // 로그 파일 생성됨 (디버그 print 제거)
    } catch (e) {
      // 로그 파일 초기화 실패 (무시)
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

  /// Cancel resize long press waiting state and reset related variables
  void _cancelResizeLongPressState({String reason = 'cancelled'}) {
    _resizeLongPressTimer?.cancel();
    _resizeLongPressTimer = null;
    _resizeVisualFeedbackTimer?.cancel();
    _resizeVisualFeedbackTimer = null;
    _isWaitingForResizeLongPress = false;
    _isPendingResizeLongPress = false;
    _resizingTableId = null;
    _resizingColumnIndex = -1;
    _resizingRowIndex = -1;
    _resizeBorderStartPos = Offset.zero;
    _perfLog('TABLE_RESIZE_LONGPRESS_CANCELLED', inputType: reason);
  }

  /// Save current stroke if exists (used when switching to resize/drag mode)
  void _saveCurrentStrokeIfExists() {
    if (_currentStroke != null && _currentStroke!.points.length >= 2) {
      setState(() {
        _strokes.add(_currentStroke!);
      });
      _perfLog('STROKE_SAVED_BEFORE_MODE_SWITCH', inputType: 'pts=${_currentStroke!.points.length}');
      widget.onStrokesChanged?.call(_strokes);
    }
    _currentStroke = null;
  }

  // Enable performance profiling log (Release 빌드에서는 false로 유지)
  static const bool _enableVerboseLogging = false;  // 성능 최적화: 비활성화
  static const bool _enablePerformanceLog = false;  // 성능 최적화: 비활성화

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
                  // Canvas background (template-based or custom image)
                  if (widget.pageTemplate == PageTemplate.customImage && widget.backgroundImagePath != null) ...[
                    // 커스텀 배경 이미지 (15% 투명도)
                    _BackgroundImageWidget(
                      imagePath: widget.backgroundImagePath!,
                      loadedImage: _loadedBackgroundImage,
                    ),
                    // 오버레이 템플릿 (배경 이미지 위에 표시되는 줄/격자/점 등) - 강한 선으로 표시
                    if (widget.overlayTemplate != null && widget.overlayTemplate != PageTemplate.blank && widget.overlayTemplate != PageTemplate.customImage)
                      CustomPaint(
                        painter: _TemplatePainter(template: widget.overlayTemplate!, isOverlay: true),
                        size: Size.infinite,
                      ),
                  ] else
                    // 기본 템플릿 배경
                    CustomPaint(
                      painter: _TemplatePainter(template: widget.pageTemplate),
                      size: Size.infinite,
                    ),
                  // Images layer - Key 최적화: 개수만으로 Key 결정 (선택 상태는 shouldRepaint로 처리)
                  RepaintBoundary(
                    key: ValueKey('images_${_images.length}'),
                    child: CustomPaint(
                      painter: _ImagePainter(
                        images: _images,
                        loadedImages: _loadedImages,
                        selectedImageId: _selectedImageId,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                  // Shapes layer - Key 최적화: 개수만으로 Key 결정
                  RepaintBoundary(
                    key: ValueKey('shapes_${_shapes.length}'),
                    child: CustomPaint(
                      painter: _ShapePainter(
                        shapes: _shapes,
                        selectedShapeId: _selectedShapeId,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                  // Tables layer - 드래그/리사이즈 중에는 매 프레임 업데이트 필요
                  // RepaintBoundary 제거하여 실시간 렌더링 보장
                  CustomPaint(
                    painter: _TablePainter(
                      tables: _tables,
                      selectedTableId: _selectedTableId,
                      readyToDragId: _readyToDragTableId,
                      resizeWaitingTableId: (_isWaitingForResizeLongPress || _isResizingTableBorder) ? _resizingTableId : null,
                      resizeWaitingColumnIndex: _resizingColumnIndex,
                      resizeWaitingRowIndex: _resizingRowIndex,
                      isResizeActive: _isResizingTableBorder,
                    ),
                    size: Size.infinite,
                  ),
                  // Text layer - Key 최적화: 개수만으로 Key 결정
                  RepaintBoundary(
                    key: ValueKey('texts_${_texts.length}'),
                    child: CustomPaint(
                      painter: _TextPainter(
                        texts: _texts,
                        selectedTextId: _selectedTextId,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                  // Drawing area with RepaintBoundary for performance
                  // Key 최적화: 지우개 위치는 Key에서 제외하여 불필요한 rebuild 방지
                  // _StrokePainter의 shouldRepaint가 지우개 위치 변경 시 repaint만 수행
                  RepaintBoundary(
                    key: ValueKey('strokes_${_strokes.length}_${_selectedStrokeIds.length}'),
                    child: CustomPaint(
                      painter: _StrokePainter(
                        strokes: _strokes,
                        currentStroke: _currentStroke,
                        eraserPosition: widget.drawingTool == DrawingTool.eraser ? _lastErasePoint : null,
                        eraserRadius: _eraserRadius,
                        lassoPath: _lassoPath,
                        selectedStrokeIds: _selectedStrokeIds,
                        selectionOffset: _selectionOffset,
                        selectionBounds: _getSelectionBounds(),
                        lassoColor: widget.lassoColor,
                        // Shape preview
                        shapeStartPoint: _shapeStartPoint,
                        shapeEndPoint: _shapeEndPoint,
                        shapeTool: _isDrawingShape ? widget.drawingTool : null,
                        shapeColor: widget.strokeColor,
                        shapeWidth: widget.strokeWidth,
                      ),
                      isComplex: true,
                      willChange: _currentStroke != null || widget.drawingTool == DrawingTool.eraser,
                      size: Size.infinite,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Lasso overlay - OUTSIDE RepaintBoundary for immediate updates
        // Key forces rebuild when path length changes
        if (widget.drawingTool == DrawingTool.lasso && _lassoPath.isNotEmpty)
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: CustomPaint(
                key: ValueKey('lasso_overlay_${_lassoPath.length}'),
                isComplex: true,
                willChange: true,
                painter: _LassoOverlayPainter(
                  lassoPath: _lassoPath,
                  scale: _scale,
                  offset: _offset,
                  lassoColor: widget.lassoColor,
                ),
              ),
            ),
          ),
        // Laser pointer overlay
        if (_laserPointerPosition != null || _laserPointerTrail.isNotEmpty)
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: CustomPaint(
                key: ValueKey('laser_pointer_${_laserPointerTrail.length}'),
                isComplex: true,
                willChange: true,
                painter: _LaserPointerPainter(
                  position: _laserPointerPosition,
                  trail: _laserPointerTrail,
                  scale: _scale,
                  offset: _offset,
                  color: widget.laserPointerColor,
                ),
              ),
            ),
          ),
        // Presentation highlighter overlay
        if (_presentationHighlighterTrail.isNotEmpty)
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: CustomPaint(
                key: ValueKey('presentation_highlighter_${_presentationHighlighterTrail.length}_${_presentationHighlighterOpacity.toStringAsFixed(2)}'),
                isComplex: true,
                willChange: true,
                painter: _PresentationHighlighterPainter(
                  trail: _presentationHighlighterTrail,
                  scale: _scale,
                  offset: _offset,
                  color: widget.highlighterColor, // 형광펜 색상 사용
                  strokeWidth: widget.highlighterWidth, // 형광펜 굵기 사용
                  opacity: _presentationHighlighterOpacity,
                  highlighterOpacity: widget.highlighterOpacity, // 형광펜 투명도 사용
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
        // 표 삭제 버튼 (1초 롱프레스 후 표시)
        if (_showDeleteButtonForTableId != null)
          _buildDeleteButtonForTable(),
        // 이미지 삭제 버튼 (1초 롱프레스 후 표시)
        if (_showDeleteButtonForImageId != null)
          _buildDeleteButtonForImage(),
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

  /// 표 삭제 버튼 위젯 (오른쪽 상단 대각선)
  Widget _buildDeleteButtonForTable() {
    final table = _tables.where((t) => t.id == _showDeleteButtonForTableId).firstOrNull;
    if (table == null) return const SizedBox.shrink();

    // 캔버스 좌표를 화면 좌표로 변환
    final screenPos = _canvasToScreen(Offset(
      table.position.dx + table.width + _deleteButtonOffset,
      table.position.dy - _deleteButtonSize - _deleteButtonOffset,
    ));

    return Positioned(
      left: screenPos.dx - _deleteButtonSize / 2,
      top: screenPos.dy,
      child: GestureDetector(
        onTap: _deleteSelectedTable,
        child: Container(
          width: _deleteButtonSize,
          height: _deleteButtonSize,
          decoration: BoxDecoration(
            color: Colors.red,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(
            Icons.close,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }

  /// 이미지 삭제 버튼 위젯 (오른쪽 상단 대각선)
  Widget _buildDeleteButtonForImage() {
    final image = _images.where((img) => img.id == _showDeleteButtonForImageId).firstOrNull;
    if (image == null) return const SizedBox.shrink();

    // 캔버스 좌표를 화면 좌표로 변환
    final screenPos = _canvasToScreen(Offset(
      image.position.dx + image.size.width + _deleteButtonOffset,
      image.position.dy - _deleteButtonSize - _deleteButtonOffset,
    ));

    return Positioned(
      left: screenPos.dx - _deleteButtonSize / 2,
      top: screenPos.dy,
      child: GestureDetector(
        onTap: _deleteSelectedImage,
        child: Container(
          width: _deleteButtonSize,
          height: _deleteButtonSize,
          decoration: BoxDecoration(
            color: Colors.red,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(
            Icons.close,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }

  /// 선택된 표 삭제
  void _deleteSelectedTable() {
    if (_showDeleteButtonForTableId == null) return;

    _saveState();
    setState(() {
      _tables.removeWhere((t) => t.id == _showDeleteButtonForTableId);
      if (_selectedTableId == _showDeleteButtonForTableId) {
        _selectedTableId = null;
        widget.onTableSelectionChanged?.call(false);
      }
      _showDeleteButtonForTableId = null;
    });
    widget.onTablesChanged?.call(_tables);
  }

  /// 선택된 이미지 삭제
  void _deleteSelectedImage() {
    if (_showDeleteButtonForImageId == null) return;

    _saveState();
    setState(() {
      final imageToRemove = _images.where((img) => img.id == _showDeleteButtonForImageId).firstOrNull;
      if (imageToRemove != null) {
        _images.remove(imageToRemove);
        _loadedImages[imageToRemove.id]?.dispose();
        _loadedImages.remove(imageToRemove.id);
      }
      if (_selectedImageId == _showDeleteButtonForImageId) {
        _selectedImageId = null;
        widget.onImageSelectionChanged?.call(false);
      }
      _showDeleteButtonForImageId = null;
    });
    widget.onImagesChanged?.call(_images);
  }

  // 이미지 삭제 버튼 롱프레스 타이머
  Timer? _imageDeleteLongPressTimer;

  void _startImageDeleteLongPressTimer(String imageId) {
    _imageDeleteLongPressTimer?.cancel();
    _imageDeleteLongPressTimer = Timer(Duration(milliseconds: _longPressDuration), () {
      if (mounted && _selectedImageId == imageId) {
        setState(() {
          _showDeleteButtonForImageId = imageId;
        });
      }
    });
  }

  void _cancelImageDeleteLongPressTimer() {
    _imageDeleteLongPressTimer?.cancel();
    _imageDeleteLongPressTimer = null;
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

  /// 캔버스 좌표를 화면 좌표로 변환
  Offset _canvasToScreen(Offset canvasPos) {
    return canvasPos * _scale + _offset;
  }

  void _onPointerDown(PointerDownEvent event) {
    final startTime = DateTime.now().millisecondsSinceEpoch;

    // 캔버스 터치 시작 시 패널 닫기 콜백 호출
    widget.onCanvasTouchStart?.call();

    // === 올가미 디버그: 항상 현재 도구 상태 로깅 ===
    final nativeType = _windowsPointerService.getMostRecentPointerType();
    final isFingerTouch = _isFingerTouch(event);
    final allowed = _isAllowedInput(event);
    _log('=== DOWN START === tool: ${widget.drawingTool}, isLasso: ${widget.drawingTool == DrawingTool.lasso}, isFingerTouch: $isFingerTouch, allowed: $allowed, nativeType: ${nativeType?.name ?? "null"}, eventKind: ${event.kind}');
    _logPointerEvent('DOWN', event, allowed);

    _perfLog('DOWN start', inputType: nativeType?.name ?? 'unknown', pos: event.localPosition);

    // Track if finger tapped on element (set in finger touch block)
    bool tappedOnElement = false;

    // 올가미/레이저포인터/프레젠테이션형광펜 도구: S-Pen이 touch로 감지되어도 첫 포인터는 해당 도구로 처리
    // Windows에서 S-Pen은 종종 touch로 감지되므로, 이 도구들 선택 시 첫 터치를 허용
    final isSpecialTool = widget.drawingTool == DrawingTool.lasso ||
                          widget.drawingTool == DrawingTool.laserPointer ||
                          widget.drawingTool == DrawingTool.presentationHighlighter;
    if (isSpecialTool && _activePointerId == null) {
      // S-Pen 또는 첫 번째 터치인 경우 해당 도구 처리로 진행
      // (아래 도구별 처리 코드로 fall through)
      _log('=== SPECIAL TOOL ACTIVE (${widget.drawingTool}) === Allowing first pointer, isFingerTouch: $isFingerTouch');
    }
    // Track all finger touches for gestures (특수 도구가 아닐 때만)
    // 핀치 줌 시작: 첫 번째 손가락이 이미 등록된 상태에서 두 번째 손가락이 오면 PEN으로 감지되어도 추가
    // Windows에서 두 번째 손가락이 PEN으로 감지되는 문제 해결
    else if (isFingerTouch || (_activePointers.isNotEmpty && !_isPenDrawing)) {
      _log('=== FINGER TOUCH DETECTED === Checking for element tap first');
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

      // Check if finger is tapping on an element (image/text/shape/table)
      // If so, allow element manipulation instead of pan/zoom
      final canvasPosForElementCheck = _screenToCanvas(event.localPosition);

      // Check images
      for (final image in _images) {
        if (image.containsPoint(canvasPosForElementCheck)) {
          tappedOnElement = true;
          break;
        }
      }
      // Check texts
      if (!tappedOnElement) {
        for (final text in _texts) {
          if (text.containsPoint(canvasPosForElementCheck)) {
            tappedOnElement = true;
            break;
          }
        }
      }
      // Check shapes
      if (!tappedOnElement) {
        for (final shape in _shapes) {
          if (shape.containsPoint(canvasPosForElementCheck)) {
            tappedOnElement = true;
            break;
          }
        }
      }
      // Check tables (테두리 근처에서만 인식 - 2px로 더 좁게)
      if (!tappedOnElement) {
        for (final table in _tables) {
          if (table.isNearBorder(canvasPosForElementCheck, tolerance: 2.0)) {
            tappedOnElement = true;
            break;
          }
        }
      }

      // If tapped on element, skip gesture mode and let element handling code run
      if (tappedOnElement) {
        _log('Finger tapped on element, allowing element manipulation');
        // Fall through to element tap handling below
      } else {
        // No element tapped - enter pan/gesture mode
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
    }

    // Ignore new touches while drawing (palm rejection)
    if (_activePointerId != null && event.pointer != _activePointerId) {
      _log('Palm rejection: pointer ${event.pointer} ignored (active: $_activePointerId)');
      setState(() {
        _lastDeviceKind = '${_getDeviceKindName(event.kind)} (ignored)';
      });
      return;
    }

    // Touch input check (올가미/레이저포인터/프레젠테이션형광펜 도구와 요소 탭은 예외)
    final isLassoFirstTouch = widget.drawingTool == DrawingTool.lasso && _activePointerId == null;
    final isLaserPointer = widget.drawingTool == DrawingTool.laserPointer;
    final isPresentationHighlighter = widget.drawingTool == DrawingTool.presentationHighlighter;
    if (!allowed && !isLassoFirstTouch && !isLaserPointer && !isPresentationHighlighter && !tappedOnElement) {
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

    // Check if tapping on an image or text first (any tool)
    final canvasPosForHitTest = _screenToCanvas(event.localPosition);

    // 펜/하이라이터/지우개/레이저포인터/프레젠테이션형광펜/도형 도구일 때는 이미지/텍스트/도형/표 위에서도 동작 가능하도록 선택 건너뛰기
    final isDrawingOrEraserTool = widget.drawingTool == DrawingTool.pen ||
                                   widget.drawingTool == DrawingTool.highlighter ||
                                   widget.drawingTool == DrawingTool.eraser ||
                                   widget.drawingTool == DrawingTool.laserPointer ||
                                   widget.drawingTool == DrawingTool.presentationHighlighter ||
                                   _isShapeTool(widget.drawingTool);

    // Check for image tap (reversed order to select topmost) - only when NOT drawing
    if (!isDrawingOrEraserTool) {
      for (int i = _images.length - 1; i >= 0; i--) {
        final image = _images[i];
        if (image.containsPoint(canvasPosForHitTest)) {
          // Check for rotation handle first if already selected
          if (_selectedImageId == image.id && _isOnRotationHandle(image, canvasPosForHitTest)) {
            _isRotatingImage = true;
            _imageRotationStart = image.rotation;
            _imageDragStart = canvasPosForHitTest;
            setState(() {
              _lastDeviceKind = 'Image (rotate)';
            });
            return;
          }

          // Check for resize handle if already selected
          if (_selectedImageId == image.id) {
            final handle = _getResizeHandle(image, canvasPosForHitTest);
            if (handle != null) {
              _isResizingImage = true;
              _resizeCorner = handle;
              _imageDragStart = canvasPosForHitTest;
              setState(() {
                _lastDeviceKind = 'Image (resize)';
              });
              return;
            }
          }

          // Select or drag the image
          if (_selectedImageId == image.id) {
            // Start dragging
            _isDraggingImage = true;
            _imageDragStart = canvasPosForHitTest;
          } else {
            // Select the image
            setState(() {
              _selectedImageId = image.id;
              _selectedTextId = null;
              _showDeleteButtonForImageId = null; // 이전 삭제 버튼 숨기기
              _showDeleteButtonForTableId = null;
            });
            widget.onImageSelectionChanged?.call(true);
          }
          // 삭제 버튼 롱프레스 타이머 시작 (1초)
          _startImageDeleteLongPressTimer(image.id);
          setState(() {
            _lastDeviceKind = 'Image';
          });
          return;
        }
      }
    }

    // Check for text tap (with double-tap detection for editing) - only when NOT drawing
    if (!isDrawingOrEraserTool) {
      for (int i = _texts.length - 1; i >= 0; i--) {
        final text = _texts[i];
        if (text.containsPoint(canvasPosForHitTest)) {
          final now = DateTime.now().millisecondsSinceEpoch;

          // Check for double-tap (same text, within 400ms)
          if (_lastTappedTextId == text.id &&
              _lastTextTapTime != null &&
              (now - _lastTextTapTime!) < 400) {
            // Double-tap detected - show edit dialog
            _showTextEditDialog(text);
            _lastTappedTextId = null;
            _lastTextTapTime = null;
            return;
          }

          // Record tap for double-tap detection
          _lastTappedTextId = text.id;
          _lastTextTapTime = now;

          if (_selectedTextId == text.id) {
            _isDraggingText = true;
            _textDragStart = canvasPosForHitTest;
          } else {
            setState(() {
              _selectedTextId = text.id;
              _selectedImageId = null;
            });
            widget.onImageSelectionChanged?.call(false);
          }
          setState(() {
            _lastDeviceKind = 'Text';
          });
          return;
        }
      }
    }

    // Check for shape tap (with handle detection for editing) - only when NOT drawing
    if (!isDrawingOrEraserTool) {
      for (int i = _shapes.length - 1; i >= 0; i--) {
        final shape = _shapes[i];

        // Check for handle tap if already selected
        if (_selectedShapeId == shape.id) {
          final handleIndex = shape.getHandleAt(canvasPosForHitTest);
          if (handleIndex != null) {
            _isDraggingShape = true;
            _draggingShapeHandle = handleIndex;
            _shapeDragStart = canvasPosForHitTest;
            setState(() {
              _lastDeviceKind = 'Shape (handle)';
            });
            return;
          }
        }

        // Check for shape body tap
        if (shape.containsPoint(canvasPosForHitTest)) {
          // Select the shape
          setState(() {
            _selectedShapeId = shape.id;
            _selectedImageId = null;
            _selectedTextId = null;
            _selectedTableId = null;
          });
          widget.onShapeSelectionChanged?.call(true);
          widget.onImageSelectionChanged?.call(false);
          widget.onTableSelectionChanged?.call(false);

          // Setup for long press drag (wait before enabling drag)
          _longPressTimer?.cancel();
          _elementTapStartTime = DateTime.now().millisecondsSinceEpoch;
          _elementTapStartPos = canvasPosForHitTest;
          _pendingDragElementId = shape.id;
          _pendingDragElementType = 'shape';
          _longPressTriggered = false;
          _shapeDragStart = canvasPosForHitTest;

          // 1초 후 롱프레스 트리거 (타이머 사용)
          _perfLog('TIMER_START', inputType: 'select-shape:${shape.id}', pos: canvasPosForHitTest);
          _longPressTimer = Timer(Duration(milliseconds: _longPressDuration), () {
            _perfLog('TIMER_FIRED', inputType: 'pendingId=$_pendingDragElementId,triggered=$_longPressTriggered', pos: _elementTapStartPos);
            if (_pendingDragElementId != null && !_longPressTriggered && mounted) {
              _triggerLongPressDrag();
            }
          });

          setState(() {
            _lastDeviceKind = 'Shape (hold to drag)';
          });
          return;
        }
      }
    }

    // Check for table interactions - cell borders for resize, left edge for drag
    // Both require 0.5 second for visual feedback, 1 second for activation
    // NOTE: Check cell borders FIRST (tolerance: 6.0), then left edge (tolerance: 15.0)
    //       to avoid left edge capturing cell border touches
    _perfLog('TABLE_CHECK', inputType: 'tool=${widget.drawingTool}, tables=${_tables.length}', pos: canvasPosForHitTest);
    for (int i = _tables.length - 1; i >= 0; i--) {
      final table = _tables[i];

      // Check if touch is within table bounds first
      final tableRect = Rect.fromLTWH(table.position.dx, table.position.dy, table.width, table.height);
      final isInTableArea = tableRect.inflate(20).contains(canvasPosForHitTest); // 20px margin for border detection

      // First check: Column border for resize (higher priority than left edge)
      final colBorder = table.getColumnBorderAt(canvasPosForHitTest, tolerance: 6.0);
      final rowBorder = table.getRowBorderAt(canvasPosForHitTest, tolerance: 6.0);

      if (isInTableArea) {
        _perfLog('TABLE_BORDER_CHECK', inputType: 'table=$i, inArea=$isInTableArea, colBorder=$colBorder, rowBorder=$rowBorder', pos: canvasPosForHitTest);
      }

      if (colBorder >= 0) {
        // Start pending state (no visual feedback yet)
        _isPendingResizeLongPress = true;
        _resizingTableId = table.id;
        _resizingColumnIndex = colBorder;
        _resizingRowIndex = -1;
        _resizeBorderStartPos = canvasPosForHitTest;
        _originalColumnWidth = table.getColumnWidth(colBorder);
        _perfLog('TABLE_COLUMN_RESIZE_PENDING', inputType: 'col=$colBorder', pos: canvasPosForHitTest);

        // Start 0.5 second timer for visual feedback
        _resizeVisualFeedbackTimer?.cancel();
        _resizeVisualFeedbackTimer = Timer(_resizeVisualFeedbackDelay, () {
          if (_isPendingResizeLongPress && _resizingTableId != null && mounted) {
            _isWaitingForResizeLongPress = true;
            setState(() {}); // Now show visual feedback
            _perfLog('TABLE_COLUMN_RESIZE_VISUAL', inputType: 'col=$colBorder', pos: canvasPosForHitTest);
          }
        });

        // Start 1 second timer for long press activation
        _resizeLongPressTimer?.cancel();
        _resizeLongPressTimer = Timer(_resizeLongPressDuration, () {
          if (_isPendingResizeLongPress && _resizingTableId != null && mounted) {
            // Long press triggered - activate resize mode
            _isPendingResizeLongPress = false;
            _isWaitingForResizeLongPress = false;
            _isResizingTableBorder = true;
            _resizeStartX = _resizeBorderStartPos.dx;
            // Save any drawing in progress before switching to resize mode
            _saveCurrentStrokeIfExists();
            setState(() {
              _selectedTableId = _resizingTableId;
              _showDeleteButtonForTableId = _resizingTableId; // 삭제 버튼 표시
              _lastDeviceKind = 'Table (resize column - active)';
            });
            _perfLog('TABLE_COLUMN_RESIZE_ACTIVATED', inputType: 'col=$_resizingColumnIndex', pos: _resizeBorderStartPos);
          }
        });
        // Don't return - allow drawing to start, will be cancelled if long press triggers
        break;
      }

      // Second check: Row border for resize (already computed above)
      if (rowBorder >= 0) {
        // Start pending state (no visual feedback yet)
        _isPendingResizeLongPress = true;
        _resizingTableId = table.id;
        _resizingColumnIndex = -1;
        _resizingRowIndex = rowBorder;
        _resizeBorderStartPos = canvasPosForHitTest;
        _originalRowHeight = table.getRowHeight(rowBorder);
        _perfLog('TABLE_ROW_RESIZE_PENDING', inputType: 'row=$rowBorder', pos: canvasPosForHitTest);

        // Start 0.5 second timer for visual feedback
        _resizeVisualFeedbackTimer?.cancel();
        _resizeVisualFeedbackTimer = Timer(_resizeVisualFeedbackDelay, () {
          if (_isPendingResizeLongPress && _resizingTableId != null && mounted) {
            _isWaitingForResizeLongPress = true;
            setState(() {}); // Now show visual feedback
            _perfLog('TABLE_ROW_RESIZE_VISUAL', inputType: 'row=$rowBorder', pos: canvasPosForHitTest);
          }
        });

        // Start 1 second timer for long press activation
        _resizeLongPressTimer?.cancel();
        _resizeLongPressTimer = Timer(_resizeLongPressDuration, () {
          if (_isPendingResizeLongPress && _resizingTableId != null && mounted) {
            // Long press triggered - activate resize mode
            _isPendingResizeLongPress = false;
            _isWaitingForResizeLongPress = false;
            _isResizingTableBorder = true;
            _resizeStartY = _resizeBorderStartPos.dy;
            // Save any drawing in progress before switching to resize mode
            _saveCurrentStrokeIfExists();
            setState(() {
              _selectedTableId = _resizingTableId;
              _showDeleteButtonForTableId = _resizingTableId; // 삭제 버튼 표시
              _lastDeviceKind = 'Table (resize row - active)';
            });
            _perfLog('TABLE_ROW_RESIZE_ACTIVATED', inputType: 'row=$_resizingRowIndex', pos: _resizeBorderStartPos);
          }
        });
        // Don't return here - allow drawing to start if threshold not met
        break;
      }

      // Third check: Left edge for table drag (lower priority than cell borders)
      if (table.isOnLeftEdge(canvasPosForHitTest, tolerance: 2.0)) {
        // Start pending state (no visual feedback yet)
        _isPendingResizeLongPress = true;
        _resizingTableId = table.id;
        _resizingColumnIndex = -99; // Special value indicating left edge drag
        _resizingRowIndex = -1;
        _resizeBorderStartPos = canvasPosForHitTest;
        _perfLog('TABLE_LEFT_EDGE_PENDING', inputType: 'drag', pos: canvasPosForHitTest);

        // Start 0.5 second timer for visual feedback
        _resizeVisualFeedbackTimer?.cancel();
        _resizeVisualFeedbackTimer = Timer(_resizeVisualFeedbackDelay, () {
          if (_isPendingResizeLongPress && _resizingTableId != null && _resizingColumnIndex == -99 && mounted) {
            _isWaitingForResizeLongPress = true;
            setState(() {}); // Now show visual feedback
            _perfLog('TABLE_LEFT_EDGE_VISUAL', inputType: 'drag', pos: canvasPosForHitTest);
          }
        });

        // Start 1 second timer for long press activation
        _resizeLongPressTimer?.cancel();
        _resizeLongPressTimer = Timer(_resizeLongPressDuration, () {
          if (_isPendingResizeLongPress && _resizingTableId != null && _resizingColumnIndex == -99 && mounted) {
            // Long press triggered on left edge - activate drag mode
            _isPendingResizeLongPress = false;
            _isWaitingForResizeLongPress = false;
            _resizingColumnIndex = -1; // Reset special value
            // Save any drawing in progress before switching to drag mode
            _saveCurrentStrokeIfExists();
            // Setup table drag
            _isDraggingTable = true;
            _tableDragStart = _resizeBorderStartPos;
            setState(() {
              _selectedTableId = _resizingTableId;
              _showDeleteButtonForTableId = _resizingTableId; // 삭제 버튼 표시
              _lastDeviceKind = 'Table (drag from left edge)';
            });
            _perfLog('TABLE_DRAG_FROM_LEFT_EDGE_ACTIVATED', inputType: 'table=${_resizingTableId}', pos: _resizeBorderStartPos);
          }
        });
        // Don't return - allow drawing to start, will be cancelled if long press triggers
        break;
      }

      // Fourth check: Top edge for table height resize (resize upward)
      if (table.isOnTopEdge(canvasPosForHitTest, tolerance: 2.0)) {
        // Start pending state (no visual feedback yet)
        _isPendingResizeLongPress = true;
        _resizingTableId = table.id;
        _resizingColumnIndex = -1;
        _resizingRowIndex = -99; // Special value indicating top edge resize
        _resizeBorderStartPos = canvasPosForHitTest;
        _originalRowHeight = table.getRowHeight(0); // First row height
        _perfLog('TABLE_TOP_EDGE_PENDING', inputType: 'resize', pos: canvasPosForHitTest);

        // Start 0.5 second timer for visual feedback
        _resizeVisualFeedbackTimer?.cancel();
        _resizeVisualFeedbackTimer = Timer(_resizeVisualFeedbackDelay, () {
          if (_isPendingResizeLongPress && _resizingTableId != null && _resizingRowIndex == -99 && mounted) {
            _isWaitingForResizeLongPress = true;
            setState(() {}); // Now show visual feedback
            _perfLog('TABLE_TOP_EDGE_VISUAL', inputType: 'resize', pos: canvasPosForHitTest);
          }
        });

        // Start 1 second timer for long press activation
        _resizeLongPressTimer?.cancel();
        _resizeLongPressTimer = Timer(_resizeLongPressDuration, () {
          if (_isPendingResizeLongPress && _resizingTableId != null && _resizingRowIndex == -99 && mounted) {
            // Long press triggered on top edge - activate resize mode
            _isPendingResizeLongPress = false;
            _isWaitingForResizeLongPress = false;
            _isResizingTableBorder = true;
            _resizeStartY = _resizeBorderStartPos.dy;
            // Save any drawing in progress before switching to resize mode
            _saveCurrentStrokeIfExists();
            setState(() {
              _selectedTableId = _resizingTableId;
              _showDeleteButtonForTableId = _resizingTableId; // 삭제 버튼 표시
              _lastDeviceKind = 'Table (resize top edge - active)';
            });
            _perfLog('TABLE_TOP_EDGE_RESIZE_ACTIVATED', inputType: 'table=${_resizingTableId}', pos: _resizeBorderStartPos);
          }
        });
        // Don't return - allow drawing to start, will be cancelled if long press triggers
        break;
      }
    }

    // Check for table tap (selection and dragging) - only when NOT drawing
    // Skip if waiting for resize long press (border resize takes priority)
    // 셀 테두리 근처에서만 선택/드래그 인식 (셀 내부 터치는 무시)
    // ★ 1초 롱프레스 후에만 표 선택이 되도록 변경
    if (!isDrawingOrEraserTool && !_isWaitingForResizeLongPress && !_isPendingResizeLongPress) {
      debugPrint('TABLE_CHECK: tables=${_tables.length}, pos=$canvasPosForHitTest');
      for (int i = _tables.length - 1; i >= 0; i--) {
        final table = _tables[i];
        final isNear = table.isNearBorder(canvasPosForHitTest, tolerance: 2.0);
        final isInside = table.containsPoint(canvasPosForHitTest);
        debugPrint('TABLE[$i]: id=${table.id}, pos=${table.position}, isNearBorder=$isNear, containsPoint=$isInside');
        // 셀 테두리 근처에서만 인식 (tolerance: 2px로 더 좁게)
        if (isNear) {
          debugPrint('TABLE_PENDING: ${table.id} (1초 후 선택됨)');
          // ★ 즉시 선택하지 않고 pending 상태로만 설정
          // 1초 후 롱프레스 시에만 선택됨

          // Setup for long press drag (wait before enabling drag)
          _longPressTimer?.cancel();
          _elementTapStartTime = DateTime.now().millisecondsSinceEpoch;
          _elementTapStartPos = canvasPosForHitTest;
          _pendingDragElementId = table.id;
          _pendingDragElementType = 'table';
          _longPressTriggered = false;
          _tableDragStart = canvasPosForHitTest;

          // 1초 후 롱프레스 트리거 (타이머 사용) - 선택, 드래그 및 삭제 버튼 표시
          debugPrint('TABLE_TIMER_START: tableId=${table.id}, duration=${_longPressDuration}ms');
          _perfLog('TIMER_START', inputType: 'select-table:${table.id}', pos: canvasPosForHitTest);
          final tableIdForTimer = table.id; // 클로저에서 사용할 ID 저장
          _longPressTimer = Timer(Duration(milliseconds: _longPressDuration), () {
            debugPrint('TABLE_TIMER_FIRED: pendingId=$_pendingDragElementId, triggered=$_longPressTriggered, mounted=$mounted');
            _perfLog('TIMER_FIRED', inputType: 'pendingId=$_pendingDragElementId,triggered=$_longPressTriggered', pos: _elementTapStartPos);
            if (_pendingDragElementId != null && !_longPressTriggered && mounted) {
              debugPrint('TABLE_SELECTED_AFTER_1SEC: $tableIdForTimer');
              // ★ 1초 후에 선택 상태로 변경
              setState(() {
                _selectedTableId = tableIdForTimer;
                _selectedImageId = null;
                _selectedTextId = null;
                _selectedShapeId = null;
                _showDeleteButtonForTableId = tableIdForTimer;
                _showDeleteButtonForImageId = null;
              });
              widget.onTableSelectionChanged?.call(true);
              widget.onImageSelectionChanged?.call(false);
              widget.onShapeSelectionChanged?.call(false);
              _triggerLongPressDrag();
            }
          });

          setState(() {
            _lastDeviceKind = 'Table border (hold 1s to select)';
          });
          return;
        }
      }
    }

    // Clear selections if tapping elsewhere
    if (_selectedImageId != null || _selectedTextId != null || _selectedShapeId != null || _selectedTableId != null) {
      setState(() {
        _selectedImageId = null;
        _selectedTextId = null;
        _selectedShapeId = null;
        _selectedTableId = null;
        _showDeleteButtonForTableId = null; // 삭제 버튼 숨기기
        _showDeleteButtonForImageId = null;
      });
      _cancelImageDeleteLongPressTimer();
      widget.onImageSelectionChanged?.call(false);
      widget.onShapeSelectionChanged?.call(false);
      widget.onTableSelectionChanged?.call(false);
    }

    // Handle eraser tool
    if (widget.drawingTool == DrawingTool.eraser) {
      _activePointerId = event.pointer; // Set active pointer for eraser tracking
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

    // Handle laser pointer tool
    if (widget.drawingTool == DrawingTool.laserPointer) {
      final canvasPos = _screenToCanvas(event.localPosition);
      _log('LaserPointer DOWN at $canvasPos');
      // 이전 페이드 타이머 취소 및 상태 완전 초기화
      _laserPointerFadeTimer?.cancel();
      _laserPointerFadeTimer = null;
      setState(() {
        _laserPointerPosition = canvasPos;
        _laserPointerTrail = [canvasPos];
        _lastDeviceKind = 'LaserPointer';
      });
      return;
    }

    // Handle presentation highlighter tool
    if (widget.drawingTool == DrawingTool.presentationHighlighter) {
      final canvasPos = _screenToCanvas(event.localPosition);
      _log('PresentationHighlighter DOWN at $canvasPos');
      // 이전 페이드 타이머 취소 및 상태 초기화
      _presentationHighlighterFadeTimer?.cancel();
      _presentationHighlighterFadeTimer = null;
      _activePointerId = event.pointer;
      _isPenDrawing = true;
      setState(() {
        _presentationHighlighterTrail = [canvasPos];
        _presentationHighlighterOpacity = 1.0;
        _lastDeviceKind = 'PresentationHighlighter';
      });
      return;
    }

    // Handle shape tools
    if (_isShapeTool(widget.drawingTool)) {
      final canvasPos = _screenToCanvas(event.localPosition);
      _log('Shape DOWN at $canvasPos, tool: ${widget.drawingTool}');
      _activePointerId = event.pointer; // Set active pointer for shape tracking
      setState(() {
        _shapeStartPoint = canvasPos;
        _shapeEndPoint = canvasPos;
        _isDrawingShape = true;
        _inputCount++;
        _lastDeviceKind = 'Shape';
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

    // 펜/하이라이터로 표/도형 위에서 롱프레스 시 드래그 모드 준비
    // (그리기와 동시에 롱프레스 감지)
    // 단, 테이블 경계선 리사이즈 대기 상태일 때는 건너뜀
    if ((widget.drawingTool == DrawingTool.pen || widget.drawingTool == DrawingTool.highlighter) && !_isWaitingForResizeLongPress && !_isPendingResizeLongPress) {
      // 기존 타이머 취소
      _longPressTimer?.cancel();
      _longPressTimer = null;

      _perfLog('PEN_CHECK_TABLES', inputType: 'tables=${_tables.length}', pos: canvasPos);

      // Check if on a table border (셀 테두리 2px 이내에서만 인식)
      for (int i = _tables.length - 1; i >= 0; i--) {
        final table = _tables[i];
        final isNearBorder = table.isNearBorder(canvasPos, tolerance: 2.0);
        _perfLog('PEN_TABLE_CHECK', inputType: 'bounds=${table.bounds},isNearBorder=$isNearBorder', pos: canvasPos);
        // 셀 테두리 근처에서만 롱프레스 드래그 인식 (셀 내부에서는 그냥 필기)
        if (isNearBorder) {
          _elementTapStartTime = DateTime.now().millisecondsSinceEpoch;
          _elementTapStartPos = canvasPos;
          _pendingDragElementId = table.id;
          _pendingDragElementType = 'table';
          _longPressTriggered = false;
          _tableDragStart = canvasPos;
          // 펜으로 표 테두리 롱프레스 시 selectedTableId는 롱프레스 트리거 시에만 설정
          // (그리기 중에는 선택 표시 안함)

          // 1초 후 롱프레스 트리거 (타이머 사용) - 삭제 버튼 표시 포함
          final tableIdForTimer = table.id;
          _perfLog('TIMER_START', inputType: 'table:${table.id}', pos: canvasPos);
          _longPressTimer = Timer(Duration(milliseconds: _longPressDuration), () {
            _perfLog('TIMER_FIRED', inputType: 'pendingId=$_pendingDragElementId,triggered=$_longPressTriggered', pos: _elementTapStartPos);
            if (_pendingDragElementId != null && !_longPressTriggered && mounted) {
              // 삭제 버튼 먼저 표시
              setState(() {
                _showDeleteButtonForTableId = tableIdForTimer;
              });
              _triggerLongPressDrag();
            }
          });
          break;
        }
      }
      // Check if on a shape
      if (_pendingDragElementId == null) {
        for (int i = _shapes.length - 1; i >= 0; i--) {
          final shape = _shapes[i];
          if (shape.containsPoint(canvasPos)) {
            _elementTapStartTime = DateTime.now().millisecondsSinceEpoch;
            _elementTapStartPos = canvasPos;
            _pendingDragElementId = shape.id;
            _pendingDragElementType = 'shape';
            _longPressTriggered = false;
            _shapeDragStart = canvasPos;
            // 펜으로 도형 위 롱프레스 시 selectedShapeId는 롱프레스 트리거 시에만 설정
            // (그리기 중에는 선택 표시 안함)

            // 1초 후 롱프레스 트리거 (타이머 사용)
            _perfLog('TIMER_START', inputType: 'shape:${shape.id}', pos: canvasPos);
            _longPressTimer = Timer(Duration(milliseconds: _longPressDuration), () {
              _perfLog('TIMER_FIRED', inputType: 'pendingId=$_pendingDragElementId,triggered=$_longPressTriggered', pos: _elementTapStartPos);
              if (_pendingDragElementId != null && !_longPressTriggered && mounted) {
                _triggerLongPressDrag();
              }
            });
            break;
          }
        }
      }
    }

    // Determine color based on tool
    Color strokeColor = widget.strokeColor;
    if (widget.drawingTool == DrawingTool.highlighter) {
      strokeColor = widget.strokeColor.withOpacity(widget.highlighterOpacity);
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

  /// Erase strokes at a point (partial erasing - splits strokes)
  void _eraseAt(Offset point) {
    // 지우개 반경: _eraserRadius 사용 (커서와 동일)
    final eraserRadius = _eraserRadius;
    final toRemove = <Stroke>[];
    final toAdd = <Stroke>[];

    for (int idx = 0; idx < _strokes.length; idx++) {
      final stroke = _strokes[idx];

      // 도형인 경우 전체 삭제 (부분 삭제 불가)
      if (stroke.isShape) {
        bool shouldRemove = false;
        // 원/타원: boundingBox 기준으로 검사
        if (stroke.shapeType == ShapeType.circle) {
          // 타원의 중심과 반지름 계산
          final centerX = (stroke.boundingBox.minX + stroke.boundingBox.maxX) / 2;
          final centerY = (stroke.boundingBox.minY + stroke.boundingBox.maxY) / 2;
          final radiusX = (stroke.boundingBox.maxX - stroke.boundingBox.minX) / 2;
          final radiusY = (stroke.boundingBox.maxY - stroke.boundingBox.minY) / 2;

          // 타원 경계와의 거리 계산 (정규화된 좌표 사용)
          final dx = (point.dx - centerX) / radiusX;
          final dy = (point.dy - centerY) / radiusY;
          final normalizedDist = math.sqrt(dx * dx + dy * dy);

          // 타원 경계선 근처인지 확인 (더 넓은 범위)
          final threshold = (eraserRadius + stroke.width + 15) / math.min(radiusX, radiusY);
          if ((normalizedDist - 1.0).abs() <= threshold) {
            shouldRemove = true;
          }
        } else {
          // 직선, 사각형, 화살표: 선분 기반 검사 (포인트 사이 연결선과의 거리)
          final hitDistance = eraserRadius + stroke.width / 2 + 10; // 여유 10px 추가
          for (int i = 0; i < stroke.points.length - 1; i++) {
            final p1 = Offset(stroke.points[i].x, stroke.points[i].y);
            final p2 = Offset(stroke.points[i + 1].x, stroke.points[i + 1].y);
            final distance = _pointToLineDistance(point, p1, p2);
            if (distance <= hitDistance) {
              shouldRemove = true;
              break;
            }
          }
        }
        if (shouldRemove) {
          toRemove.add(stroke);
        }
      } else {
        // 일반 스트로크: 부분 삭제 (지우개에 닿은 포인트만 제거)
        final hitDistance = eraserRadius + stroke.width / 2;
        final erasedIndices = <int>{};

        // 포인트가 1개인 경우 (점)
        if (stroke.points.length == 1) {
          final p = stroke.points[0];
          final distance = (Offset(p.x, p.y) - point).distance;
          if (distance <= hitDistance) {
            toRemove.add(stroke);
          }
        } else {
          // 각 포인트가 지우개에 닿았는지 확인
          for (int i = 0; i < stroke.points.length; i++) {
            final p = stroke.points[i];
            final distance = (Offset(p.x, p.y) - point).distance;
            if (distance <= hitDistance) {
              erasedIndices.add(i);
            }
          }

          if (erasedIndices.isNotEmpty) {
            toRemove.add(stroke);
            // 지워지지 않은 부분을 세그먼트로 분할
            final segments = _splitStrokeByErasedIndices(stroke, erasedIndices);
            toAdd.addAll(segments);
          }
        }
      }
    }

    if (toRemove.isNotEmpty) {
      setState(() {
        for (final stroke in toRemove) {
          _strokes.remove(stroke);
        }
        _strokes.addAll(toAdd);
      });
      widget.onStrokesChanged?.call(_strokes);
    }

    // Also check CanvasShapes for erasing
    final shapesToRemove = <CanvasShape>[];
    for (final shape in _shapes) {
      if (shape.containsPoint(point, tolerance: eraserRadius + 20)) {
        shapesToRemove.add(shape);
      }
    }
    if (shapesToRemove.isNotEmpty) {
      setState(() {
        for (final shape in shapesToRemove) {
          _shapes.remove(shape);
        }
        // Clear selection if selected shape was erased
        if (_selectedShapeId != null && shapesToRemove.any((s) => s.id == _selectedShapeId)) {
          _selectedShapeId = null;
          widget.onShapeSelectionChanged?.call(false);
        }
      });
      widget.onShapesChanged?.call(_shapes);
    }

    // 표(Table)와 이미지(Image)는 지우개로 삭제하지 않음
    // 실수로 삭제되는 것을 방지하기 위해 선택 후 삭제 버튼으로만 삭제 가능
  }

  /// 점에서 선분까지의 최단 거리 계산
  double _pointToLineDistance(Offset point, Offset lineStart, Offset lineEnd) {
    final dx = lineEnd.dx - lineStart.dx;
    final dy = lineEnd.dy - lineStart.dy;
    final lengthSquared = dx * dx + dy * dy;

    if (lengthSquared == 0) {
      // 선분이 점인 경우
      return (point - lineStart).distance;
    }

    // 선분 위 가장 가까운 점의 파라미터 t (0~1 범위로 클램프)
    var t = ((point.dx - lineStart.dx) * dx + (point.dy - lineStart.dy) * dy) / lengthSquared;
    t = t.clamp(0.0, 1.0);

    // 선분 위 가장 가까운 점
    final closestX = lineStart.dx + t * dx;
    final closestY = lineStart.dy + t * dy;

    return (point - Offset(closestX, closestY)).distance;
  }

  /// Split a stroke into segments, excluding erased indices
  List<Stroke> _splitStrokeByErasedIndices(Stroke stroke, Set<int> erasedIndices) {
    final segments = <Stroke>[];
    final currentSegment = <StrokePoint>[];

    for (int i = 0; i < stroke.points.length; i++) {
      if (erasedIndices.contains(i)) {
        // End current segment if it has enough points
        if (currentSegment.length >= 2) {
          segments.add(_createSegmentStroke(stroke, List.from(currentSegment)));
        }
        currentSegment.clear();
      } else {
        currentSegment.add(stroke.points[i]);
      }
    }

    // Add final segment if it has enough points
    if (currentSegment.length >= 2) {
      segments.add(_createSegmentStroke(stroke, List.from(currentSegment)));
    }

    return segments;
  }

  /// Create a new stroke from a segment of points
  Stroke _createSegmentStroke(Stroke original, List<StrokePoint> points) {
    return Stroke(
      id: '${original.id}_${DateTime.now().millisecondsSinceEpoch}',
      toolType: original.toolType,
      color: original.color,
      width: original.width,
      points: points,
      timestamp: original.timestamp,
      isShape: original.isShape,
      shapeType: original.shapeType,
    );
  }

  void _onPointerMove(PointerMoveEvent event) {
    final moveStartTime = DateTime.now().millisecondsSinceEpoch;
    final isFingerTouch = _isFingerTouch(event);

    // Handle image manipulation first
    if (_isDraggingImage || _isResizingImage || _isRotatingImage) {
      final canvasPos = _screenToCanvas(event.localPosition);
      if (_selectedImageId != null && _imageDragStart != null) {
        final index = _images.indexWhere((img) => img.id == _selectedImageId);
        if (index != -1) {
          final image = _images[index];

          if (_isRotatingImage) {
            // Calculate rotation based on angle from center
            final center = image.bounds.center;
            final startAngle = (_imageDragStart! - center).direction;
            final currentAngle = (canvasPos - center).direction;
            final newRotation = (_imageRotationStart ?? 0) + (currentAngle - startAngle);
            setState(() {
              _images[index] = image.copyWith(rotation: newRotation);
            });
          } else if (_isResizingImage) {
            // Resize from corner
            final delta = canvasPos - _imageDragStart!;
            var newBounds = image.bounds;

            switch (_resizeCorner) {
              case 'br':
                newBounds = Rect.fromLTRB(
                  image.bounds.left,
                  image.bounds.top,
                  (image.bounds.right + delta.dx).clamp(image.bounds.left + 20, double.infinity),
                  (image.bounds.bottom + delta.dy).clamp(image.bounds.top + 20, double.infinity),
                );
                break;
              case 'bl':
                newBounds = Rect.fromLTRB(
                  (image.bounds.left + delta.dx).clamp(-double.infinity, image.bounds.right - 20),
                  image.bounds.top,
                  image.bounds.right,
                  (image.bounds.bottom + delta.dy).clamp(image.bounds.top + 20, double.infinity),
                );
                break;
              case 'tr':
                newBounds = Rect.fromLTRB(
                  image.bounds.left,
                  (image.bounds.top + delta.dy).clamp(-double.infinity, image.bounds.bottom - 20),
                  (image.bounds.right + delta.dx).clamp(image.bounds.left + 20, double.infinity),
                  image.bounds.bottom,
                );
                break;
              case 'tl':
                newBounds = Rect.fromLTRB(
                  (image.bounds.left + delta.dx).clamp(-double.infinity, image.bounds.right - 20),
                  (image.bounds.top + delta.dy).clamp(-double.infinity, image.bounds.bottom - 20),
                  image.bounds.right,
                  image.bounds.bottom,
                );
                break;
            }

            setState(() {
              _images[index] = image.copyWith(
                position: newBounds.topLeft,
                size: newBounds.size,
              );
            });
            _imageDragStart = canvasPos;
          } else if (_isDraggingImage) {
            // Move image
            final delta = canvasPos - _imageDragStart!;
            setState(() {
              _images[index] = image.copyWith(
                position: image.position + delta,
              );
            });
            _imageDragStart = canvasPos;
          }
          widget.onImagesChanged?.call(_images);
        }
      }
      return;
    }

    // Check if waiting for resize long press - cancel if moved too much
    if ((_isWaitingForResizeLongPress || _isPendingResizeLongPress) && _resizingTableId != null) {
      final canvasPos = _screenToCanvas(event.localPosition);
      final moveDistance = (canvasPos - _resizeBorderStartPos).distance;

      // Cancel long press if moved more than threshold (20px)
      if (moveDistance > _resizeMovementThreshold) {
        _cancelResizeLongPressState(reason: 'moved too much');
      }
    }

    // Handle table border resize (after long press activated)
    if (_isResizingTableBorder && _resizingTableId != null) {
      final canvasPos = _screenToCanvas(event.localPosition);
      final index = _tables.indexWhere((t) => t.id == _resizingTableId);
      if (index != -1) {
        final table = _tables[index];
        if (_resizingColumnIndex >= 0) {
          // Resize column width
          final deltaX = canvasPos.dx - _resizeStartX;
          final newWidth = (_originalColumnWidth + deltaX).clamp(20.0, 500.0);
          setState(() {
            _tables[index] = table.withColumnWidth(_resizingColumnIndex, newWidth);
          });
        } else if (_resizingRowIndex >= 0) {
          // Resize row height
          final deltaY = canvasPos.dy - _resizeStartY;
          final newHeight = (_originalRowHeight + deltaY).clamp(15.0, 300.0);
          setState(() {
            _tables[index] = table.withRowHeight(_resizingRowIndex, newHeight);
          });
        } else if (_resizingRowIndex == -99) {
          // Resize from top edge: adjust first row height and move table position upward
          final deltaY = _resizeStartY - canvasPos.dy; // Inverted: moving up increases height
          final newHeight = (_originalRowHeight + deltaY).clamp(15.0, 300.0);
          final actualDelta = newHeight - _originalRowHeight;
          setState(() {
            // Update row height
            _tables[index] = table.withRowHeight(0, newHeight).copyWith(
              // Move table position upward by the height difference
              position: Offset(table.position.dx, table.position.dy - actualDelta),
            );
            // Update start position for continuous resize
            _resizeStartY = canvasPos.dy;
            _originalRowHeight = newHeight;
          });
        }
        widget.onTablesChanged?.call(_tables);
      }
      return;
    }

    // Handle text dragging
    if (_isDraggingText && _selectedTextId != null && _textDragStart != null) {
      final canvasPos = _screenToCanvas(event.localPosition);
      final index = _texts.indexWhere((t) => t.id == _selectedTextId);
      if (index != -1) {
        final text = _texts[index];
        final delta = canvasPos - _textDragStart!;
        setState(() {
          _texts[index] = text.copyWith(position: text.position + delta);
        });
        _textDragStart = canvasPos;
        widget.onTextsChanged?.call(_texts);
      }
      return;
    }

    // Check for long press cancellation (if moved too much or drawing started)
    if (_pendingDragElementId != null && !_longPressTriggered) {
      // Check if position moved too much (cancel long press if moved)
      final canvasPos = _screenToCanvas(event.localPosition);
      final moveDistance = _elementTapStartPos != null ? (canvasPos - _elementTapStartPos!).distance : 0.0;

      // 펜으로 그리는 중이면 롱프레스 취소 (스트로크 포인트가 2개 이상이면 그리기 시작한 것)
      final isDrawingStroke = _currentStroke != null && _currentStroke!.points.length >= 2;

      if (moveDistance > 20.0 || isDrawingStroke) {
        // Moved too much or drawing stroke, cancel pending drag and timer
        _longPressTimer?.cancel();
        _longPressTimer = null;
        _pendingDragElementId = null;
        _pendingDragElementType = null;
        _elementTapStartTime = null;
        _elementTapStartPos = null;
      }
    }

    // Handle shape ready-to-drag state → start actual dragging
    if (_readyToDragShapeId != null && _selectedShapeId != null && _shapeDragStart != null) {
      // 준비 상태에서 이동하면 실제 드래그 시작
      setState(() {
        _isDraggingShape = true;
        _draggingShapeHandle = null;
        _readyToDragShapeId = null; // 준비 상태 해제
        _lastDeviceKind = 'Shape (dragging)';
      });
      _perfLog('SHAPE_DRAG_START', inputType: 'from ready state', pos: _shapeDragStart);
    }

    // Handle shape dragging/editing
    if (_isDraggingShape && _selectedShapeId != null && _shapeDragStart != null) {
      final canvasPos = _screenToCanvas(event.localPosition);
      _log('Shape dragging MOVE: canvasPos=(${canvasPos.dx.toStringAsFixed(1)}, ${canvasPos.dy.toStringAsFixed(1)}), shapeDragStart=(${_shapeDragStart!.dx.toStringAsFixed(1)}, ${_shapeDragStart!.dy.toStringAsFixed(1)})');
      final index = _shapes.indexWhere((s) => s.id == _selectedShapeId);
      if (index != -1) {
        final shape = _shapes[index];
        final delta = canvasPos - _shapeDragStart!;

        if (_draggingShapeHandle == null) {
          // Dragging whole shape
          setState(() {
            _shapes[index] = shape.copyWith(
              startPoint: shape.startPoint + delta,
              endPoint: shape.endPoint + delta,
            );
          });
        } else if (_draggingShapeHandle == 0) {
          // Dragging start handle
          setState(() {
            _shapes[index] = shape.copyWith(startPoint: canvasPos);
          });
        } else if (_draggingShapeHandle == 1) {
          // Dragging end handle
          setState(() {
            _shapes[index] = shape.copyWith(endPoint: canvasPos);
          });
        }

        _shapeDragStart = canvasPos;
        widget.onShapesChanged?.call(_shapes);
      }
      return;
    }

    // Handle table ready-to-drag state → start actual dragging
    if (_readyToDragTableId != null && _selectedTableId != null && _tableDragStart != null) {
      // 준비 상태에서 이동하면 실제 드래그 시작
      setState(() {
        _isDraggingTable = true;
        _readyToDragTableId = null; // 준비 상태 해제
        _lastDeviceKind = 'Table (dragging)';
      });
      _perfLog('TABLE_DRAG_START', inputType: 'from ready state', pos: _tableDragStart);
    }

    // Handle table dragging
    if (_isDraggingTable && _selectedTableId != null && _tableDragStart != null) {
      final canvasPos = _screenToCanvas(event.localPosition);
      final delta = canvasPos - _tableDragStart!;
      _perfLog('TABLE DRAG', inputType: 'delta=(${delta.dx.toStringAsFixed(0)},${delta.dy.toStringAsFixed(0)})', pos: canvasPos);
      final index = _tables.indexWhere((t) => t.id == _selectedTableId);
      if (index != -1) {
        final table = _tables[index];

        setState(() {
          _tables[index] = table.copyWith(
            position: table.position + delta,
          );
        });

        _tableDragStart = canvasPos;
        widget.onTablesChanged?.call(_tables);
      }
      return;
    }

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

    // Handle laser pointer tool - process BEFORE finger gesture check
    if (widget.drawingTool == DrawingTool.laserPointer && _laserPointerPosition != null) {
      final canvasPos = _screenToCanvas(event.localPosition);
      setState(() {
        _laserPointerPosition = canvasPos;
        _laserPointerTrail.add(canvasPos);
        // 트레일 길이 제한
        if (_laserPointerTrail.length > _laserPointerTrailLength) {
          _laserPointerTrail.removeAt(0);
        }
      });
      return;
    }

    // Handle presentation highlighter tool - process BEFORE finger gesture check
    if (widget.drawingTool == DrawingTool.presentationHighlighter &&
        _presentationHighlighterTrail.isNotEmpty &&
        event.pointer == _activePointerId) {
      final canvasPos = _screenToCanvas(event.localPosition);
      setState(() {
        _presentationHighlighterTrail.add(canvasPos);
        // 선긋기 중에는 트레일 길이 제한 없음 - 모든 점 유지
        // fade는 선긋기가 끝난 후에만 시작됨
      });
      return;
    }

    // Handle shape tools - process BEFORE finger gesture check
    if (_isShapeTool(widget.drawingTool) && _isDrawingShape && event.pointer == _activePointerId) {
      final canvasPos = _screenToCanvas(event.localPosition);
      setState(() {
        _shapeEndPoint = canvasPos;
        _inputCount++;
      });
      return;
    }

    // Handle finger gesture (pan/zoom) - but not if dragging elements
    // 핀치 줌이 활성화되면 (_isGesturing && _activePointers.length >= 2) 포인터 타입과 무관하게 제스처 처리
    final isDraggingElement = _isDraggingImage || _isResizingImage || _isRotatingImage ||
        _isDraggingText || _isDraggingShape || _isDraggingTable;
    final isActiveGesture = _isGesturing && _activePointers.length >= 2;

    // 활성 제스처 중이면 손가락 터치 체크 무시하고 계속 처리
    if ((isFingerTouch || isActiveGesture) && _activePointers.containsKey(event.pointer) && !isDraggingElement) {
      _activePointers[event.pointer] = event.localPosition;

      if (isActiveGesture) {
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

        if (_lastFocalPoint != null && _baseSpan > 0 && _canvasSize != null) {
          // 핀치 시작 시점 대비 스케일 변화율 계산
          final rawScaleFactor = currentSpan / _baseSpan;

          // 새 스케일 계산 (클램핑: 1.0x ~ 3.0x)
          final newScale = (_baseScale * rawScaleFactor).clamp(1.0, 3.0);

          // 핀치 중심(focal point) 기준으로 오프셋 계산
          // 현재 focal point가 가리키는 캔버스 좌표가 줌 후에도 같은 화면 위치에 있도록
          final focalInCanvas = (currentFocal - _offset) / _scale;
          final newOffset = currentFocal - focalInCanvas * newScale;

          _scale = newScale;
          _offset = newOffset;

          _perfLog('PINCH-ZOOM', inputType: 'scale:${_scale.toStringAsFixed(2)}');

          // 외부에 변환 정보 알림
          widget.onTransformChanged?.call(_scale, _offset);
        }

        _lastFocalPoint = currentFocal;
        setState(() {});  // 핀치 줌 상태 업데이트
        return;
      }

      // Single finger pan
      if (_activePointers.length == 1 && _lastFocalPoint != null) {
        final delta = event.localPosition - _lastFocalPoint!;
        setState(() {
          _offset += delta;
        });
        _lastFocalPoint = event.localPosition;

        // 외부에 변환 정보 알림
        widget.onTransformChanged?.call(_scale, _offset);
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

    // 이미 활성화된 포인터로 그리는 중이면 _isAllowedInput 체크 생략
    // (MOVE 중에 Native API가 다른 포인터 정보를 반환하면 스트로크가 중단되는 문제 방지)
    final allowed = (event.pointer == _activePointerId && _currentStroke != null)
        ? true
        : _isAllowedInput(event);

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
      if (event.pointer != _activePointerId) {
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

    // Handle image/text manipulation end
    if (_isDraggingImage || _isResizingImage || _isRotatingImage) {
      _activePointerId = null;
      _isDraggingImage = false;
      _isResizingImage = false;
      _isRotatingImage = false;
      _imageDragStart = null;
      _resizeCorner = null;
      _imageRotationStart = null;
      return;
    }

    if (_isDraggingText) {
      _activePointerId = null;
      _isDraggingText = false;
      _textDragStart = null;
      return;
    }

    // Handle table border resize end (or long press waiting cleanup)
    if (_isResizingTableBorder || _isWaitingForResizeLongPress || _isPendingResizeLongPress) {
      _activePointerId = null;
      final wasActualResize = _isResizingTableBorder;
      _resizeLongPressTimer?.cancel();
      _resizeLongPressTimer = null;
      _resizeVisualFeedbackTimer?.cancel();
      _resizeVisualFeedbackTimer = null;
      _isResizingTableBorder = false;
      _isWaitingForResizeLongPress = false;
      _isPendingResizeLongPress = false;
      _resizingTableId = null;
      _resizingColumnIndex = -1;
      _resizingRowIndex = -1;
      _resizeBorderStartPos = Offset.zero;
      if (wasActualResize) {
        _perfLog('TABLE_RESIZE_END', inputType: 'resize complete');
      } else {
        // Save any stroke drawn during the waiting period (before 0.5s timeout)
        _saveCurrentStrokeIfExists();
        _perfLog('TABLE_RESIZE_WAITING_END', inputType: 'long press not triggered');
      }
      return;
    }

    // Handle shape dragging end (or ready state end)
    if (_isDraggingShape || _readyToDragShapeId != null) {
      _activePointerId = null;
      _isDraggingShape = false;
      _readyToDragShapeId = null;
      _shapeDragStart = null;
      _draggingShapeHandle = null;
      // Reset long press state and timer
      _longPressTimer?.cancel();
      _longPressTimer = null;
      _pendingDragElementId = null;
      _pendingDragElementType = null;
      _elementTapStartTime = null;
      _elementTapStartPos = null;
      _longPressTriggered = false;
      return;
    }

    // Handle table dragging end (or ready state end)
    if (_isDraggingTable || _readyToDragTableId != null) {
      _activePointerId = null;
      _isDraggingTable = false;
      _readyToDragTableId = null;
      _tableDragStart = null;
      // Reset long press state and timer
      _longPressTimer?.cancel();
      _longPressTimer = null;
      _pendingDragElementId = null;
      _pendingDragElementType = null;
      _elementTapStartTime = null;
      _elementTapStartPos = null;
      _longPressTriggered = false;
      return;
    }

    // Reset long press state if element was selected but not dragged
    if (_pendingDragElementId != null) {
      _longPressTimer?.cancel();
      _longPressTimer = null;
      _pendingDragElementId = null;
      _pendingDragElementType = null;
      _elementTapStartTime = null;
      _elementTapStartPos = null;
      _longPressTriggered = false;
    }

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
        _isGesturing = false;  // 핀치 줌 모드 해제
        _lastFocalPoint = _activePointers.values.first;
        // 현재 상태를 새 기준점으로 저장 (다시 2손가락이 되면 여기서 시작)
        _baseScale = _scale;
        _baseOffset = _offset;
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

    // Handle laser pointer end - start fade animation
    if (widget.drawingTool == DrawingTool.laserPointer && _laserPointerPosition != null) {
      _activePointerId = null;  // 다음 터치를 허용하기 위해 초기화
      _isPenDrawing = false;
      _startLaserPointerFade();
      return;
    }

    // Handle presentation highlighter end - start fade animation or save as highlighter stroke
    if (widget.drawingTool == DrawingTool.presentationHighlighter && _presentationHighlighterTrail.isNotEmpty) {
      _activePointerId = null;  // 다음 터치를 허용하기 위해 초기화
      _isPenDrawing = false;
      if (widget.presentationHighlighterFadeEnabled) {
        _startPresentationHighlighterFade();
      } else {
        // 페이드 OFF면 형광펜 스트로크로 저장
        _savePresentationHighlighterAsStroke();
        setState(() {
          _presentationHighlighterTrail.clear();
        });
      }
      return;
    }

    // Handle shape tool end
    if (_isShapeTool(widget.drawingTool) && _isDrawingShape) {
      _activePointerId = null;
      _isPenDrawing = false;

      // Update end point with final UP position
      final finalEndPoint = _screenToCanvas(event.localPosition);

      if (_shapeStartPoint != null) {
        // Create editable CanvasShape
        CanvasShapeType shapeType;
        switch (widget.drawingTool) {
          case DrawingTool.shapeLine:
            shapeType = CanvasShapeType.line;
            break;
          case DrawingTool.shapeRectangle:
            shapeType = CanvasShapeType.rectangle;
            break;
          case DrawingTool.shapeCircle:
            shapeType = CanvasShapeType.circle;
            break;
          case DrawingTool.shapeArrow:
            shapeType = CanvasShapeType.arrow;
            break;
          default:
            shapeType = CanvasShapeType.line;
        }

        final newShape = CanvasShape(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          type: shapeType,
          startPoint: _shapeStartPoint!,
          endPoint: finalEndPoint,
          color: widget.strokeColor,
          strokeWidth: widget.strokeWidth,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );

        _saveState();
        setState(() {
          _shapes.add(newShape);
          _selectedShapeId = newShape.id;
        });
        widget.onShapesChanged?.call(_shapes);
        widget.onShapeSelectionChanged?.call(true);
      }

      setState(() {
        _shapeStartPoint = null;
        _shapeEndPoint = null;
        _isDrawingShape = false;
      });
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

  /// Start laser pointer fade animation
  void _startLaserPointerFade() {
    _laserPointerFadeTimer?.cancel();
    _laserPointerFadeTimer = null;

    // 점진적으로 트레일을 제거하여 페이드 효과 구현
    int fadeSteps = 15; // 15단계로 페이드
    int stepDuration = _laserPointerFadeDuration.inMilliseconds ~/ fadeSteps;
    int currentStep = 0;

    _laserPointerFadeTimer = Timer.periodic(Duration(milliseconds: stepDuration), (timer) {
      currentStep++;
      if (!mounted) {
        timer.cancel();
        _laserPointerFadeTimer = null;
        return;
      }

      setState(() {
        // 트레일에서 점진적으로 포인트 제거
        if (_laserPointerTrail.length > 2) {
          _laserPointerTrail.removeAt(0);
          _laserPointerTrail.removeAt(0);
        } else if (_laserPointerTrail.isNotEmpty) {
          _laserPointerTrail.clear();
        }

        // 완전히 사라지면 포지션도 null로
        if (_laserPointerTrail.isEmpty || currentStep >= fadeSteps) {
          _laserPointerPosition = null;
          _laserPointerTrail.clear();
          timer.cancel();
          _laserPointerFadeTimer = null;
        }
      });
    });
  }

  /// Save presentation highlighter trail as a highlighter stroke (when fade is OFF)
  void _savePresentationHighlighterAsStroke() {
    if (_presentationHighlighterTrail.isEmpty) return;

    _saveState();

    // 트레일을 형광펜 스트로크로 변환
    final points = _presentationHighlighterTrail.map((offset) =>
      StrokePoint(
        x: offset.dx,
        y: offset.dy,
        pressure: 0.5, // 기본 압력
        tilt: 0.0,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      )
    ).toList();

    if (points.length < 2) return;

    final newStroke = Stroke(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      toolType: ToolType.highlighter, // 형광펜으로 저장
      color: widget.highlighterColor, // 형광펜 색상 사용
      width: widget.highlighterWidth, // 형광펜 굵기 사용
      points: points,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    setState(() {
      _strokes.add(newStroke);
    });

    widget.onStrokesChanged?.call(_strokes);
    _log('PresentationHighlighter saved as highlighter stroke: ${newStroke.id}');
  }

  /// Start presentation highlighter fade animation - removes from beginning (first drawn)
  void _startPresentationHighlighterFade() {
    _presentationHighlighterFadeTimer?.cancel();
    _presentationHighlighterFadeTimer = null;

    if (_presentationHighlighterTrail.isEmpty) return;

    // 속도에 따라 페이드 시간 조정 (속도가 높을수록 빠르게 사라짐)
    // 기본 1.5초, 느림(0.5x) = 3초, 빠름(2.0x) = 0.75초
    final adjustedDurationMs = (_presentationHighlighterFadeDuration.inMilliseconds / widget.presentationHighlighterFadeSpeed).round();

    // 처음 그어진 부분부터 점차 지우기
    final totalPoints = _presentationHighlighterTrail.length;

    // 고정 간격(50ms)으로 타이머 실행, 매 스텝마다 제거할 포인트 수를 계산
    const int stepInterval = 50; // 50ms 간격
    final int totalSteps = (adjustedDurationMs / stepInterval).ceil();

    // 매 스텝마다 제거할 포인트 수 (일정하게 유지)
    final double pointsPerStep = totalPoints / totalSteps;
    double accumulatedPoints = 0;

    _presentationHighlighterFadeTimer = Timer.periodic(const Duration(milliseconds: stepInterval), (timer) {
      if (!mounted) {
        timer.cancel();
        _presentationHighlighterFadeTimer = null;
        return;
      }

      setState(() {
        // 누적 포인트 계산하여 일정한 속도로 제거
        accumulatedPoints += pointsPerStep;
        int pointsToRemove = accumulatedPoints.floor();
        accumulatedPoints -= pointsToRemove;

        // 최소 1개는 제거
        pointsToRemove = pointsToRemove.clamp(1, _presentationHighlighterTrail.length);

        // 앞쪽(처음 그어진 부분)에서 포인트 제거
        for (int i = 0; i < pointsToRemove && _presentationHighlighterTrail.isNotEmpty; i++) {
          _presentationHighlighterTrail.removeAt(0);
        }

        // 모두 제거되면 타이머 종료
        if (_presentationHighlighterTrail.isEmpty) {
          _presentationHighlighterOpacity = 1.0;
          timer.cancel();
          _presentationHighlighterFadeTimer = null;
        }
      });
    });
  }

  /// Check if a drawing tool is a shape tool
  bool _isShapeTool(DrawingTool tool) {
    return tool == DrawingTool.shapeLine ||
        tool == DrawingTool.shapeRectangle ||
        tool == DrawingTool.shapeCircle ||
        tool == DrawingTool.shapeArrow;
  }

  /// Generate stroke points for a shape
  List<StrokePoint> _generateShapePoints(DrawingTool tool, Offset start, Offset end) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    const pressure = 0.5;

    switch (tool) {
      case DrawingTool.shapeLine:
        return [
          StrokePoint(x: start.dx, y: start.dy, pressure: pressure, tilt: 0, timestamp: timestamp),
          StrokePoint(x: end.dx, y: end.dy, pressure: pressure, tilt: 0, timestamp: timestamp),
        ];

      case DrawingTool.shapeRectangle:
        return [
          StrokePoint(x: start.dx, y: start.dy, pressure: pressure, tilt: 0, timestamp: timestamp),
          StrokePoint(x: end.dx, y: start.dy, pressure: pressure, tilt: 0, timestamp: timestamp),
          StrokePoint(x: end.dx, y: end.dy, pressure: pressure, tilt: 0, timestamp: timestamp),
          StrokePoint(x: start.dx, y: end.dy, pressure: pressure, tilt: 0, timestamp: timestamp),
          StrokePoint(x: start.dx, y: start.dy, pressure: pressure, tilt: 0, timestamp: timestamp),
        ];

      case DrawingTool.shapeCircle:
        final centerX = (start.dx + end.dx) / 2;
        final centerY = (start.dy + end.dy) / 2;
        final radiusX = (end.dx - start.dx).abs() / 2;
        final radiusY = (end.dy - start.dy).abs() / 2;
        final points = <StrokePoint>[];

        // Generate ellipse points
        const segments = 36;
        for (int i = 0; i <= segments; i++) {
          final angle = (i / segments) * 2 * math.pi;
          final x = centerX + radiusX * math.cos(angle);
          final y = centerY + radiusY * math.sin(angle);
          points.add(StrokePoint(x: x, y: y, pressure: pressure, tilt: 0, timestamp: timestamp));
        }
        return points;

      case DrawingTool.shapeArrow:
        // Arrow with arrowhead - line from start to end + arrowhead at end
        final dx = end.dx - start.dx;
        final dy = end.dy - start.dy;
        final length = math.sqrt(dx * dx + dy * dy);
        if (length < 10) return [];

        // Arrowhead size (proportional to line length, max 30)
        final arrowSize = math.min(length * 0.2, 30.0);
        final angle = math.atan2(dy, dx);

        // Arrowhead points (pointing backwards from end)
        final arrowAngle1 = angle + math.pi * 0.85;
        final arrowAngle2 = angle - math.pi * 0.85;

        final arrow1X = end.dx + arrowSize * math.cos(arrowAngle1);
        final arrow1Y = end.dy + arrowSize * math.sin(arrowAngle1);
        final arrow2X = end.dx + arrowSize * math.cos(arrowAngle2);
        final arrow2Y = end.dy + arrowSize * math.sin(arrowAngle2);

        // Draw: start -> end (main line) + arrow1 -> end -> arrow2 (arrowhead)
        return [
          StrokePoint(x: start.dx, y: start.dy, pressure: pressure, tilt: 0, timestamp: timestamp),
          StrokePoint(x: end.dx, y: end.dy, pressure: pressure, tilt: 0, timestamp: timestamp),
          StrokePoint(x: arrow1X, y: arrow1Y, pressure: pressure, tilt: 0, timestamp: timestamp),
          StrokePoint(x: end.dx, y: end.dy, pressure: pressure, tilt: 0, timestamp: timestamp),
          StrokePoint(x: arrow2X, y: arrow2Y, pressure: pressure, tilt: 0, timestamp: timestamp),
        ];

      default:
        return [];
    }
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
    // Check if there's anything to clear
    if (_strokes.isEmpty && _images.isEmpty && _texts.isEmpty && _shapes.isEmpty && _tables.isEmpty) {
      return;
    }
    _saveState();
    setState(() {
      // Clear strokes
      _strokes.clear();
      _currentStroke = null;
      _inputCount = 0;

      // Clear images
      _images.clear();
      _selectedImageId = null;
      _isDraggingImage = false;
      _isResizingImage = false;
      _isRotatingImage = false;

      // Clear texts
      _texts.clear();
      _selectedTextId = null;
      _isDraggingText = false;

      // Clear shapes
      _shapes.clear();
      _selectedShapeId = null;
      _isDraggingShape = false;
      _isDrawingShape = false;
      _shapeStartPoint = null;
      _shapeEndPoint = null;

      // Clear tables
      _tables.clear();
      _selectedTableId = null;
      _isDraggingTable = false;
      _isResizingTableBorder = false;
      _resizingTableId = null;

      // Clear lasso selection
      _lassoPath.clear();
      _selectedStrokeIds.clear();
      _isDraggingSelection = false;
    });

    // Notify all changes
    widget.onStrokesChanged?.call(_strokes);
    widget.onImagesChanged?.call(_images);
    widget.onTextsChanged?.call(_texts);
    widget.onShapesChanged?.call(_shapes);
    widget.onTablesChanged?.call(_tables);
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

  /// Check if stroke is inside lasso selection (with bounding box optimization)
  bool _isStrokeInLasso(Stroke stroke, List<Offset> lasso) {
    if (stroke.points.isEmpty || lasso.length < 3) return false;

    // Calculate lasso bounding box for fast rejection
    double lassoMinX = double.infinity, lassoMinY = double.infinity;
    double lassoMaxX = double.negativeInfinity, lassoMaxY = double.negativeInfinity;
    for (final p in lasso) {
      if (p.dx < lassoMinX) lassoMinX = p.dx;
      if (p.dy < lassoMinY) lassoMinY = p.dy;
      if (p.dx > lassoMaxX) lassoMaxX = p.dx;
      if (p.dy > lassoMaxY) lassoMaxY = p.dy;
    }

    // Calculate stroke bounding box
    double strokeMinX = double.infinity, strokeMinY = double.infinity;
    double strokeMaxX = double.negativeInfinity, strokeMaxY = double.negativeInfinity;
    for (final p in stroke.points) {
      if (p.x < strokeMinX) strokeMinX = p.x;
      if (p.y < strokeMinY) strokeMinY = p.y;
      if (p.x > strokeMaxX) strokeMaxX = p.x;
      if (p.y > strokeMaxY) strokeMaxY = p.y;
    }

    // Fast rejection: if bounding boxes don't overlap, stroke is outside
    if (strokeMaxX < lassoMinX || strokeMinX > lassoMaxX ||
        strokeMaxY < lassoMinY || strokeMinY > lassoMaxY) {
      return false;
    }

    // Sample points for large strokes (check every Nth point)
    final sampleRate = stroke.points.length > 100 ? stroke.points.length ~/ 50 : 1;

    // Check if any sampled point of the stroke is inside the lasso
    for (int i = 0; i < stroke.points.length; i += sampleRate) {
      final point = stroke.points[i];
      if (_isPointInLasso(Offset(point.x, point.y), lasso)) {
        return true;
      }
    }

    // If sampling, also check the last point
    if (sampleRate > 1) {
      final lastPoint = stroke.points.last;
      if (_isPointInLasso(Offset(lastPoint.x, lastPoint.y), lasso)) {
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
    widget.onImageSelectionChanged?.call(true);
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
    widget.onImageSelectionChanged?.call(false);
  }

  /// Clear image selection
  void clearImageSelection() {
    setState(() {
      _selectedImageId = null;
    });
    widget.onImageSelectionChanged?.call(false);
  }

  /// Update image rotation
  void updateImageRotation(double rotation) {
    if (_selectedImageId == null) return;

    final index = _images.indexWhere((img) => img.id == _selectedImageId);
    if (index == -1) return;

    setState(() {
      _images[index] = _images[index].copyWith(rotation: rotation);
    });
    widget.onImagesChanged?.call(_images);
  }

  /// Update image opacity
  void updateImageOpacity(double opacity) {
    if (_selectedImageId == null) return;

    final index = _images.indexWhere((img) => img.id == _selectedImageId);
    if (index == -1) return;

    setState(() {
      _images[index] = _images[index].copyWith(opacity: opacity.clamp(0.1, 1.0));
    });
    widget.onImagesChanged?.call(_images);
  }

  /// Get selected image
  CanvasImage? get selectedImage {
    if (_selectedImageId == null) return null;
    try {
      return _images.firstWhere((img) => img.id == _selectedImageId);
    } catch (_) {
      return null;
    }
  }

  /// Check if point is on rotation handle
  bool _isOnRotationHandle(CanvasImage image, Offset point) {
    final bounds = image.bounds;
    final center = bounds.center;
    final rotationHandlePos = Offset(center.dx, bounds.top - 30);
    return (point - rotationHandlePos).distance < 15;
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
    double fontSize = text.fontSize;
    bool isBold = text.isBold;
    bool isItalic = text.isItalic;
    Color textColor = text.color;

    final colors = [
      Colors.black,
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
    ];

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('텍스트 편집'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Text input
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLines: 5,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                    fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
                    color: textColor,
                  ),
                  decoration: const InputDecoration(
                    hintText: '텍스트를 입력하세요...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                // Font size slider
                Row(
                  children: [
                    const Icon(Icons.format_size, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Slider(
                        value: fontSize,
                        min: 10,
                        max: 48,
                        divisions: 19,
                        label: '${fontSize.toInt()}',
                        onChanged: (value) {
                          setDialogState(() => fontSize = value);
                        },
                      ),
                    ),
                    Text('${fontSize.toInt()}pt'),
                  ],
                ),

                // Style buttons
                Row(
                  children: [
                    const Text('스타일: '),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(Icons.format_bold,
                        color: isBold ? Colors.blue : Colors.grey),
                      onPressed: () {
                        setDialogState(() => isBold = !isBold);
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.format_italic,
                        color: isItalic ? Colors.blue : Colors.grey),
                      onPressed: () {
                        setDialogState(() => isItalic = !isItalic);
                      },
                    ),
                  ],
                ),

                // Color picker
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('색상: '),
                    const SizedBox(width: 8),
                    ...colors.map((c) => GestureDetector(
                      onTap: () => setDialogState(() => textColor = c),
                      child: Container(
                        width: 28,
                        height: 28,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: textColor == c ? Colors.blue : Colors.grey,
                            width: textColor == c ? 3 : 1,
                          ),
                        ),
                      ),
                    )),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (controller.text.isEmpty) {
                  deleteSelectedText();
                }
                Navigator.pop(context);
              },
              child: const Text('취소'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () {
                deleteSelectedText();
                Navigator.pop(context);
              },
              child: const Text('삭제'),
            ),
            TextButton(
              onPressed: () {
                if (controller.text.isNotEmpty) {
                  _updateText(text.id, controller.text, fontSize, isBold, isItalic, textColor);
                } else {
                  deleteSelectedText();
                }
                Navigator.pop(context);
              },
              child: const Text('확인'),
            ),
          ],
        ),
      ),
    );
  }

  /// Update text with all properties
  void _updateText(String textId, String content, double fontSize, bool isBold, bool isItalic, Color color) {
    _saveState();
    setState(() {
      final index = _texts.indexWhere((t) => t.id == textId);
      if (index >= 0) {
        _texts[index] = _texts[index].copyWith(
          text: content,
          fontSize: fontSize,
          isBold: isBold,
          isItalic: isItalic,
          color: color,
        );
      }
    });
    widget.onTextsChanged?.call(_texts);
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

  /// Get all shapes (for saving)
  List<CanvasShape> get shapes => List.from(_shapes);

  /// Load strokes (for loading)
  void loadStrokes(List<Stroke> strokes) {
    _saveState();
    setState(() {
      _strokes = List.from(strokes);
    });
    widget.onStrokesChanged?.call(_strokes);
  }

  /// Load shapes (for loading)
  void loadShapes(List<CanvasShape> shapes) {
    setState(() {
      _shapes = List.from(shapes);
    });
    widget.onShapesChanged?.call(_shapes);
  }

  /// 여러 스트로크를 캔버스에 추가 (표 삽입 등)
  void addStrokes(List<Stroke> strokes) {
    if (strokes.isEmpty) return;
    _saveState();
    setState(() {
      _strokes.addAll(strokes);
    });
    widget.onStrokesChanged?.call(_strokes);
  }

  /// Get all tables (for saving)
  List<CanvasTable> get tables => List.from(_tables);

  /// Load tables (for loading)
  void loadTables(List<CanvasTable> tables) {
    setState(() {
      _tables = List.from(tables);
    });
    widget.onTablesChanged?.call(_tables);
  }

  /// Add a table to canvas
  void addTable(CanvasTable table) {
    setState(() {
      _tables.add(table);
      _selectedTableId = table.id;
    });
    widget.onTablesChanged?.call(_tables);
    widget.onTableSelectionChanged?.call(true);
  }

  /// Get selected table
  CanvasTable? get selectedTable {
    if (_selectedTableId == null) return null;
    return _tables.firstWhere(
      (t) => t.id == _selectedTableId,
      orElse: () => _tables.first,
    );
  }

  /// Delete selected table
  void deleteSelectedTable() {
    if (_selectedTableId == null) return;
    setState(() {
      _tables.removeWhere((t) => t.id == _selectedTableId);
      _selectedTableId = null;
    });
    widget.onTablesChanged?.call(_tables);
    widget.onTableSelectionChanged?.call(false);
  }
}

/// Lasso overlay painter - draws OUTSIDE RepaintBoundary for immediate updates
class _LassoOverlayPainter extends CustomPainter {
  final List<Offset> lassoPath;
  final double scale;
  final Offset offset;
  final Color lassoColor;

  _LassoOverlayPainter({
    required this.lassoPath,
    required this.scale,
    required this.offset,
    this.lassoColor = const Color(0xFF2196F3),
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (lassoPath.isEmpty) return;

    // Convert canvas coordinates to screen coordinates
    final screenPath = lassoPath.map((p) {
      return Offset(
        p.dx * scale + offset.dx,
        p.dy * scale + offset.dy,
      );
    }).toList();

    // Draw lasso path with user-selected color
    final paint = Paint()
      ..color = lassoColor.withOpacity(0.8)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // White outline for visibility
    final outlinePaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (screenPath.length >= 2) {
      final path = Path();
      path.moveTo(screenPath.first.dx, screenPath.first.dy);
      for (int i = 1; i < screenPath.length; i++) {
        path.lineTo(screenPath[i].dx, screenPath[i].dy);
      }
      canvas.drawPath(path, outlinePaint);
      canvas.drawPath(path, paint);
    }

    // Draw start point indicator
    final startPaint = Paint()
      ..color = lassoColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(screenPath.first, 5.0, startPaint);

    // Draw current point indicator
    final currentPaint = Paint()
      ..color = lassoColor.withOpacity(0.6)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(screenPath.last, 4.0, currentPaint);
  }

  @override
  bool shouldRepaint(_LassoOverlayPainter oldDelegate) {
    return lassoPath.length != oldDelegate.lassoPath.length ||
        scale != oldDelegate.scale ||
        offset != oldDelegate.offset ||
        lassoColor != oldDelegate.lassoColor;
  }
}

/// Laser pointer overlay painter - draws laser pointer with fading trail
class _LaserPointerPainter extends CustomPainter {
  final Offset? position;
  final List<Offset> trail;
  final double scale;
  final Offset offset;
  final Color color;

  _LaserPointerPainter({
    required this.position,
    required this.trail,
    required this.scale,
    required this.offset,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (trail.isEmpty && position == null) return;

    // Convert canvas coordinates to screen coordinates
    final screenTrail = trail.map((p) {
      return Offset(
        p.dx * scale + offset.dx,
        p.dy * scale + offset.dy,
      );
    }).toList();

    // Draw fading trail
    if (screenTrail.length >= 2) {
      for (int i = 1; i < screenTrail.length; i++) {
        // Calculate opacity based on position in trail (older = more transparent)
        final progress = i / screenTrail.length;
        final opacity = progress * 0.8; // Max opacity 0.8

        final trailPaint = Paint()
          ..color = color.withOpacity(opacity)
          ..strokeWidth = 4.0 * progress + 2.0 // Thicker toward current position
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

        canvas.drawLine(screenTrail[i - 1], screenTrail[i], trailPaint);
      }
    }

    // Draw current position (large red dot with glow effect)
    if (position != null) {
      final screenPos = Offset(
        position!.dx * scale + offset.dx,
        position!.dy * scale + offset.dy,
      );

      // Outer glow
      final glowPaint = Paint()
        ..color = color.withOpacity(0.3)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(screenPos, 20.0, glowPaint);

      // Middle glow
      final midGlowPaint = Paint()
        ..color = color.withOpacity(0.5)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(screenPos, 12.0, midGlowPaint);

      // Inner bright dot
      final dotPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(screenPos, 6.0, dotPaint);

      // White center highlight
      final highlightPaint = Paint()
        ..color = Colors.white.withOpacity(0.8)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(screenPos, 2.0, highlightPaint);
    }
  }

  @override
  bool shouldRepaint(_LaserPointerPainter oldDelegate) {
    return position != oldDelegate.position ||
        trail.length != oldDelegate.trail.length ||
        scale != oldDelegate.scale ||
        offset != oldDelegate.offset ||
        color != oldDelegate.color;
  }
}

/// Presentation highlighter overlay painter - draws highlighter with fading effect
class _PresentationHighlighterPainter extends CustomPainter {
  final List<Offset> trail;
  final double scale;
  final Offset offset;
  final Color color;
  final double strokeWidth;
  final double opacity;
  final double highlighterOpacity; // 형광펜 투명도

  _PresentationHighlighterPainter({
    required this.trail,
    required this.scale,
    required this.offset,
    required this.color,
    required this.strokeWidth,
    required this.opacity,
    this.highlighterOpacity = 0.4,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (trail.isEmpty) return;

    // Convert canvas coordinates to screen coordinates
    final screenTrail = trail.map((p) {
      return Offset(
        p.dx * scale + offset.dx,
        p.dy * scale + offset.dy,
      );
    }).toList();

    // Draw highlighter path with semi-transparency
    if (screenTrail.length >= 2) {
      final path = ui.Path();
      path.moveTo(screenTrail.first.dx, screenTrail.first.dy);

      for (int i = 1; i < screenTrail.length; i++) {
        path.lineTo(screenTrail[i].dx, screenTrail[i].dy);
      }

      // Main highlighter stroke with current opacity (형광펜 투명도 적용)
      final highlighterPaint = Paint()
        ..color = color.withOpacity(highlighterOpacity * opacity)
        ..strokeWidth = strokeWidth * scale
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      canvas.drawPath(path, highlighterPaint);

      // Add a subtle glow effect
      final glowPaint = Paint()
        ..color = color.withOpacity(highlighterOpacity * 0.4 * opacity)
        ..strokeWidth = (strokeWidth + 8) * scale
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);

      canvas.drawPath(path, glowPaint);
    }
  }

  @override
  bool shouldRepaint(_PresentationHighlighterPainter oldDelegate) {
    return trail.length != oldDelegate.trail.length ||
        scale != oldDelegate.scale ||
        offset != oldDelegate.offset ||
        color != oldDelegate.color ||
        strokeWidth != oldDelegate.strokeWidth ||
        opacity != oldDelegate.opacity ||
        highlighterOpacity != oldDelegate.highlighterOpacity;
  }
}

/// Template background painter - supports multiple page templates
class _TemplatePainter extends CustomPainter {
  final PageTemplate template;
  final bool isOverlay; // 배경 이미지 위에 표시되는 오버레이인지 여부

  _TemplatePainter({this.template = PageTemplate.blank, this.isOverlay = false});

  @override
  void paint(Canvas canvas, Size size) {
    // 오버레이일 때는 선을 더 강하게 (진하고 두껍게) 표시
    final paint = Paint()
      ..color = isOverlay ? Colors.grey.withOpacity(0.5) : Colors.grey.withOpacity(0.2)
      ..strokeWidth = isOverlay ? 1.0 : 0.5;

    switch (template) {
      case PageTemplate.blank:
        // No lines, just blank
        break;

      case PageTemplate.lined:
        // Horizontal lines only (like notebook)
        const lineSpacing = 30.0;
        const marginLeft = 80.0;

        // Draw left margin line (red) - 오버레이일 때 더 진하게
        final marginPaint = Paint()
          ..color = isOverlay ? Colors.red.withOpacity(0.6) : Colors.red.withOpacity(0.3)
          ..strokeWidth = isOverlay ? 1.5 : 1.0;
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
        // Dot grid - 오버레이일 때 더 진하고 크게
        const dotSpacing = 25.0;
        final dotPaint = Paint()
          ..color = isOverlay ? Colors.grey.withOpacity(0.7) : Colors.grey.withOpacity(0.4)
          ..strokeWidth = isOverlay ? 3.0 : 2.0
          ..strokeCap = StrokeCap.round;

        final dotRadius = isOverlay ? 1.5 : 1.0;
        for (double x = dotSpacing; x < size.width; x += dotSpacing) {
          for (double y = dotSpacing; y < size.height; y += dotSpacing) {
            canvas.drawCircle(Offset(x, y), dotRadius, dotPaint);
          }
        }
        break;

      case PageTemplate.cornell:
        // Cornell note-taking format - 오버레이일 때 더 강하게
        const cueColumnWidth = 150.0;
        const summaryHeight = 120.0;
        const lineSpacing = 30.0;

        final sectionPaint = Paint()
          ..color = isOverlay ? Colors.blue.withOpacity(0.6) : Colors.blue.withOpacity(0.3)
          ..strokeWidth = isOverlay ? 3.0 : 2.0;

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

        // Labels - 오버레이일 때 더 진하게
        final labelOpacity = isOverlay ? 0.7 : 0.4;
        final textPainter = TextPainter(
          textDirection: TextDirection.ltr,
        );

        // Cue label
        textPainter.text = TextSpan(
          text: 'CUE',
          style: TextStyle(
            color: Colors.blue.withOpacity(labelOpacity),
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
            color: Colors.blue.withOpacity(labelOpacity),
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
            color: Colors.blue.withOpacity(labelOpacity),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(10, size.height - summaryHeight + 10));
        break;

      case PageTemplate.customImage:
        // 커스텀 이미지 배경은 별도 위젯에서 렌더링
        // _TemplatePainter에서는 아무것도 그리지 않음
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _TemplatePainter oldDelegate) =>
      template != oldDelegate.template || isOverlay != oldDelegate.isOverlay;
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
  final Color lassoColor;
  // Shape preview
  final Offset? shapeStartPoint;
  final Offset? shapeEndPoint;
  final DrawingTool? shapeTool;
  final Color shapeColor;
  final double shapeWidth;

  _StrokePainter({
    required this.strokes,
    this.currentStroke,
    this.eraserPosition,
    this.eraserRadius = 10.0,
    this.lassoPath = const [],
    this.selectedStrokeIds = const {},
    this.selectionOffset = Offset.zero,
    this.selectionBounds,
    this.lassoColor = const Color(0xFF2196F3),
    this.shapeStartPoint,
    this.shapeEndPoint,
    this.shapeTool,
    this.shapeColor = Colors.black,
    this.shapeWidth = 2.0,
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

    // Draw shape preview
    if (shapeTool != null && shapeStartPoint != null && shapeEndPoint != null) {
      _drawShapePreview(canvas, shapeTool!, shapeStartPoint!, shapeEndPoint!);
    }

    // Draw lasso path - only when selection is complete (selectedStrokeIds.isNotEmpty)
    // During drawing, lasso path is rendered by _LassoOverlayPainter (outside RepaintBoundary)
    if (lassoPath.isNotEmpty && selectedStrokeIds.isNotEmpty) {
      // Semi-transparent fill for selected area
      final lassoFillPaint = Paint()
        ..color = lassoColor.withOpacity(0.08)
        ..style = PaintingStyle.fill;

      // Main lasso stroke paint
      final lassoPaint = Paint()
        ..color = lassoColor.withOpacity(0.8)
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
        ..color = lassoColor.withOpacity(0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      final handlePaint = Paint()
        ..color = lassoColor
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

  /// Draw shape preview while user is dragging
  void _drawShapePreview(Canvas canvas, DrawingTool tool, Offset start, Offset end) {
    final paint = Paint()
      ..color = shapeColor
      ..strokeWidth = shapeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (tool) {
      case DrawingTool.shapeLine:
        canvas.drawLine(start, end, paint);
        break;

      case DrawingTool.shapeRectangle:
        canvas.drawRect(Rect.fromPoints(start, end), paint);
        break;

      case DrawingTool.shapeCircle:
        final rect = Rect.fromPoints(start, end);
        canvas.drawOval(rect, paint);
        break;

      case DrawingTool.shapeArrow:
        // Draw main line
        canvas.drawLine(start, end, paint);

        // Draw arrowhead
        final dx = end.dx - start.dx;
        final dy = end.dy - start.dy;
        final length = math.sqrt(dx * dx + dy * dy);
        if (length >= 10) {
          final arrowSize = math.min(length * 0.2, 30.0);
          final angle = math.atan2(dy, dx);

          final arrowAngle1 = angle + math.pi * 0.85;
          final arrowAngle2 = angle - math.pi * 0.85;

          final arrow1 = Offset(
            end.dx + arrowSize * math.cos(arrowAngle1),
            end.dy + arrowSize * math.sin(arrowAngle1),
          );
          final arrow2 = Offset(
            end.dx + arrowSize * math.cos(arrowAngle2),
            end.dy + arrowSize * math.sin(arrowAngle2),
          );

          canvas.drawLine(end, arrow1, paint);
          canvas.drawLine(end, arrow2, paint);
        }
        break;

      default:
        break;
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

    // 도형인 경우 타입에 따라 다르게 그림
    if (stroke.isShape) {
      // 원/타원인 경우 drawOval로 직접 그림
      if (stroke.shapeType == ShapeType.circle) {
        // 포인트들로부터 bounding rect 계산
        double minX = double.infinity;
        double minY = double.infinity;
        double maxX = double.negativeInfinity;
        double maxY = double.negativeInfinity;

        for (final p in stroke.points) {
          if (p.x < minX) minX = p.x;
          if (p.y < minY) minY = p.y;
          if (p.x > maxX) maxX = p.x;
          if (p.y > maxY) maxY = p.y;
        }

        final ovalRect = Rect.fromLTRB(
          minX + offset.dx,
          minY + offset.dy,
          maxX + offset.dx,
          maxY + offset.dy,
        );

        // Draw highlight glow for selected strokes
        if (highlight) {
          final glowPaint = Paint()
            ..color = Colors.blue.withOpacity(0.3)
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..style = PaintingStyle.stroke
            ..strokeWidth = paint.strokeWidth + 6;
          canvas.drawOval(ovalRect, glowPaint);
        }

        canvas.drawOval(ovalRect, paint);
        return; // 원은 여기서 종료
      }

      // 그 외 도형은 직선으로 그림
      for (int i = 1; i < stroke.points.length; i++) {
        final p = stroke.points[i];
        path.lineTo(p.x + offset.dx, p.y + offset.dy);
      }
    } else {
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
    // Shape preview changes
    if (shapeStartPoint != oldDelegate.shapeStartPoint) return true;
    if (shapeEndPoint != oldDelegate.shapeEndPoint) return true;
    if (shapeTool != oldDelegate.shapeTool) return true;
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
      final center = bounds.center;

      // Save canvas state for rotation
      canvas.save();

      // Apply rotation around center
      if (canvasImage.rotation != 0) {
        canvas.translate(center.dx, center.dy);
        canvas.rotate(canvasImage.rotation);
        canvas.translate(-center.dx, -center.dy);
      }

      // Draw the image with opacity
      final srcRect = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
      final paint = Paint()..color = Color.fromRGBO(255, 255, 255, canvasImage.opacity);
      canvas.drawImageRect(image, srcRect, bounds, paint);

      // Draw selection border if selected
      if (isSelected) {
        final borderPaint = Paint()
          ..color = Colors.blue
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        canvas.drawRect(bounds, borderPaint);

        // Draw resize handles at corners
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

        // Draw rotation handle at top center
        final rotationHandlePos = Offset(center.dx, bounds.top - 30);
        canvas.drawLine(Offset(center.dx, bounds.top), rotationHandlePos,
          Paint()..color = Colors.blue..strokeWidth = 2);
        canvas.drawCircle(rotationHandlePos, 8, handleBorderPaint);
        canvas.drawCircle(rotationHandlePos, 6, Paint()..color = Colors.green);
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ImagePainter oldDelegate) {
    if (images.length != oldDelegate.images.length) return true;
    if (selectedImageId != oldDelegate.selectedImageId) return true;
    if (loadedImages.length != oldDelegate.loadedImages.length) return true;
    // 이미지 위치/크기/회전 변경 감지
    for (int i = 0; i < images.length; i++) {
      if (i >= oldDelegate.images.length) return true;
      final img = images[i];
      final oldImg = oldDelegate.images[i];
      if (img.position != oldImg.position) return true;
      if (img.size != oldImg.size) return true;
      if (img.rotation != oldImg.rotation) return true;
    }
    return false;
  }
}

/// Shape painter for rendering editable shapes on canvas
class _ShapePainter extends CustomPainter {
  final List<CanvasShape> shapes;
  final String? selectedShapeId;

  _ShapePainter({
    required this.shapes,
    this.selectedShapeId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final shape in shapes) {
      final isSelected = shape.id == selectedShapeId;
      final paint = Paint()
        ..color = shape.color
        ..strokeWidth = shape.strokeWidth
        ..style = shape.isFilled ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      switch (shape.type) {
        case CanvasShapeType.line:
          canvas.drawLine(shape.startPoint, shape.endPoint, paint);
          break;
        case CanvasShapeType.rectangle:
          canvas.drawRect(shape.bounds, paint);
          break;
        case CanvasShapeType.circle:
          final center = shape.center;
          final radius = (shape.endPoint - shape.startPoint).distance / 2;
          canvas.drawCircle(center, radius, paint);
          break;
        case CanvasShapeType.arrow:
          _drawArrow(canvas, shape.startPoint, shape.endPoint, paint);
          break;
        case CanvasShapeType.pdfBackground:
          // PDF 배경은 별도 렌더링 (이미지로 처리)
          break;
      }

      // Draw selection handles if selected
      if (isSelected) {
        final handlePaint = Paint()
          ..color = Colors.blue
          ..style = PaintingStyle.fill;
        final handleBorderPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;

        // Draw handles at start and end points
        for (final handle in shape.handles) {
          canvas.drawCircle(handle, 8, handleBorderPaint);
          canvas.drawCircle(handle, 6, handlePaint);
        }

        // Draw selection border
        final borderPaint = Paint()
          ..color = Colors.blue.withOpacity(0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
        canvas.drawRect(shape.bounds.inflate(5), borderPaint);
      }
    }
  }

  void _drawArrow(Canvas canvas, Offset start, Offset end, Paint paint) {
    // Draw line
    canvas.drawLine(start, end, paint);

    // Draw arrowhead
    final direction = (end - start);
    final length = direction.distance;
    if (length < 10) return;

    final normalized = direction / length;
    final arrowLength = (length * 0.2).clamp(10.0, 30.0);
    final arrowWidth = arrowLength * 0.5;

    final perpendicular = Offset(-normalized.dy, normalized.dx);
    final arrowBase = end - normalized * arrowLength;
    final arrowLeft = arrowBase + perpendicular * arrowWidth;
    final arrowRight = arrowBase - perpendicular * arrowWidth;

    final path = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(arrowLeft.dx, arrowLeft.dy)
      ..lineTo(arrowRight.dx, arrowRight.dy)
      ..close();

    canvas.drawPath(path, paint..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(covariant _ShapePainter oldDelegate) {
    if (shapes.length != oldDelegate.shapes.length) return true;
    if (selectedShapeId != oldDelegate.selectedShapeId) return true;
    // 도형 위치/크기 변경 감지
    for (int i = 0; i < shapes.length; i++) {
      if (shapes[i].startPoint != oldDelegate.shapes[i].startPoint) return true;
      if (shapes[i].endPoint != oldDelegate.shapes[i].endPoint) return true;
    }
    return false;
  }
}

/// Table painter for rendering tables on canvas
class _TablePainter extends CustomPainter {
  final List<CanvasTable> tables;
  final String? selectedTableId;
  final String? readyToDragId; // 드래그 준비 완료 상태 (1초 롱프레스 완료)
  final String? resizeWaitingTableId; // 리사이즈 대기 중인 테이블 ID
  final int resizeWaitingColumnIndex; // 리사이즈 대기 중인 컬럼 인덱스 (-1=없음, -99=왼쪽외곽)
  final int resizeWaitingRowIndex; // 리사이즈 대기 중인 행 인덱스 (-1=없음)
  final bool isResizeActive; // 리사이즈 활성화 상태 (롱프레스 완료)

  // 성능 최적화: TextPainter 캐시 (tableId:row:col -> TextPainter)
  static final Map<String, TextPainter> _textPainterCache = {};
  static const int _maxCacheSize = 500;

  _TablePainter({
    required this.tables,
    this.selectedTableId,
    this.readyToDragId,
    this.resizeWaitingTableId,
    this.resizeWaitingColumnIndex = -1,
    this.resizeWaitingRowIndex = -1,
    this.isResizeActive = false,
  });

  /// 캐시된 TextPainter 가져오기 또는 생성
  TextPainter _getCachedTextPainter(String cacheKey, String content, Color color, double maxWidth) {
    final cached = _textPainterCache[cacheKey];
    if (cached != null) {
      return cached;
    }

    // 캐시 크기 제한
    if (_textPainterCache.length >= _maxCacheSize) {
      // 절반 제거 (LRU 대신 간단한 방식)
      final keysToRemove = _textPainterCache.keys.take(_maxCacheSize ~/ 2).toList();
      for (final key in keysToRemove) {
        _textPainterCache.remove(key);
      }
    }

    final textPainter = TextPainter(
      text: TextSpan(
        text: content,
        style: TextStyle(
          color: color,
          fontSize: 12,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(maxWidth: maxWidth);
    _textPainterCache[cacheKey] = textPainter;
    return textPainter;
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final table in tables) {
      final isSelected = table.id == selectedTableId;

      // Draw table border
      final borderPaint = Paint()
        ..color = table.borderColor
        ..strokeWidth = table.borderWidth
        ..style = PaintingStyle.stroke;

      // Draw outer border
      canvas.drawRect(table.bounds, borderPaint);

      // Draw grid lines (using individual column/row sizes)
      // Horizontal lines (row borders)
      for (int i = 1; i < table.rows; i++) {
        final y = table.getRowY(i);
        canvas.drawLine(
          Offset(table.position.dx, y),
          Offset(table.position.dx + table.width, y),
          borderPaint,
        );
      }

      // Vertical lines (column borders)
      for (int i = 1; i < table.columns; i++) {
        final x = table.getColumnX(i);
        canvas.drawLine(
          Offset(x, table.position.dy),
          Offset(x, table.position.dy + table.height),
          borderPaint,
        );
      }

      // Draw cell contents (성능 최적화: TextPainter 캐시 사용)
      for (int row = 0; row < table.rows; row++) {
        for (int col = 0; col < table.columns; col++) {
          final content = table.cellContents[row][col];
          if (content.isNotEmpty) {
            final cellBounds = table.getCellBounds(row, col);
            // 캐시 키: tableId:row:col:content:color:width
            final cacheKey = '${table.id}:$row:$col:$content:${table.borderColor.value}:${cellBounds.width.toInt()}';
            final textPainter = _getCachedTextPainter(
              cacheKey,
              content,
              table.borderColor,
              cellBounds.width - 4,
            );
            textPainter.paint(
              canvas,
              Offset(cellBounds.left + 2, cellBounds.top + 2),
            );
          }
        }
      }

      // Draw selection highlight if selected
      if (isSelected) {
        final selectionPaint = Paint()
          ..color = Colors.blue.withOpacity(0.2)
          ..style = PaintingStyle.fill;
        canvas.drawRect(table.bounds, selectionPaint);

        final selectionBorderPaint = Paint()
          ..color = Colors.blue
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;
        canvas.drawRect(table.bounds, selectionBorderPaint);
      }

      // 드래그 준비 완료 표시 (1초 롱프레스 완료 시)
      final isReadyToDrag = table.id == readyToDragId;
      if (isReadyToDrag) {
        // 주황색 테두리로 드래그 준비 상태 표시
        final readyPaint = Paint()
          ..color = Colors.orange.withOpacity(0.3)
          ..style = PaintingStyle.fill;
        canvas.drawRect(table.bounds, readyPaint);

        final readyBorderPaint = Paint()
          ..color = Colors.orange
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke;
        canvas.drawRect(table.bounds, readyBorderPaint);

        // 이동 아이콘 표시 (표 중앙)
        final center = table.bounds.center;
        final iconPaint = Paint()
          ..color = Colors.orange
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

        // 십자 화살표 그리기
        const arrowSize = 15.0;
        // 상
        canvas.drawLine(center, Offset(center.dx, center.dy - arrowSize), iconPaint);
        canvas.drawLine(Offset(center.dx, center.dy - arrowSize), Offset(center.dx - 5, center.dy - arrowSize + 5), iconPaint);
        canvas.drawLine(Offset(center.dx, center.dy - arrowSize), Offset(center.dx + 5, center.dy - arrowSize + 5), iconPaint);
        // 하
        canvas.drawLine(center, Offset(center.dx, center.dy + arrowSize), iconPaint);
        canvas.drawLine(Offset(center.dx, center.dy + arrowSize), Offset(center.dx - 5, center.dy + arrowSize - 5), iconPaint);
        canvas.drawLine(Offset(center.dx, center.dy + arrowSize), Offset(center.dx + 5, center.dy + arrowSize - 5), iconPaint);
        // 좌
        canvas.drawLine(center, Offset(center.dx - arrowSize, center.dy), iconPaint);
        canvas.drawLine(Offset(center.dx - arrowSize, center.dy), Offset(center.dx - arrowSize + 5, center.dy - 5), iconPaint);
        canvas.drawLine(Offset(center.dx - arrowSize, center.dy), Offset(center.dx - arrowSize + 5, center.dy + 5), iconPaint);
        // 우
        canvas.drawLine(center, Offset(center.dx + arrowSize, center.dy), iconPaint);
        canvas.drawLine(Offset(center.dx + arrowSize, center.dy), Offset(center.dx + arrowSize - 5, center.dy - 5), iconPaint);
        canvas.drawLine(Offset(center.dx + arrowSize, center.dy), Offset(center.dx + arrowSize - 5, center.dy + 5), iconPaint);
      }

      // 리사이즈 대기/활성화 상태 표시
      final isResizeWaiting = table.id == resizeWaitingTableId;

      // 왼쪽 외곽 드래그 대기 상태 표시 (col=-99는 왼쪽 외곽 특수 값)
      if (isResizeWaiting && resizeWaitingColumnIndex == -99) {
        // 왼쪽 외곽은 주황색으로 표시 (이동 대기)
        final leftEdgePaint = Paint()
          ..color = Colors.orange
          ..strokeWidth = isResizeActive ? 4.0 : 3.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

        // 왼쪽 경계선 하이라이트
        canvas.drawLine(
          Offset(table.position.dx, table.position.dy - 5),
          Offset(table.position.dx, table.position.dy + table.height + 5),
          leftEdgePaint,
        );

        // 이동 아이콘 (좌우 화살표)
        final centerY = table.position.dy + table.height / 2;
        final x = table.position.dx;
        final arrowPaint = Paint()
          ..color = Colors.orange
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

        // 좌
        canvas.drawLine(Offset(x - 8, centerY), Offset(x - 3, centerY), arrowPaint);
        canvas.drawLine(Offset(x - 8, centerY), Offset(x - 5, centerY - 3), arrowPaint);
        canvas.drawLine(Offset(x - 8, centerY), Offset(x - 5, centerY + 3), arrowPaint);
        // 우
        canvas.drawLine(Offset(x + 3, centerY), Offset(x + 8, centerY), arrowPaint);
        canvas.drawLine(Offset(x + 8, centerY), Offset(x + 5, centerY - 3), arrowPaint);
        canvas.drawLine(Offset(x + 8, centerY), Offset(x + 5, centerY + 3), arrowPaint);
      }

      // 위쪽 외곽 리사이즈 대기 상태 표시 (row=-99는 위쪽 외곽 특수 값)
      if (isResizeWaiting && resizeWaitingRowIndex == -99) {
        // 위쪽 외곽은 주황색으로 표시 (첫 번째 행 리사이즈)
        final topEdgePaint = Paint()
          ..color = Colors.orange
          ..strokeWidth = isResizeActive ? 4.0 : 3.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

        // 위쪽 경계선 하이라이트
        canvas.drawLine(
          Offset(table.position.dx - 5, table.position.dy),
          Offset(table.position.dx + table.width + 5, table.position.dy),
          topEdgePaint,
        );

        // 리사이즈 아이콘 (상하 화살표)
        final centerX = table.position.dx + table.width / 2;
        final y = table.position.dy;
        final arrowPaint = Paint()
          ..color = Colors.orange
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

        // 상
        canvas.drawLine(Offset(centerX, y - 8), Offset(centerX, y - 3), arrowPaint);
        canvas.drawLine(Offset(centerX, y - 8), Offset(centerX - 3, y - 5), arrowPaint);
        canvas.drawLine(Offset(centerX, y - 8), Offset(centerX + 3, y - 5), arrowPaint);
        // 하
        canvas.drawLine(Offset(centerX, y + 3), Offset(centerX, y + 8), arrowPaint);
        canvas.drawLine(Offset(centerX, y + 8), Offset(centerX - 3, y + 5), arrowPaint);
        canvas.drawLine(Offset(centerX, y + 8), Offset(centerX + 3, y + 5), arrowPaint);
      }

      if (isResizeWaiting && (resizeWaitingColumnIndex >= 0 || resizeWaitingRowIndex >= 0)) {
        // 첫 번째 경계선 여부 판단 (왼쪽에서 첫 번째, 위에서 첫 번째)
        // col=0: 첫 번째 컬럼의 오른쪽 경계선 (왼쪽에서 가장 가까운 내부 경계선)
        // row=0: 첫 번째 행의 아래쪽 경계선 (위에서 가장 가까운 내부 경계선)
        final isFirstBorder =
            (resizeWaitingColumnIndex == 0) ||
            (resizeWaitingRowIndex == 0);

        // 첫 번째 경계선(왼쪽/위쪽에 가까운)은 주황색, 나머지는 파란색
        final borderColor = isFirstBorder ? Colors.orange : Colors.blue;
        final borderWidth = isResizeActive ? 4.0 : 3.0;

        final resizePaint = Paint()
          ..color = borderColor
          ..strokeWidth = borderWidth
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

        if (resizeWaitingColumnIndex >= 0) {
          // 컬럼 경계선 하이라이트
          final x = table.getColumnX(resizeWaitingColumnIndex + 1);
          canvas.drawLine(
            Offset(x, table.position.dy - 5),
            Offset(x, table.position.dy + table.height + 5),
            resizePaint,
          );

          // 리사이즈 아이콘 (좌우 화살표)
          final centerY = table.position.dy + table.height / 2;
          final arrowPaint = Paint()
            ..color = borderColor
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round;

          // 좌
          canvas.drawLine(Offset(x - 8, centerY), Offset(x - 3, centerY), arrowPaint);
          canvas.drawLine(Offset(x - 8, centerY), Offset(x - 5, centerY - 3), arrowPaint);
          canvas.drawLine(Offset(x - 8, centerY), Offset(x - 5, centerY + 3), arrowPaint);
          // 우
          canvas.drawLine(Offset(x + 3, centerY), Offset(x + 8, centerY), arrowPaint);
          canvas.drawLine(Offset(x + 8, centerY), Offset(x + 5, centerY - 3), arrowPaint);
          canvas.drawLine(Offset(x + 8, centerY), Offset(x + 5, centerY + 3), arrowPaint);
        }

        if (resizeWaitingRowIndex >= 0) {
          // 행 경계선 하이라이트
          final y = table.getRowY(resizeWaitingRowIndex + 1);
          canvas.drawLine(
            Offset(table.position.dx - 5, y),
            Offset(table.position.dx + table.width + 5, y),
            resizePaint,
          );

          // 리사이즈 아이콘 (상하 화살표)
          final centerX = table.position.dx + table.width / 2;
          final arrowPaint = Paint()
            ..color = borderColor
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round;

          // 상
          canvas.drawLine(Offset(centerX, y - 8), Offset(centerX, y - 3), arrowPaint);
          canvas.drawLine(Offset(centerX, y - 8), Offset(centerX - 3, y - 5), arrowPaint);
          canvas.drawLine(Offset(centerX, y - 8), Offset(centerX + 3, y - 5), arrowPaint);
          // 하
          canvas.drawLine(Offset(centerX, y + 3), Offset(centerX, y + 8), arrowPaint);
          canvas.drawLine(Offset(centerX, y + 8), Offset(centerX - 3, y + 5), arrowPaint);
          canvas.drawLine(Offset(centerX, y + 8), Offset(centerX + 3, y + 5), arrowPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TablePainter oldDelegate) {
    // 성능 최적화: 빠른 체크 먼저 수행
    if (tables.length != oldDelegate.tables.length) return true;
    if (selectedTableId != oldDelegate.selectedTableId) return true;
    if (readyToDragId != oldDelegate.readyToDragId) return true;
    if (resizeWaitingTableId != oldDelegate.resizeWaitingTableId) return true;
    if (resizeWaitingColumnIndex != oldDelegate.resizeWaitingColumnIndex) return true;
    if (resizeWaitingRowIndex != oldDelegate.resizeWaitingRowIndex) return true;
    if (isResizeActive != oldDelegate.isResizeActive) return true;

    // 성능 최적화: identical 체크로 대부분의 경우 빠르게 반환
    if (identical(tables, oldDelegate.tables)) return false;

    // 표 변경 감지 (위치/크기/구조만 체크, 개별 열/행 순회 최소화)
    for (int i = 0; i < tables.length; i++) {
      final table = tables[i];
      final oldTable = oldDelegate.tables[i];

      // 기본 속성 비교 (O(1))
      if (table.id != oldTable.id) return true;
      if (table.position != oldTable.position) return true;
      if (table.rows != oldTable.rows) return true;
      if (table.columns != oldTable.columns) return true;

      // 성능 최적화: 전체 크기 비교로 대부분의 변경 감지
      if (table.width != oldTable.width) return true;
      if (table.height != oldTable.height) return true;

      // 셀 내용 변경 감지 (identical 먼저 체크)
      if (!identical(table.cellContents, oldTable.cellContents)) {
        // cellContents가 다른 인스턴스면 내용 비교
        for (int r = 0; r < table.rows; r++) {
          for (int c = 0; c < table.columns; c++) {
            if (table.cellContents[r][c] != oldTable.cellContents[r][c]) {
              return true;
            }
          }
        }
      }
    }
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

/// 커스텀 배경 이미지 위젯
/// 전체 캔버스 크기에 맞게 이미지를 렌더링
class _BackgroundImageWidget extends StatelessWidget {
  final String imagePath;
  final ui.Image? loadedImage;

  const _BackgroundImageWidget({
    required this.imagePath,
    this.loadedImage,
  });

  @override
  Widget build(BuildContext context) {
    if (loadedImage == null) {
      // 이미지 로딩 중 - 로딩 인디케이터 또는 빈 컨테이너
      return const SizedBox.expand(
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return CustomPaint(
      painter: _BackgroundImagePainter(image: loadedImage!),
      size: Size.infinite,
    );
  }
}

/// 배경 이미지 페인터
/// 캔버스 전체에 이미지를 채워서 렌더링 (cover 모드 - 전체 채움)
class _BackgroundImagePainter extends CustomPainter {
  final ui.Image image;

  _BackgroundImagePainter({required this.image});

  @override
  void paint(Canvas canvas, Size size) {
    // 배경을 흰색으로 채움 (투명 이미지 대비)
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white,
    );

    // cover 모드: 이미지가 캔버스 전체를 채우도록 (비율 유지, 잘릴 수 있음)
    final imageAspect = image.width / image.height;
    final canvasAspect = size.width / size.height;

    double srcWidth, srcHeight;
    double srcOffsetX = 0, srcOffsetY = 0;

    if (imageAspect > canvasAspect) {
      // 이미지가 더 넓음 - 세로에 맞추고 가로 중앙 잘라냄
      srcHeight = image.height.toDouble();
      srcWidth = srcHeight * canvasAspect;
      srcOffsetX = (image.width - srcWidth) / 2;
    } else {
      // 이미지가 더 높음 - 가로에 맞추고 세로 중앙 잘라냄
      srcWidth = image.width.toDouble();
      srcHeight = srcWidth / canvasAspect;
      srcOffsetY = (image.height - srcHeight) / 2;
    }

    final srcRect = Rect.fromLTWH(srcOffsetX, srcOffsetY, srcWidth, srcHeight);
    final destRect = Rect.fromLTWH(0, 0, size.width, size.height);

    // 15% 투명도로 배경 이미지 렌더링 (필기가 더 잘 보이도록)
    final paint = Paint()
      ..colorFilter = const ColorFilter.matrix(<double>[
        1, 0, 0, 0, 0,    // R
        0, 1, 0, 0, 0,    // G
        0, 0, 1, 0, 0,    // B
        0, 0, 0, 0.15, 0, // A (15% 투명도)
      ]);
    canvas.drawImageRect(image, srcRect, destRect, paint);
  }

  @override
  bool shouldRepaint(covariant _BackgroundImagePainter oldDelegate) =>
      image != oldDelegate.image;
}
