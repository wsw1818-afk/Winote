import 'package:flutter/material.dart';
import '../../domain/entities/stroke.dart';
import '../../domain/entities/stroke_point.dart';
import '../services/stroke_smoothing_service.dart';

/// Tool types available in the drawing canvas
enum DrawingTool {
  pen,
  highlighter,
  eraser,
  lasso, // 올가미 선택 도구
  laserPointer, // 레이저 포인터 (발표용)
  presentationHighlighter, // 프레젠테이션 형광펜 (줄 긋고 사라짐)
  shapeLine, // 직선
  shapeRectangle, // 사각형
  shapeCircle, // 원/타원
  shapeArrow, // 화살표
}

/// Page template types for different note styles
enum PageTemplate {
  blank,        // 빈 페이지
  lined,        // 줄 노트
  grid,         // 격자 노트
  dotted,       // 점 노트
  cornell,      // 코넬 노트
  customImage,  // 커스텀 이미지 배경 (Canva 등에서 가져온 이미지)
}

/// Drawing state provider for managing canvas state
class DrawingState extends ChangeNotifier {
  // Current tool
  DrawingTool _currentTool = DrawingTool.pen;
  DrawingTool get currentTool => _currentTool;

  // Pen settings
  Color _penColor = Colors.black;
  double _penWidth = 2.0;
  Color get penColor => _penColor;
  double get penWidth => _penWidth;

  // Highlighter settings
  Color _highlighterColor = Colors.yellow.withOpacity(0.5);
  double _highlighterWidth = 20.0;
  Color get highlighterColor => _highlighterColor;
  double get highlighterWidth => _highlighterWidth;

  // Eraser settings
  double _eraserWidth = 20.0;
  double get eraserWidth => _eraserWidth;

  // Laser pointer settings
  Color _laserPointerColor = Colors.red;
  Color get laserPointerColor => _laserPointerColor;

  // Stroke smoothing (필기 보정)
  SmoothingLevel _smoothingLevel = SmoothingLevel.medium;
  SmoothingLevel get smoothingLevel => _smoothingLevel;

  // Strokes and history for undo/redo
  // 최적화: 델타 기반 undo/redo (전체 복사 대신 변경분만 저장)
  List<Stroke> _strokes = [];
  final List<_UndoAction> _undoStack = [];
  final List<_UndoAction> _redoStack = [];
  static const int _maxHistorySize = 50;

  List<Stroke> get strokes => _strokes;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  // Canvas transform for zoom/pan
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  double get scale => _scale;
  Offset get offset => _offset;

  // Predefined colors
  static const List<Color> presetColors = [
    Colors.black,
    Colors.white,
    Color(0xFF424242), // Dark gray
    Color(0xFF9E9E9E), // Gray
    Color(0xFFF44336), // Red
    Color(0xFFE91E63), // Pink
    Color(0xFF9C27B0), // Purple
    Color(0xFF673AB7), // Deep Purple
    Color(0xFF3F51B5), // Indigo
    Color(0xFF2196F3), // Blue
    Color(0xFF03A9F4), // Light Blue
    Color(0xFF00BCD4), // Cyan
    Color(0xFF009688), // Teal
    Color(0xFF4CAF50), // Green
    Color(0xFF8BC34A), // Light Green
    Color(0xFFCDDC39), // Lime
    Color(0xFFFFEB3B), // Yellow
    Color(0xFFFFC107), // Amber
    Color(0xFFFF9800), // Orange
    Color(0xFFFF5722), // Deep Orange
    Color(0xFF795548), // Brown
  ];

  // Predefined stroke widths
  static const List<double> presetWidths = [
    0.5,
    1.0,
    2.0,
    3.0,
    5.0,
    8.0,
    12.0,
    20.0,
  ];

  /// Set current tool
  void setTool(DrawingTool tool) {
    _currentTool = tool;
    notifyListeners();
  }

  /// Set pen color
  void setPenColor(Color color) {
    _penColor = color;
    notifyListeners();
  }

  /// Set pen width
  void setPenWidth(double width) {
    _penWidth = width.clamp(0.5, 50.0);
    notifyListeners();
  }

  /// Set highlighter color
  void setHighlighterColor(Color color) {
    _highlighterColor = color.withOpacity(0.5);
    notifyListeners();
  }

  /// Set highlighter width
  void setHighlighterWidth(double width) {
    _highlighterWidth = width.clamp(5.0, 50.0);
    notifyListeners();
  }

  /// Set eraser width
  void setEraserWidth(double width) {
    _eraserWidth = width.clamp(5.0, 150.0);
    notifyListeners();
  }

  /// Set laser pointer color
  void setLaserPointerColor(Color color) {
    _laserPointerColor = color;
    notifyListeners();
  }

  /// Set stroke smoothing level (필기 보정 강도)
  void setSmoothingLevel(SmoothingLevel level) {
    _smoothingLevel = level;
    StrokeSmoothingService.instance.level = level;
    notifyListeners();
  }

  /// Get current color based on tool
  Color get currentColor {
    switch (_currentTool) {
      case DrawingTool.pen:
      case DrawingTool.shapeLine:
      case DrawingTool.shapeRectangle:
      case DrawingTool.shapeCircle:
      case DrawingTool.shapeArrow:
        return _penColor;
      case DrawingTool.highlighter:
        return _highlighterColor;
      case DrawingTool.eraser:
      case DrawingTool.lasso:
      case DrawingTool.laserPointer:
      case DrawingTool.presentationHighlighter:
        return Colors.white; // Not used for eraser/lasso/laser/presentationHighlighter
    }
  }

  /// Get current width based on tool
  double get currentWidth {
    switch (_currentTool) {
      case DrawingTool.pen:
      case DrawingTool.shapeLine:
      case DrawingTool.shapeRectangle:
      case DrawingTool.shapeCircle:
      case DrawingTool.shapeArrow:
        return _penWidth;
      case DrawingTool.highlighter:
        return _highlighterWidth;
      case DrawingTool.eraser:
      case DrawingTool.lasso:
      case DrawingTool.laserPointer:
      case DrawingTool.presentationHighlighter:
        return _eraserWidth; // Lasso/laser/presentationHighlighter uses eraser width for visual
    }
  }

  /// Add a stroke (최적화: 델타 기반)
  void addStroke(Stroke stroke) {
    _pushUndo(_UndoAction.add(stroke));
    _strokes.add(stroke);
    notifyListeners();
  }

  /// Set all strokes (used when loading or replacing)
  void setStrokes(List<Stroke> strokes) {
    // 전체 교체는 스냅샷으로 저장 (드물게 발생)
    _pushUndo(_UndoAction.replace(List.from(_strokes)));
    _strokes = List.from(strokes);
    notifyListeners();
  }

  /// Undo last action (최적화: 델타 역적용)
  void undo() {
    if (_undoStack.isEmpty) return;

    final action = _undoStack.removeLast();
    _redoStack.add(action.createInverse(_strokes));
    action.undo(_strokes);
    notifyListeners();
  }

  /// Redo last undone action (최적화: 델타 재적용)
  void redo() {
    if (_redoStack.isEmpty) return;

    final action = _redoStack.removeLast();
    _undoStack.add(action.createInverse(_strokes));
    action.undo(_strokes);
    notifyListeners();
  }

  /// Clear all strokes
  void clear() {
    if (_strokes.isEmpty) return;
    _pushUndo(_UndoAction.replace(List.from(_strokes)));
    _strokes.clear();
    notifyListeners();
  }

  /// Push undo action with size limit
  void _pushUndo(_UndoAction action) {
    _undoStack.add(action);
    if (_undoStack.length > _maxHistorySize) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  /// Erase strokes at a point (partial erasing - splits strokes)
  void eraseAt(Offset point, double radius) {
    final toRemove = <Stroke>[];
    final toAdd = <Stroke>[];

    for (final stroke in _strokes) {
      // Find points that should be erased
      final erasedIndices = <int>{};
      for (int i = 0; i < stroke.points.length; i++) {
        final p = stroke.points[i];
        final distance = (Offset(p.x, p.y) - point).distance;
        if (distance <= radius + stroke.width / 2) {
          erasedIndices.add(i);
        }
      }

      if (erasedIndices.isEmpty) continue;

      // Mark stroke for removal
      toRemove.add(stroke);

      // Split stroke into segments (keeping non-erased parts)
      final segments = _splitStrokeByErasedIndices(stroke, erasedIndices);
      toAdd.addAll(segments);
    }

    if (toRemove.isNotEmpty) {
      // 지우기 작업도 델타 기반으로 저장
      _pushUndo(_UndoAction.erase(toRemove, toAdd));
      for (final stroke in toRemove) {
        _strokes.remove(stroke);
      }
      _strokes.addAll(toAdd);
      notifyListeners();
    }
  }

  /// Split a stroke into segments, excluding erased indices
  List<Stroke> _splitStrokeByErasedIndices(Stroke stroke, Set<int> erasedIndices) {
    final segments = <Stroke>[];
    final currentSegment = <StrokePoint>[];

    for (int i = 0; i < stroke.points.length; i++) {
      if (erasedIndices.contains(i)) {
        // End current segment if it has enough points
        if (currentSegment.length >= 2) {
          segments.add(_createSegmentStroke(stroke, currentSegment));
        }
        currentSegment.clear();
      } else {
        currentSegment.add(stroke.points[i]);
      }
    }

    // Add final segment if it has enough points
    if (currentSegment.length >= 2) {
      segments.add(_createSegmentStroke(stroke, currentSegment));
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
      points: List.from(points),
      timestamp: original.timestamp,
      isShape: original.isShape,
      shapeType: original.shapeType,
    );
  }

  /// Update canvas transform
  void setTransform({double? scale, Offset? offset}) {
    if (scale != null) {
      _scale = scale.clamp(1.0, 1.5);
    }
    if (offset != null) {
      _offset = offset;
    }
    notifyListeners();
  }

  /// Reset canvas transform
  void resetTransform() {
    _scale = 1.0;
    _offset = Offset.zero;
    notifyListeners();
  }
}

/// Undo 액션 타입
enum _UndoActionType {
  add,     // 스트로크 추가
  erase,   // 스트로크 지우기 (분할 포함)
  replace, // 전체 교체 (스냅샷)
}

/// 델타 기반 Undo 액션 (메모리 최적화)
class _UndoAction {
  final _UndoActionType type;
  final Stroke? addedStroke;           // add: 추가된 스트로크
  final List<Stroke>? removedStrokes;  // erase: 제거된 스트로크들
  final List<Stroke>? addedStrokes;    // erase: 분할로 추가된 스트로크들
  final List<Stroke>? snapshot;        // replace: 전체 스냅샷

  _UndoAction._({
    required this.type,
    this.addedStroke,
    this.removedStrokes,
    this.addedStrokes,
    this.snapshot,
  });

  /// 스트로크 추가 액션
  factory _UndoAction.add(Stroke stroke) {
    return _UndoAction._(type: _UndoActionType.add, addedStroke: stroke);
  }

  /// 스트로크 지우기 액션 (분할 포함)
  factory _UndoAction.erase(List<Stroke> removed, List<Stroke> added) {
    return _UndoAction._(
      type: _UndoActionType.erase,
      removedStrokes: List.from(removed),
      addedStrokes: List.from(added),
    );
  }

  /// 전체 교체 액션 (clear, setStrokes 등)
  factory _UndoAction.replace(List<Stroke> previousStrokes) {
    return _UndoAction._(type: _UndoActionType.replace, snapshot: previousStrokes);
  }

  /// Undo 실행 (역방향 적용)
  void undo(List<Stroke> strokes) {
    switch (type) {
      case _UndoActionType.add:
        // 추가된 스트로크 제거
        strokes.removeWhere((s) => s.id == addedStroke!.id);
        break;
      case _UndoActionType.erase:
        // 분할된 스트로크 제거하고 원본 복원
        for (final added in addedStrokes!) {
          strokes.removeWhere((s) => s.id == added.id);
        }
        strokes.addAll(removedStrokes!);
        break;
      case _UndoActionType.replace:
        // 스냅샷으로 복원
        strokes.clear();
        strokes.addAll(snapshot!);
        break;
    }
  }

  /// Redo를 위한 역방향 액션 생성
  _UndoAction createInverse(List<Stroke> currentStrokes) {
    switch (type) {
      case _UndoActionType.add:
        // redo: 다시 추가
        return _UndoAction._(
          type: _UndoActionType.erase,
          removedStrokes: [],
          addedStrokes: [addedStroke!],
        );
      case _UndoActionType.erase:
        // redo: 다시 지우기
        return _UndoAction._(
          type: _UndoActionType.erase,
          removedStrokes: addedStrokes,
          addedStrokes: removedStrokes,
        );
      case _UndoActionType.replace:
        // redo: 현재 상태를 스냅샷으로
        return _UndoAction.replace(List.from(currentStrokes));
    }
  }
}
