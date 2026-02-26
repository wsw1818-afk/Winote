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
import '../../../core/services/stroke_cache_service.dart';
import '../../../core/providers/drawing_state.dart';
import 'painters/canvas_painters.dart';
import 'package:flutter/services.dart';

/// 배경 이미지 글로벌 캐시 (노트 간 공유)
class _BackgroundImageCache {
  static final Map<String, ui.Image> _cache = {};
  static const int _maxCacheSize = 10; // 최대 10개 이미지 캐시

  static ui.Image? get(String path) => _cache[path];

  static bool contains(String? path) => path != null && _cache.containsKey(path);

  static void put(String path, ui.Image image) {
    // 캐시 크기 제한
    if (_cache.length >= _maxCacheSize && !_cache.containsKey(path)) {
      // 가장 오래된 항목 제거 (첫 번째 항목)
      final oldestKey = _cache.keys.first;
      _cache[oldestKey]?.dispose();
      _cache.remove(oldestKey);
    }
    _cache[path] = image;
  }

  static void clear() {
    for (final image in _cache.values) {
      image.dispose();
    }
    _cache.clear();
  }
}

/// 롱프레스 드래그 대상 요소 타입
enum _DragElementType { shape, table }

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
  // 도구 변경 콜백 (롱프레스 메뉴에서 올가미 도구 전환 시)
  final void Function(DrawingTool tool)? onToolChanged;
  // 필압 민감도 (0.0 ~ 1.0)
  final double pressureSensitivity;
  // S펜 호버 커서 표시 여부
  final bool penHoverCursorEnabled;
  // 다크 캔버스 모드 (검은 배경 + 밝은 템플릿 라인)
  final bool darkCanvasMode;

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
    this.onToolChanged,
    this.pressureSensitivity = 0.6,
    this.penHoverCursorEnabled = true,
    this.darkCanvasMode = false,
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

  // Stroke cache service (래스터 캐싱)
  final StrokeCacheService _cacheService = StrokeCacheService.instance;

  // 캐시된 스트로크 이미지 (성능 최적화)
  ui.Image? _cachedStrokesImage;
  bool _needsCacheUpdate = true;

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

  // Two-finger double-tap for Fit-to-Screen
  int? _lastTwoFingerTapTime;
  static const int _doubleTapMaxInterval = 400; // ms

  // Three-finger tap detection for Redo
  int? _threeFingerTapStartTime;
  List<Offset> _threeFingerTapStartPositions = [];
  bool _threeFingerMoved = false;

  // Palm rejection: S-Pen drawing state
  bool _isPenDrawing = false; // True when S-Pen is actively drawing
  int? _penDrawStartTime; // Time when pen started drawing
  int? _penHoverStartTime; // Time when pen started hovering (for palm rejection)
  static const int _palmRejectionGracePeriod = 1000; // 1초 grace period (펜 사용 후)

  // Auto-scroll when drawing near edge (for zoomed-in state)
  static const double _edgeScrollMargin = 60.0; // pixels from edge to trigger scroll
  static const double _edgeScrollSpeed = 8.0; // pixels per frame
  Size? _canvasSize;

  // Eraser tracking
  Offset? _lastErasePoint;

  /// 지우개 반경 계산 (커서와 실제 지우기 반경 일치)
  double get _eraserRadius => widget.eraserWidth / 2;

  /// 현재 뷰포트 영역 계산 (대용량 노트 최적화)
  Rect? get _visibleRect {
    if (_canvasSize == null) return null;
    // 화면 좌표를 캔버스 좌표로 변환
    final left = -_offset.dx / _scale;
    final top = -_offset.dy / _scale;
    final width = _canvasSize!.width / _scale;
    final height = _canvasSize!.height / _scale;
    // 약간의 여유를 두어 경계에서 깜빡임 방지
    return Rect.fromLTWH(left - 50, top - 50, width + 100, height + 100);
  }

  // Lasso selection
  List<Offset> _lassoPath = [];
  Set<String> _selectedStrokeIds = {};
  bool _isDraggingSelection = false;
  Offset? _selectionDragStart;
  Offset _selectionOffset = Offset.zero;

  // 스트로크 변경 추적 (색상/굵기 변경 시 Key 갱신용)
  int _strokeContentVersion = 0;

  // Area eraser
  List<Offset> _areaEraserPath = [];
  bool _isAreaEraserActive = false;

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
  _DragElementType? _pendingDragElementType;
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

  // 스트로크 롱프레스 올가미 메뉴 상태
  Timer? _strokeLongPressTimer;
  Offset? _strokeLongPressPosition; // 캔버스 좌표
  Offset? _strokeLongPressScreenPosition; // 화면 좌표 (메뉴 표시용)
  bool _showStrokeLassoMenu = false;
  String? _longPressedStrokeId; // 롱프레스한 스트로크 ID
  static const int _strokeLongPressDuration = 800; // 0.8초 (빠른 반응)

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
    // 템플릿 변경 로그
    if (widget.pageTemplate != oldWidget.pageTemplate) {
      debugPrint('[DrawingCanvas] 템플릿 변경됨: ${oldWidget.pageTemplate} -> ${widget.pageTemplate}');
    }
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
    _strokeLongPressTimer?.cancel();

    // 이미지 캐시 정리
    for (final image in _loadedImages.values) {
      image.dispose();
    }
    _loadedImages.clear();

    // 배경 이미지 정리
    _loadedBackgroundImage?.dispose();
    _loadedBackgroundImage = null;

    // 스트로크 캐시 정리
    _cachedStrokesImage?.dispose();
    _cachedStrokesImage = null;

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
    if (_pendingDragElementType == _DragElementType.shape) {
      setState(() {
        _readyToDragShapeId = _pendingDragElementId;
        _selectedShapeId = _pendingDragElementId;
        _lastDeviceKind = 'Shape (ready to drag)';
        _selectedTableId = null;
        _selectedImageId = null;
        _selectedTextId = null;
      });
      widget.onShapeSelectionChanged?.call(true);
    } else if (_pendingDragElementType == _DragElementType.table) {
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

  /// Load background image for custom template (최적화됨)
  Future<void> _loadBackgroundImage(String path) async {
    // 이미 같은 이미지가 로드되어 있으면 스킵
    if (_lastBackgroundImagePath == path && _loadedBackgroundImage != null) {
      return;
    }

    // 글로벌 캐시에서 확인
    final cachedImage = _BackgroundImageCache.get(path);
    if (cachedImage != null) {
      if (mounted) {
        setState(() {
          _loadedBackgroundImage = cachedImage;
          _lastBackgroundImagePath = path;
        });
      }
      debugPrint('[DrawingCanvas] Background image loaded from cache: $path');
      return;
    }

    try {
      final file = File(path);
      if (!await file.exists()) {
        debugPrint('[DrawingCanvas] Background image not found: $path');
        return;
      }

      // 기존 배경 이미지 정리 (글로벌 캐시에 있으면 dispose하지 않음)
      if (_loadedBackgroundImage != null && !_BackgroundImageCache.contains(_lastBackgroundImagePath)) {
        _loadedBackgroundImage?.dispose();
      }

      final bytes = await file.readAsBytes();

      // 이미지 리사이즈: 최대 2048px로 제한하여 메모리 절약 + 로딩 속도 향상
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 2048, // 최대 너비 제한
      );
      final frame = await codec.getNextFrame();

      // 글로벌 캐시에 저장
      _BackgroundImageCache.put(path, frame.image);

      if (mounted) {
        setState(() {
          _loadedBackgroundImage = frame.image;
          _lastBackgroundImagePath = path;
        });
      }
      debugPrint('[DrawingCanvas] Background image loaded and cached: $path (${frame.image.width}x${frame.image.height})');
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
    // 캐시 무효화
    _invalidateStrokeCache();
  }

  /// 스트로크 캐시 무효화 (스트로크 변경 시 호출)
  void _invalidateStrokeCache() {
    _needsCacheUpdate = true;
    _cacheService.invalidateCache();
  }

  /// 스트로크 캐시 업데이트 (비동기)
  /// 스트로크가 완료되거나 변경되었을 때 호출
  Future<void> _updateStrokeCache() async {
    if (!_needsCacheUpdate || _canvasSize == null || _canvasSize!.isEmpty) return;
    if (_strokes.isEmpty) {
      _cachedStrokesImage?.dispose();
      _cachedStrokesImage = null;
      _needsCacheUpdate = false;
      return;
    }
    
    // 캐시 서비스를 통해 스트로크를 이미지로 렌더링
    final cachedImage = await _cacheService.cacheStrokes(
      _strokes,
      _canvasSize!,
      null, // 제외할 스트로크 없음
    );
    
    if (cachedImage != null && mounted) {
      _cachedStrokesImage?.dispose();
      _cachedStrokesImage = cachedImage;
      _needsCacheUpdate = false;
      // 캐시 업데이트 후 다시 그리기
      setState(() {});
    }
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
    // 리사이즈 시작 좌표 및 원본 크기 초기화 (메모리 누수 방지)
    _resizeStartX = 0;
    _resizeStartY = 0;
    _originalColumnWidth = 0;
    _originalRowHeight = 0;
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

  // Performance tracking (disabled)

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
          onPointerHover: _onPointerHover, // 펜 호버링 감지 (Palm rejection용)
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
                    BackgroundImageWidget(
                      imagePath: widget.backgroundImagePath!,
                      loadedImage: _loadedBackgroundImage,
                    ),
                    // 오버레이 템플릿 (배경 이미지 위에 표시되는 줄/격자/점 등) - 강한 선으로 표시
                    if (widget.overlayTemplate != null && widget.overlayTemplate != PageTemplate.blank && widget.overlayTemplate != PageTemplate.customImage)
                      CustomPaint(
                        painter: TemplatePainter(template: widget.overlayTemplate!, isOverlay: true, darkMode: widget.darkCanvasMode),
                        size: Size.infinite,
                      ),
                  ] else
                    // 기본 템플릿 배경
                    CustomPaint(
                      painter: TemplatePainter(template: widget.pageTemplate, darkMode: widget.darkCanvasMode),
                      size: Size.infinite,
                    ),
                  // Images layer - Key 최적화: 개수만으로 Key 결정 (선택 상태는 shouldRepaint로 처리)
                  RepaintBoundary(
                    key: ValueKey('images_${_images.length}'),
                    child: CustomPaint(
                      painter: ImagePainter(
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
                      painter: ShapePainter(
                        shapes: _shapes,
                        selectedShapeId: _selectedShapeId,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                  // Tables layer - 드래그/리사이즈 중에는 매 프레임 업데이트 필요
                  // RepaintBoundary 제거하여 실시간 렌더링 보장
                  CustomPaint(
                    painter: TablePainter(
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
                      painter: CanvasTextPainter(
                        texts: _texts,
                        selectedTextId: _selectedTextId,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                  // Drawing area with RepaintBoundary for performance
                  // Key 최적화: 지우개 위치는 Key에서 제외하여 불필요한 rebuild 방지
                  // StrokePainter의 shouldRepaint가 지우개 위치 변경 시 repaint만 수행
                  RepaintBoundary(
                    key: ValueKey('strokes_${_strokes.length}_${_selectedStrokeIds.length}_$_strokeContentVersion'),
                    child: CustomPaint(
                      painter: StrokePainter(
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
                        // 대용량 노트 최적화: 뷰포트 밖 스트로크 렌더링 스킵
                        visibleRect: _visibleRect,
                        // 캐시된 스트로크 이미지 (성능 최적화)
                        cachedStrokesImage: _cachedStrokesImage,
                        canvasSize: _canvasSize,
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
                painter: LassoOverlayPainter(
                  lassoPath: _lassoPath,
                  scale: _scale,
                  offset: _offset,
                  lassoColor: widget.lassoColor,
                ),
              ),
            ),
          ),
        // Area eraser overlay
        if (widget.drawingTool == DrawingTool.areaEraser && _areaEraserPath.isNotEmpty)
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: CustomPaint(
                key: ValueKey('area_eraser_overlay_${_areaEraserPath.length}'),
                isComplex: true,
                willChange: true,
                painter: AreaEraserOverlayPainter(
                  path: _areaEraserPath,
                  scale: _scale,
                  offset: _offset,
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
                painter: LaserPointerPainter(
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
                painter: PresentationHighlighterPainter(
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
                    // 롱프레스 디버그 정보
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: _strokeLongPressTimer != null ? Colors.orange.withValues(alpha: 0.3 ) : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '롱프레스: ${_strokeLongPressTimer != null ? "대기중" : "없음"}',
                            style: TextStyle(
                              color: _strokeLongPressTimer != null ? Colors.orange : Colors.white70,
                              fontSize: 11,
                              fontWeight: _strokeLongPressTimer != null ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          if (_longPressedStrokeId != null && _longPressedStrokeId!.isNotEmpty)
                            Text(
                              '대상 스트로크: ${_longPressedStrokeId!.length >= 8 ? _longPressedStrokeId!.substring(0, 8) : _longPressedStrokeId!}...',
                              style: const TextStyle(color: Colors.yellow, fontSize: 10),
                            ),
                          Text(
                            '메뉴표시: ${_showStrokeLassoMenu ? "YES" : "NO"}',
                            style: TextStyle(
                              color: _showStrokeLassoMenu ? Colors.green : Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            '선택된 스트로크: ${_selectedStrokeIds.length}개',
                            style: TextStyle(
                              color: _selectedStrokeIds.isNotEmpty ? Colors.cyan : Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
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
        // 스트로크 롱프레스 올가미 메뉴
        if (_showStrokeLassoMenu && _strokeLongPressScreenPosition != null)
          _buildStrokeLassoMenu(),
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
    ),);

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
                color: Colors.black.withValues(alpha: 0.3 ),
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
    ),);

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
                color: Colors.black.withValues(alpha: 0.3 ),
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

  /// 스트로크 롱프레스 올가미 미니 툴바 위젯
  Widget _buildStrokeLassoMenu() {
    if (_strokeLongPressScreenPosition == null || _selectedStrokeIds.isEmpty) {
      return const SizedBox.shrink();
    }

    // 미니 툴바 위치 계산
    const toolbarWidth = 240.0;
    const toolbarHeight = 44.0;
    final screenSize = _canvasSize ?? const Size(400, 600);
    const minTopMargin = 70.0; // 상단 여백 (AppBar 등 고려)

    // 선택 영역의 bounds 가져오기
    final bounds = _getSelectionBounds();

    // 화면 경계를 넘지 않도록 위치 조정
    double left = _strokeLongPressScreenPosition!.dx - toolbarWidth / 2;
    double top;

    // 선택 영역 상단이 툴바+여백보다 충분한 공간이 있으면 위에 표시, 아니면 아래에 표시
    if (bounds != null && bounds.top < minTopMargin + toolbarHeight + 20) {
      // 위에 공간이 부족하면 선택 영역 아래쪽에 표시
      top = bounds.bottom + 20;
    } else {
      // 기본: 선택 영역 위쪽에 표시
      top = _strokeLongPressScreenPosition!.dy - toolbarHeight - 20;
    }

    // 왼쪽 경계
    if (left < 8) left = 8;
    // 오른쪽 경계
    if (left + toolbarWidth > screenSize.width - 8) {
      left = screenSize.width - toolbarWidth - 8;
    }
    // 아래쪽 경계 (화면 밖으로 나가지 않도록)
    if (top + toolbarHeight > screenSize.height - 8) {
      top = screenSize.height - toolbarHeight - 8;
    }
    // 위쪽 경계 (최소값)
    if (top < 8) {
      top = 8;
    }

    return Positioned(
      left: left,
      top: top,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(24),
        color: Colors.grey[850],
        child: Container(
          height: toolbarHeight,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 선택 개수 표시
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.2 ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_selectedStrokeIds.length}개',
                  style: const TextStyle(
                    color: Colors.blue,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // 글씨 변경 버튼 (색상 + 굵기)
              _buildMiniToolbarButton(
                icon: Icons.edit,
                tooltip: '글씨 변경',
                color: Colors.amber[300],
                onTap: () {
                  _showStrokeEditDialog();
                },
              ),
              // 변형 버튼 (회전/크기)
              _buildMiniToolbarButton(
                icon: Icons.transform,
                tooltip: '변형',
                color: Colors.lightBlue[300],
                onTap: () {
                  _showTransformDialog();
                },
              ),
              // 복사 버튼
              _buildMiniToolbarButton(
                icon: Icons.copy,
                tooltip: '복사',
                onTap: () {
                  copySelection();
                  _closeStrokeLassoMenu();
                },
              ),
              // 삭제 버튼
              _buildMiniToolbarButton(
                icon: Icons.delete_outline,
                tooltip: '삭제',
                color: Colors.red[300],
                onTap: () {
                  deleteSelection();
                  _closeStrokeLassoMenu();
                },
              ),
              // 닫기 버튼
              _buildMiniToolbarButton(
                icon: Icons.close,
                tooltip: '선택 해제',
                onTap: () {
                  setState(() {
                    _selectedStrokeIds.clear();
                    _lassoPath.clear();
                  });
                  _closeStrokeLassoMenu();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 미니 툴바 버튼 위젯
  Widget _buildMiniToolbarButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color? color,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(icon, color: color ?? Colors.white70, size: 20),
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
        // 올바른 키 사용: _loadedImages는 imagePath를 키로 사용
        _loadedImages[imageToRemove.imagePath]?.dispose();
        _loadedImages.remove(imageToRemove.imagePath);
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
    _imageDeleteLongPressTimer = Timer(const Duration(milliseconds: _longPressDuration), () {
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
            color: Colors.black.withValues(alpha: 0.1 ),
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
      _scale = (_scale * factor).clamp(1.0, 3.0);
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

    // S-Pen 뒤집기(invertedStylus) 감지 시 자동으로 지우개로 전환
    if (event.kind == PointerDeviceKind.invertedStylus) {
      _log('=== INVERTED STYLUS DETECTED === Switching to eraser');
      widget.onToolChanged?.call(DrawingTool.eraser);
      // 현재 이벤트는 지우개로 처리하지 않고 반환 (다음 이벤트부터 지우개로 동작)
      return;
    }

    // Track if finger tapped on element (set in finger touch block)
    bool tappedOnElement = false;

    // ========== PALM REJECTION (최우선 처리) ==========
    // 펜 필기 중이거나 펜 사용 직후에는 모든 터치 입력을 무시
    // 이 체크를 가장 먼저 수행하여 손바닥 터치가 줌/팬을 트리거하는 것을 방지
    if (isFingerTouch) {
      // 펜 필기 중이면 터치 무시
      if (_isPenDrawing) {
        _perfLog('FINGER IGNORED (pen drawing)', inputType: 'TOUCH', pos: event.localPosition);
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      // 펜 사용 후 grace period 동안 터치 무시 (손바닥 접촉 방지)
      if (_penDrawStartTime != null && (now - _penDrawStartTime!) < _palmRejectionGracePeriod) {
        _perfLog('FINGER IGNORED (pen grace period ${now - _penDrawStartTime!}ms)', inputType: 'TOUCH', pos: event.localPosition);
        return;
      }
      // 펜 호버링 후 grace period 동안 터치 무시
      if (_penHoverStartTime != null && (now - _penHoverStartTime!) < _palmRejectionGracePeriod) {
        _perfLog('FINGER IGNORED (pen hover grace ${now - _penHoverStartTime!}ms)', inputType: 'TOUCH', pos: event.localPosition);
        return;
      }
    }
    // ========== END PALM REJECTION ==========

    // 올가미/레이저포인터/프레젠테이션형광펜/영역지우개 도구: S-Pen이 touch로 감지되어도 첫 포인터는 해당 도구로 처리
    // Windows에서 S-Pen은 종종 touch로 감지되므로, 이 도구들 선택 시 첫 터치를 허용
    final isSpecialTool = widget.drawingTool == DrawingTool.lasso ||
                          widget.drawingTool == DrawingTool.laserPointer ||
                          widget.drawingTool == DrawingTool.presentationHighlighter ||
                          widget.drawingTool == DrawingTool.areaEraser;
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

        // If 3+ fingers, start three-finger gesture detection
        if (_activePointers.length >= 3) {
          _isGesturing = true;
          // Start three-finger tap detection
          final positions = _activePointers.values.toList();
          _threeFingerTapStartTime = DateTime.now().millisecondsSinceEpoch;
          _threeFingerTapStartPositions = List.from(positions.take(3));
          _threeFingerMoved = false;

          _perfLog('THREE-FINGER start', inputType: 'MULTI-TOUCH');
          return;
        }

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
    final now = DateTime.now().millisecondsSinceEpoch;
    _penDrawStartTime = now;
    _penHoverStartTime = now; // 펜 터치 시 호버 타임도 업데이트 (Palm rejection용)
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
          _pendingDragElementType = _DragElementType.shape;
          _longPressTriggered = false;
          _shapeDragStart = canvasPosForHitTest;

          // 1초 후 롱프레스 트리거 (타이머 사용)
          _perfLog('TIMER_START', inputType: 'select-shape:${shape.id}', pos: canvasPosForHitTest);
          _longPressTimer = Timer(const Duration(milliseconds: _longPressDuration), () {
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
            _perfLog('TABLE_DRAG_FROM_LEFT_EDGE_ACTIVATED', inputType: 'table=$_resizingTableId', pos: _resizeBorderStartPos);
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
            _perfLog('TABLE_TOP_EDGE_RESIZE_ACTIVATED', inputType: 'table=$_resizingTableId', pos: _resizeBorderStartPos);
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
          _pendingDragElementType = _DragElementType.table;
          _longPressTriggered = false;
          _tableDragStart = canvasPosForHitTest;

          // 1초 후 롱프레스 트리거 (타이머 사용) - 선택, 드래그 및 삭제 버튼 표시
          debugPrint('TABLE_TIMER_START: tableId=${table.id}, duration=${_longPressDuration}ms');
          _perfLog('TIMER_START', inputType: 'select-table:${table.id}', pos: canvasPosForHitTest);
          final tableIdForTimer = table.id; // 클로저에서 사용할 ID 저장
          _longPressTimer = Timer(const Duration(milliseconds: _longPressDuration), () {
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
          // 드래그 시작 시 메뉴 숨김
          _showStrokeLassoMenu = false;
          _strokeLongPressScreenPosition = null;
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

    // Handle area eraser tool
    if (widget.drawingTool == DrawingTool.areaEraser) {
      final canvasPos = _screenToCanvas(event.localPosition);
      _log('AreaEraser DOWN at $canvasPos');

      // Start new area eraser path
      setState(() {
        _areaEraserPath = [canvasPos];
        _isAreaEraserActive = true;
        _inputCount++;
        _lastDeviceKind = 'AreaEraser';
      });
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
          _pendingDragElementType = _DragElementType.table;
          _longPressTriggered = false;
          _tableDragStart = canvasPos;
          // 펜으로 표 테두리 롱프레스 시 selectedTableId는 롱프레스 트리거 시에만 설정
          // (그리기 중에는 선택 표시 안함)

          // 1초 후 롱프레스 트리거 (타이머 사용) - 삭제 버튼 표시 포함
          final tableIdForTimer = table.id;
          _perfLog('TIMER_START', inputType: 'table:${table.id}', pos: canvasPos);
          _longPressTimer = Timer(const Duration(milliseconds: _longPressDuration), () {
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
            _pendingDragElementType = _DragElementType.shape;
            _longPressTriggered = false;
            _shapeDragStart = canvasPos;
            // 펜으로 도형 위 롱프레스 시 selectedShapeId는 롱프레스 트리거 시에만 설정
            // (그리기 중에는 선택 표시 안함)

            // 1초 후 롱프레스 트리거 (타이머 사용)
            _perfLog('TIMER_START', inputType: 'shape:${shape.id}', pos: canvasPos);
            _longPressTimer = Timer(const Duration(milliseconds: _longPressDuration), () {
              _perfLog('TIMER_FIRED', inputType: 'pendingId=$_pendingDragElementId,triggered=$_longPressTriggered', pos: _elementTapStartPos);
              if (_pendingDragElementId != null && !_longPressTriggered && mounted) {
                _triggerLongPressDrag();
              }
            });
            break;
          }
        }
      }

      // 스트로크 위 롱프레스 감지는 펜/형광펜 필기 중에는 하지 않음
      // 펜으로 필기할 때 기존 스트로크 위를 지나가면 올가미 메뉴가 뜨는 버그 방지
      // (올가미 메뉴는 올가미 도구 선택 시에만 표시되어야 함)
    }

    // Determine color based on tool
    Color strokeColor = widget.strokeColor;
    if (widget.drawingTool == DrawingTool.highlighter) {
      strokeColor = widget.strokeColor.withValues(alpha: widget.highlighterOpacity );
    }

    // 스무딩 서비스 초기화 (속도 버퍼 클리어)
    _smoothingService.beginStroke();

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
        // 스트로크 롱프레스 타이머도 취소
        _cancelStrokeLongPressTimer();
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

        // Check if three fingers moved significantly
        if (_threeFingerTapStartPositions.isNotEmpty && _activePointers.length >= 3) {
          final positions = _activePointers.values.toList();
          for (int i = 0; i < 3 && i < positions.length && i < _threeFingerTapStartPositions.length; i++) {
            final move = (positions[i] - _threeFingerTapStartPositions[i]).distance;
            if (move > _tapMaxMovement) {
              _threeFingerMoved = true;
              break;
            }
          }
        }

        if (_lastFocalPoint != null && _baseSpan > 0 && _canvasSize != null) {
          // 핀치 시작 시점 대비 스케일 변화율 계산
          final rawScaleFactor = currentSpan / _baseSpan;

          // 새 스케일 계산 (클램핑: 1.0x ~ 3.0x, 축소 시 공백 방지)
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

    // Handle area eraser
    if (widget.drawingTool == DrawingTool.areaEraser && event.pointer == _activePointerId && _isAreaEraserActive) {
      final canvasPos = _screenToCanvas(event.localPosition);
      setState(() {
        _areaEraserPath.add(canvasPos);
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

    // 스트로크 롱프레스 타이머 취소 (메뉴가 이미 표시된 경우는 유지)
    if (!_showStrokeLassoMenu) {
      _cancelStrokeLongPressTimer();
    }

    // Handle finger gesture end
    if (_activePointers.containsKey(event.pointer)) {
      _activePointers.remove(event.pointer);

      // Check for three-finger tap (Redo gesture)
      if (_activePointers.isEmpty && _threeFingerTapStartTime != null) {
        final tapDuration = DateTime.now().millisecondsSinceEpoch - _threeFingerTapStartTime!;

        if (tapDuration < _tapMaxDuration && !_threeFingerMoved) {
          // Three-finger tap detected - trigger Redo
          _perfLog('THREE-FINGER TAP', inputType: 'REDO');
          redo();
        }

        // Reset three-finger tap detection
        _threeFingerTapStartTime = null;
        _threeFingerTapStartPositions.clear();
        _threeFingerMoved = false;
      }

      // Check for two-finger tap (Undo) or double-tap (Fit-to-Screen)
      if (_activePointers.isEmpty && _twoFingerTapStartTime != null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final tapDuration = now - _twoFingerTapStartTime!;

        if (tapDuration < _tapMaxDuration && !_twoFingerMoved) {
          // Check for double-tap (Fit-to-Screen)
          if (_lastTwoFingerTapTime != null &&
              (now - _lastTwoFingerTapTime!) < _doubleTapMaxInterval) {
            // Two-finger double-tap detected - Fit to Screen
            _perfLog('TWO-FINGER DOUBLE-TAP', inputType: 'FIT-TO-SCREEN');
            _fitToScreen();
            _lastTwoFingerTapTime = null; // Reset to prevent triple-tap
          } else {
            // Two-finger single tap - trigger Undo
            _perfLog('TWO-FINGER TAP', inputType: 'UNDO');
            undo();
            _lastTwoFingerTapTime = now; // Record for double-tap detection
          }
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

    // Handle area eraser end
    if (widget.drawingTool == DrawingTool.areaEraser && _isAreaEraserActive) {
      _log('AreaEraser UP: ${_areaEraserPath.length} points in path');
      _activePointerId = null;
      _isPenDrawing = false;

      // Close the path by connecting back to start
      if (_areaEraserPath.length >= 3) {
        // Find all strokes inside the area
        final strokesToErase = <Stroke>[];
        for (final stroke in _strokes) {
          if (_isStrokeInLasso(stroke, _areaEraserPath)) {
            strokesToErase.add(stroke);
          }
        }

        if (strokesToErase.isNotEmpty) {
          _saveState();
          setState(() {
            for (final stroke in strokesToErase) {
              _strokes.removeWhere((s) => s.id == stroke.id);
            }
          });
          widget.onStrokesChanged?.call(_strokes);
          _log('AreaEraser: Erased ${strokesToErase.length} strokes');
        }
      }

      setState(() {
        _areaEraserPath.clear();
        _isAreaEraserActive = false;
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
        // 드래그 완료 후 선택이 유지되어 있으면 메뉴 다시 표시
        if (_selectedStrokeIds.isNotEmpty) {
          final bounds = _getSelectionBounds();
          if (bounds != null) {
            setState(() {
              _showStrokeLassoMenu = true;
              _strokeLongPressScreenPosition = Offset(
                bounds.center.dx,
                bounds.top - 30,
              );
            });
          }
        }
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
          // 선택된 스트로크가 있으면 미니 툴바 표시
          if (selectedIds.isNotEmpty) {
            _showStrokeLassoMenu = true;
            // 선택 영역의 중심점 계산
            final bounds = _getSelectionBounds();
            if (bounds != null) {
              _strokeLongPressScreenPosition = Offset(
                bounds.center.dx,
                bounds.top - 30, // 선택 영역 위에 표시
              );
            }
          }
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
      
      // 스트로크 캐시 업데이트 (비동기)
      _updateStrokeCache();
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

  /// 펜 호버링 감지 - Palm Rejection 강화용
  /// 펜이 화면 가까이에 있으면 손바닥 터치를 무시하도록 타임스탬프 업데이트
  void _onPointerHover(PointerHoverEvent event) {
    // 펜/스타일러스 호버링인 경우에만 처리
    if (event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus) {
      _penHoverStartTime = DateTime.now().millisecondsSinceEpoch;
      // _log('Pen hovering detected, updating hover timestamp');
    }
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
    const int fadeSteps = 15; // 15단계로 페이드
    final int stepDuration = _laserPointerFadeDuration.inMilliseconds ~/ fadeSteps;
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
      ),
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

  /// Snap angle to nearest 15 degrees for line/arrow tools
  /// Returns snapped end point based on start point
  Offset _snapToAngle(Offset start, Offset end, {double snapAngle = 15.0}) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final distance = math.sqrt(dx * dx + dy * dy);

    if (distance < 5) return end; // Too short to snap

    // Calculate current angle in degrees
    final double angle = math.atan2(dy, dx) * 180 / math.pi;

    // Snap to nearest snapAngle degrees
    final double snappedAngle = (angle / snapAngle).round() * snapAngle;

    // Convert back to radians and calculate new end point
    final double radians = snappedAngle * math.pi / 180;
    return Offset(
      start.dx + distance * math.cos(radians),
      start.dy + distance * math.sin(radians),
    );
  }

  /// Snap rectangle/circle to square/circle when Shift is held (or aspect ratio lock)
  Offset _snapToSquare(Offset start, Offset end) {
    final dx = (end.dx - start.dx).abs();
    final dy = (end.dy - start.dy).abs();
    final size = math.max(dx, dy);

    return Offset(
      start.dx + (end.dx > start.dx ? size : -size),
      start.dy + (end.dy > start.dy ? size : -size),
    );
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
    HapticFeedback.lightImpact(); // 진동 피드백
    _redoStack.add(List.from(_strokes.map((s) => s.copyWith())));
    setState(() {
      _strokes = _undoStack.removeLast();
    });
    widget.onStrokesChanged?.call(_strokes);
    // 스트로크 캐시 업데이트
    _updateStrokeCache();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    HapticFeedback.lightImpact(); // 진동 피드백
    _undoStack.add(List.from(_strokes.map((s) => s.copyWith())));
    setState(() {
      _strokes = _redoStack.removeLast();
    });
    widget.onStrokesChanged?.call(_strokes);
    // 스트로크 캐시 업데이트
    _updateStrokeCache();
  }

  /// Fit canvas to screen (reset zoom and center)
  void _fitToScreen() {
    HapticFeedback.mediumImpact(); // 진동 피드백 (화면 맞춤은 더 강하게)
    setState(() {
      _scale = 1.0;
      _offset = Offset.zero;
      _baseScale = 1.0;
      _baseOffset = Offset.zero;
    });
    _log('Fit to screen: scale=$_scale, offset=$_offset');
  }

  /// 화면 맞춤 공개 메서드 (외부에서 호출 가능)
  void fitToScreen() => _fitToScreen();

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

  /// Change color of selected strokes
  void changeSelectionColor(Color newColor) {
    if (_selectedStrokeIds.isEmpty) return;
    _saveState();

    setState(() {
      for (int i = 0; i < _strokes.length; i++) {
        if (_selectedStrokeIds.contains(_strokes[i].id)) {
          final stroke = _strokes[i];
          _strokes[i] = Stroke(
            id: stroke.id,
            toolType: stroke.toolType,
            color: newColor,
            width: stroke.width,
            points: stroke.points,
            timestamp: stroke.timestamp,
          );
        }
      }
    });
    widget.onStrokesChanged?.call(_strokes);
  }

  /// Change width of selected strokes
  void changeSelectionWidth(double newWidth) {
    if (_selectedStrokeIds.isEmpty) return;
    _saveState();

    setState(() {
      for (int i = 0; i < _strokes.length; i++) {
        if (_selectedStrokeIds.contains(_strokes[i].id)) {
          final stroke = _strokes[i];
          _strokes[i] = Stroke(
            id: stroke.id,
            toolType: stroke.toolType,
            color: stroke.color,
            width: newWidth,
            points: stroke.points,
            timestamp: stroke.timestamp,
          );
        }
      }
    });
    widget.onStrokesChanged?.call(_strokes);
  }

  /// Change both color and width of selected strokes
  void changeSelectionStyle({Color? newColor, double? newWidth}) {
    if (_selectedStrokeIds.isEmpty) return;
    if (newColor == null && newWidth == null) return;
    _saveState();

    setState(() {
      for (int i = 0; i < _strokes.length; i++) {
        if (_selectedStrokeIds.contains(_strokes[i].id)) {
          final stroke = _strokes[i];
          _strokes[i] = Stroke(
            id: stroke.id,
            toolType: stroke.toolType,
            color: newColor ?? stroke.color,
            width: newWidth ?? stroke.width,
            points: stroke.points,
            timestamp: stroke.timestamp,
          );
        }
      }
    });
    widget.onStrokesChanged?.call(_strokes);
  }

  /// Rotate selected strokes by angle (in degrees)
  void rotateSelection(double angleDegrees) {
    if (_selectedStrokeIds.isEmpty) return;
    _saveState();

    final bounds = _getSelectionBounds();
    if (bounds == null) return;

    final center = bounds.center;
    final angleRadians = angleDegrees * (3.141592653589793 / 180);

    setState(() {
      for (int i = 0; i < _strokes.length; i++) {
        if (_selectedStrokeIds.contains(_strokes[i].id)) {
          final stroke = _strokes[i];
          final rotatedPoints = stroke.points.map((p) {
            // Translate to origin, rotate, translate back
            final dx = p.x - center.dx;
            final dy = p.y - center.dy;
            final cos = math.cos(angleRadians);
            final sin = math.sin(angleRadians);
            return StrokePoint(
              x: center.dx + dx * cos - dy * sin,
              y: center.dy + dx * sin + dy * cos,
              pressure: p.pressure,
              tilt: p.tilt,
              timestamp: p.timestamp,
            );
          }).toList();

          _strokes[i] = Stroke(
            id: stroke.id,
            toolType: stroke.toolType,
            color: stroke.color,
            width: stroke.width,
            points: rotatedPoints,
            timestamp: stroke.timestamp,
          );
        }
      }
    });
    widget.onStrokesChanged?.call(_strokes);
  }


  /// Scale selected strokes by factor
  void scaleSelection(double factor) {
    if (_selectedStrokeIds.isEmpty || factor <= 0) return;
    _saveState();

    final bounds = _getSelectionBounds();
    if (bounds == null) return;

    final center = bounds.center;

    setState(() {
      for (int i = 0; i < _strokes.length; i++) {
        if (_selectedStrokeIds.contains(_strokes[i].id)) {
          final stroke = _strokes[i];
          final scaledPoints = stroke.points.map((p) {
            // Scale from center
            final dx = p.x - center.dx;
            final dy = p.y - center.dy;
            return StrokePoint(
              x: center.dx + dx * factor,
              y: center.dy + dy * factor,
              pressure: p.pressure,
              tilt: p.tilt,
              timestamp: p.timestamp,
            );
          }).toList();

          _strokes[i] = Stroke(
            id: stroke.id,
            toolType: stroke.toolType,
            color: stroke.color,
            width: stroke.width * factor, // 굵기도 비례 조정
            points: scaledPoints,
            timestamp: stroke.timestamp,
          );
        }
      }
    });
    widget.onStrokesChanged?.call(_strokes);
  }

  /// Show transform panel (rotate/scale) - 화면 하단에 표시하여 선택 영역이 보이도록
  void _showTransformDialog() {
    // 원본 스트로크 저장 (취소 시 복원용)
    final originalStrokes = _strokes.map((s) => Stroke(
      id: s.id,
      toolType: s.toolType,
      color: s.color,
      width: s.width,
      points: s.points.toList(),
      timestamp: s.timestamp,
      isShape: s.isShape,
      shapeType: s.shapeType,
    ),).toList();

    double rotationAngle = 0;
    double scaleFactor = 1.0;
    double lastAppliedRotation = 0;
    double lastAppliedScale = 1.0;

    // 올가미 메뉴 숨기기
    setState(() {
      _showStrokeLassoMenu = false;
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent, // 배경 투명하게 하여 선택 영역이 보이도록
      isDismissible: false, // 바깥 터치로 닫히지 않도록
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          // 실시간 변환 적용 함수
          void applyTransformPreview() {
            // 델타 계산 (이전 적용값과의 차이)
            final deltaRotation = rotationAngle - lastAppliedRotation;
            final deltaScale = scaleFactor / lastAppliedScale;

            if (deltaRotation != 0) {
              _rotateSelectionImmediate(deltaRotation);
              lastAppliedRotation = rotationAngle;
            }
            if (deltaScale != 1.0) {
              _scaleSelectionImmediate(deltaScale);
              lastAppliedScale = scaleFactor;
            }
          }

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15 ),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 헤더 + 버튼
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1 ),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.transform, color: Colors.blue, size: 18),
                      const SizedBox(width: 6),
                      const Text('변형', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const Spacer(),
                      // 취소 버튼
                      TextButton(
                        onPressed: () {
                          // 원본으로 복원
                          setState(() {
                            _strokes = originalStrokes;
                          });
                          widget.onStrokesChanged?.call(_strokes);
                          Navigator.pop(sheetContext);
                          // 올가미 메뉴 다시 표시
                          final bounds = _getSelectionBounds();
                          if (bounds != null && _selectedStrokeIds.isNotEmpty) {
                            setState(() {
                              _showStrokeLassoMenu = true;
                              _strokeLongPressScreenPosition = Offset(bounds.center.dx, bounds.top - 30);
                            });
                          }
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                        ),
                        child: const Text('취소', style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 4),
                      // 완료 버튼
                      ElevatedButton(
                        onPressed: () {
                          // 변형 확정 (이미 적용됨)
                          _saveState();
                          Navigator.pop(sheetContext);
                          _closeStrokeLassoMenu();
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          minimumSize: Size.zero,
                          backgroundColor: Colors.blue,
                        ),
                        child: const Text('완료', style: TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 회전 슬라이더 (컴팩트)
                      Row(
                        children: [
                          const Icon(Icons.rotate_right, size: 16, color: Colors.blue),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                              ),
                              child: Slider(
                                value: rotationAngle,
                                min: -180,
                                max: 180,
                                divisions: 72,
                                activeColor: Colors.blue,
                                onChanged: (value) {
                                  setSheetState(() => rotationAngle = value);
                                  applyTransformPreview();
                                },
                              ),
                            ),
                          ),
                          Container(
                            width: 40,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1 ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${rotationAngle.round()}°',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // 크기 슬라이더 (컴팩트)
                      Row(
                        children: [
                          const Icon(Icons.photo_size_select_small, size: 16, color: Colors.green),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                              ),
                              child: Slider(
                                value: scaleFactor,
                                min: 0.25,
                                max: 3.0,
                                divisions: 55,
                                activeColor: Colors.green,
                                onChanged: (value) {
                                  setSheetState(() => scaleFactor = value);
                                  applyTransformPreview();
                                },
                              ),
                            ),
                          ),
                          Container(
                            width: 40,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1 ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${(scaleFactor * 100).round()}%',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 실시간 회전 적용 (Undo 스택에 저장하지 않음)
  void _rotateSelectionImmediate(double angleDegrees) {
    if (_selectedStrokeIds.isEmpty) return;

    final bounds = _getSelectionBounds();
    if (bounds == null) return;

    final center = bounds.center;
    final angleRadians = angleDegrees * (3.141592653589793 / 180);
    final cos = math.cos(angleRadians);
    final sin = math.sin(angleRadians);

    setState(() {
      for (int i = 0; i < _strokes.length; i++) {
        if (_selectedStrokeIds.contains(_strokes[i].id)) {
          final stroke = _strokes[i];
          final rotatedPoints = stroke.points.map((p) {
            final dx = p.x - center.dx;
            final dy = p.y - center.dy;
            return StrokePoint(
              x: center.dx + dx * cos - dy * sin,
              y: center.dy + dx * sin + dy * cos,
              pressure: p.pressure,
              tilt: p.tilt,
              timestamp: p.timestamp,
            );
          }).toList();

          _strokes[i] = Stroke(
            id: stroke.id,
            toolType: stroke.toolType,
            color: stroke.color,
            width: stroke.width,
            points: rotatedPoints,
            timestamp: stroke.timestamp,
            isShape: stroke.isShape,
            shapeType: stroke.shapeType,
          );
        }
      }
    });
    widget.onStrokesChanged?.call(_strokes);
  }

  /// 실시간 크기 조절 적용 (Undo 스택에 저장하지 않음)
  void _scaleSelectionImmediate(double factor) {
    if (_selectedStrokeIds.isEmpty || factor == 1.0) return;

    final bounds = _getSelectionBounds();
    if (bounds == null) return;

    final center = bounds.center;

    setState(() {
      for (int i = 0; i < _strokes.length; i++) {
        if (_selectedStrokeIds.contains(_strokes[i].id)) {
          final stroke = _strokes[i];
          final scaledPoints = stroke.points.map((p) {
            final dx = p.x - center.dx;
            final dy = p.y - center.dy;
            return StrokePoint(
              x: center.dx + dx * factor,
              y: center.dy + dy * factor,
              pressure: p.pressure,
              tilt: p.tilt,
              timestamp: p.timestamp,
            );
          }).toList();

          _strokes[i] = Stroke(
            id: stroke.id,
            toolType: stroke.toolType,
            color: stroke.color,
            width: stroke.width,
            points: scaledPoints,
            timestamp: stroke.timestamp,
            isShape: stroke.isShape,
            shapeType: stroke.shapeType,
          );
        }
      }
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
      ),).toList();

      newStrokes.add(Stroke(
        id: newId,
        toolType: stroke.toolType,
        color: stroke.color,
        width: stroke.width,
        points: offsetPoints,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),);
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
          ),).toList();

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

  /// 주어진 위치에 스트로크가 있는지 확인하고 해당 스트로크 ID 반환
  /// tolerance: 터치 허용 범위 (픽셀)
  String? _findStrokeAtPosition(Offset canvasPos, {double tolerance = 15.0}) {
    // 뒤에서부터 검색 (최상위 스트로크 우선)
    for (int i = _strokes.length - 1; i >= 0; i--) {
      final stroke = _strokes[i];
      if (_isPointOnStroke(canvasPos, stroke, tolerance: tolerance)) {
        return stroke.id;
      }
    }
    return null;
  }

  /// 점이 스트로크 위에 있는지 확인
  bool _isPointOnStroke(Offset point, Stroke stroke, {double tolerance = 15.0}) {
    if (stroke.points.isEmpty) return false;

    // 스트로크 폭을 고려한 실제 허용 범위
    final effectiveTolerance = tolerance + (stroke.width / 2);

    // 빠른 바운딩 박스 체크
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final p in stroke.points) {
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }

    // 바운딩 박스 밖이면 빠르게 반환
    if (point.dx < minX - effectiveTolerance ||
        point.dx > maxX + effectiveTolerance ||
        point.dy < minY - effectiveTolerance ||
        point.dy > maxY + effectiveTolerance) {
      return false;
    }

    // 각 선분에 대해 점과의 거리 확인
    for (int i = 0; i < stroke.points.length - 1; i++) {
      final p1 = Offset(stroke.points[i].x, stroke.points[i].y);
      final p2 = Offset(stroke.points[i + 1].x, stroke.points[i + 1].y);

      final distance = _pointToLineDistance(point, p1, p2);
      if (distance <= effectiveTolerance) {
        return true;
      }
    }

    // 단일 점인 경우
    if (stroke.points.length == 1) {
      final p = Offset(stroke.points[0].x, stroke.points[0].y);
      return (point - p).distance <= effectiveTolerance;
    }

    return false;
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

    // 선분 위의 가장 가까운 점의 파라미터 t (0~1)
    var t = ((point.dx - lineStart.dx) * dx + (point.dy - lineStart.dy) * dy) / lengthSquared;
    t = t.clamp(0.0, 1.0);

    // 가장 가까운 점
    final closestPoint = Offset(
      lineStart.dx + t * dx,
      lineStart.dy + t * dy,
    );

    return (point - closestPoint).distance;
  }

  /// 스트로크 롱프레스 타이머 시작
  void _startStrokeLongPressTimer(Offset canvasPos, Offset screenPos, String strokeId) {
    _cancelStrokeLongPressTimer();
    _strokeLongPressPosition = canvasPos;
    _strokeLongPressScreenPosition = screenPos;
    _longPressedStrokeId = strokeId;

    _strokeLongPressTimer = Timer(const Duration(milliseconds: _strokeLongPressDuration), () {
      if (mounted && _longPressedStrokeId != null) {
        // 현재 그리던 스트로크 취소
        _currentStroke = null;

        setState(() {
          // 해당 스트로크 자동 선택
          _selectedStrokeIds = {_longPressedStrokeId!};
          // 미니 툴바 표시
          _showStrokeLassoMenu = true;
        });

        // 디버그 로그
        debugPrint('롱프레스 스트로크 선택: strokeId=$_longPressedStrokeId');
      }
    });
  }

  /// 스트로크 롱프레스 타이머 취소
  void _cancelStrokeLongPressTimer() {
    _strokeLongPressTimer?.cancel();
    _strokeLongPressTimer = null;
    _strokeLongPressPosition = null;
    _longPressedStrokeId = null;
  }

  /// 올가미 메뉴 닫기
  void _closeStrokeLassoMenu() {
    if (_showStrokeLassoMenu) {
      setState(() {
        _showStrokeLassoMenu = false;
        _strokeLongPressScreenPosition = null;
      });
    }
  }

  /// 선택된 스트로크 글씨 변경 패널 (색상 + 굵기) - 화면 하단에 표시하여 선택 영역이 보이도록
  void _showStrokeEditDialog() {
    // 선택된 스트로크들의 현재 굵기 평균값 가져오기
    double currentWidth = 2.0;
    Color? currentColor;
    if (_selectedStrokeIds.isNotEmpty) {
      final selectedList = _strokes.where((s) => _selectedStrokeIds.contains(s.id)).toList();
      if (selectedList.isNotEmpty) {
        currentWidth = selectedList.map((s) => s.width).reduce((a, b) => a + b) / selectedList.length;
        // 선택된 스트로크들의 색상이 모두 같으면 그 색상 표시
        final firstColor = selectedList.first.color;
        if (selectedList.every((s) => s.color == firstColor)) {
          currentColor = firstColor;
        }
      }
    }

    // 원본 스트로크 저장 (취소 시 복원용)
    final originalStrokes = _strokes.map((s) => Stroke(
      id: s.id,
      toolType: s.toolType,
      color: s.color,
      width: s.width,
      points: s.points.toList(),
      timestamp: s.timestamp,
      isShape: s.isShape,
      shapeType: s.shapeType,
    ),).toList();

    Color selectedColor = currentColor ?? Colors.black;
    double selectedWidth = currentWidth;

    final colors = [
      Colors.black,
      Colors.white,
      Colors.grey,
      Colors.red,
      Colors.orange,
      Colors.amber,
      Colors.yellow,
      Colors.green,
      Colors.teal,
      Colors.blue,
      Colors.indigo,
      Colors.purple,
      Colors.pink,
      Colors.brown,
      const Color(0xFF1976D2), // Blue 700
      const Color(0xFFD32F2F), // Red 700
    ];

    // 올가미 메뉴 숨기기
    setState(() {
      _showStrokeLassoMenu = false;
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent, // 배경 투명하게 하여 선택 영역이 보이도록
      isDismissible: false, // 바깥 터치로 닫히지 않도록
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          // 실시간 스타일 적용 함수 (Undo 스택에 저장하지 않음)
          void applyStylePreview(Color color, double width) {
            // 선택된 스트로크에 즉시 스타일 적용
            for (int i = 0; i < _strokes.length; i++) {
              if (_selectedStrokeIds.contains(_strokes[i].id)) {
                final stroke = _strokes[i];
                _strokes[i] = Stroke(
                  id: stroke.id,
                  toolType: stroke.toolType,
                  color: color,
                  width: width,
                  points: stroke.points,
                  timestamp: stroke.timestamp,
                  isShape: stroke.isShape,
                  shapeType: stroke.shapeType,
                );
              }
            }
            // 캔버스 위젯의 setState 호출하여 다시 그리기
            // _strokeContentVersion 증가로 RepaintBoundary Key 변경 → 강제 repaint
            setState(() {
              _strokeContentVersion++;
            });
            widget.onStrokesChanged?.call(_strokes);
          }

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15 ),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 헤더 + 닫기 버튼
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1 ),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.edit, color: Colors.amber, size: 18),
                      const SizedBox(width: 6),
                      const Text('글씨 변경', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const Spacer(),
                      // 취소 버튼
                      TextButton(
                        onPressed: () {
                          // 취소: 원본으로 복원
                          setState(() {
                            _strokes.clear();
                            _strokes.addAll(originalStrokes);
                          });
                          widget.onStrokesChanged?.call(_strokes);
                          Navigator.pop(sheetContext);
                          setState(() {
                            _showStrokeLassoMenu = true;
                          });
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                        ),
                        child: const Text('취소', style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 4),
                      // 완료 버튼
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _closeStrokeLassoMenu();
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          minimumSize: Size.zero,
                          backgroundColor: Colors.amber,
                        ),
                        child: const Text('완료', style: TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 색상 팔레트 (컴팩트)
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: colors.map((color) {
                          final isSelected = selectedColor == color;
                          return GestureDetector(
                            onTap: () {
                              setSheetState(() => selectedColor = color);
                              applyStylePreview(color, selectedWidth);
                            },
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected ? Colors.blue : (color == Colors.white ? Colors.grey[400]! : Colors.transparent),
                                  width: isSelected ? 2 : 1,
                                ),
                                boxShadow: isSelected ? [
                                  BoxShadow(
                                    color: Colors.blue.withValues(alpha: 0.4 ),
                                    blurRadius: 4,
                                    spreadRadius: 1,
                                  ),
                                ] : null,
                              ),
                              child: isSelected
                                  ? Icon(Icons.check, color: color == Colors.white || color == Colors.yellow || color == Colors.amber ? Colors.black : Colors.white, size: 14)
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 10),
                      // 굵기 슬라이더 (컴팩트)
                      Row(
                        children: [
                          const Icon(Icons.line_weight, size: 16, color: Colors.orange),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                              ),
                              child: Slider(
                                value: selectedWidth,
                                min: 0.5,
                                max: 20.0,
                                divisions: 39,
                                activeColor: Colors.orange,
                                onChanged: (value) {
                                  setSheetState(() => selectedWidth = value);
                                  applyStylePreview(selectedColor, value);
                                },
                              ),
                            ),
                          ),
                          Container(
                            width: 36,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.1 ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              selectedWidth.toStringAsFixed(1),
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
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
    final double width = math.min(image.width.toDouble(), 300);
    final double height = width / aspectRatio;

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

  /// Get selected shape
  CanvasShape? get selectedShape {
    if (_selectedShapeId == null) return null;
    try {
      return _shapes.firstWhere((s) => s.id == _selectedShapeId);
    } catch (_) {
      return null;
    }
  }

  /// Delete selected shape
  void deleteSelectedShape() {
    if (_selectedShapeId == null) return;
    setState(() {
      _shapes.removeWhere((s) => s.id == _selectedShapeId);
      _selectedShapeId = null;
    });
    widget.onShapeSelectionChanged?.call(false);
    _log('Deleted selected shape');
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
                        color: isBold ? Colors.blue : Colors.grey,),
                      onPressed: () {
                        setDialogState(() => isBold = !isBold);
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.format_italic,
                        color: isItalic ? Colors.blue : Colors.grey,),
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
                    ),),
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
