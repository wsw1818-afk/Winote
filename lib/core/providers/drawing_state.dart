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
  blank,      // 빈 페이지
  lined,      // 줄 노트
  grid,       // 격자 노트
  dotted,     // 점 노트
  cornell,    // 코넬 노트
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
  List<Stroke> _strokes = [];
  final List<List<Stroke>> _undoStack = [];
  final List<List<Stroke>> _redoStack = [];
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
    _eraserWidth = width.clamp(5.0, 100.0);
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

  /// Save current state for undo
  void _saveState() {
    _undoStack.add(List.from(_strokes));
    if (_undoStack.length > _maxHistorySize) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  /// Add a stroke
  void addStroke(Stroke stroke) {
    _saveState();
    _strokes.add(stroke);
    notifyListeners();
  }

  /// Set all strokes (used when loading or replacing)
  void setStrokes(List<Stroke> strokes) {
    _saveState();
    _strokes = List.from(strokes);
    notifyListeners();
  }

  /// Undo last action
  void undo() {
    if (_undoStack.isEmpty) return;

    _redoStack.add(List.from(_strokes));
    _strokes = _undoStack.removeLast();
    notifyListeners();
  }

  /// Redo last undone action
  void redo() {
    if (_redoStack.isEmpty) return;

    _undoStack.add(List.from(_strokes));
    _strokes = _redoStack.removeLast();
    notifyListeners();
  }

  /// Clear all strokes
  void clear() {
    if (_strokes.isEmpty) return;
    _saveState();
    _strokes.clear();
    notifyListeners();
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
      _saveState();
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
