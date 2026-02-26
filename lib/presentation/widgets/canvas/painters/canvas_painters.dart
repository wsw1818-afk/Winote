import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../../../domain/entities/stroke.dart';
import '../../../../domain/entities/canvas_image.dart';
import '../../../../domain/entities/canvas_shape.dart';
import '../../../../domain/entities/canvas_table.dart';
import '../../../../domain/entities/canvas_text.dart';
import '../../../../core/providers/drawing_state.dart';


/// Lasso overlay painter - draws OUTSIDE RepaintBoundary for immediate updates
class LassoOverlayPainter extends CustomPainter {
  final List<Offset> lassoPath;
  final double scale;
  final Offset offset;
  final Color lassoColor;

  LassoOverlayPainter({
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

    // screenPath가 비었으면 early return (crash 방지)
    if (screenPath.isEmpty) return;

    // Draw lasso path with user-selected color
    final paint = Paint()
      ..color = lassoColor.withValues(alpha: 0.8 )
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // White outline for visibility
    final outlinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9 )
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

    // Draw start point indicator (screenPath가 비어있지 않음이 보장됨)
    final startPaint = Paint()
      ..color = lassoColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(screenPath.first, 5.0, startPaint);

    // Draw current point indicator
    final currentPaint = Paint()
      ..color = lassoColor.withValues(alpha: 0.6 )
      ..style = PaintingStyle.fill;
    canvas.drawCircle(screenPath.last, 4.0, currentPaint);
  }

  @override
  bool shouldRepaint(LassoOverlayPainter oldDelegate) {
    return lassoPath.length != oldDelegate.lassoPath.length ||
        scale != oldDelegate.scale ||
        offset != oldDelegate.offset ||
        lassoColor != oldDelegate.lassoColor;
  }
}

/// Area eraser overlay painter - draws the area being selected for erasure
class AreaEraserOverlayPainter extends CustomPainter {
  final List<Offset> path;
  final double scale;
  final Offset offset;

  AreaEraserOverlayPainter({
    required this.path,
    required this.scale,
    required this.offset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (path.isEmpty) return;

    // Convert canvas coordinates to screen coordinates
    final screenPath = path.map((p) {
      return Offset(
        p.dx * scale + offset.dx,
        p.dy * scale + offset.dy,
      );
    }).toList();

    // Draw area eraser path with red color
    final paint = Paint()
      ..color = Colors.red.withValues(alpha: 0.8 )
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // White outline for visibility
    final outlinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9 )
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Fill the area with semi-transparent red
    final fillPaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.1 )
      ..style = PaintingStyle.fill;

    if (screenPath.length >= 2) {
      final pathObj = Path();
      pathObj.moveTo(screenPath.first.dx, screenPath.first.dy);
      for (int i = 1; i < screenPath.length; i++) {
        pathObj.lineTo(screenPath[i].dx, screenPath[i].dy);
      }

      // Close the path for fill
      if (screenPath.length >= 3) {
        pathObj.close();
        canvas.drawPath(pathObj, fillPaint);
      }

      // Draw the stroke
      final strokePath = Path();
      strokePath.moveTo(screenPath.first.dx, screenPath.first.dy);
      for (int i = 1; i < screenPath.length; i++) {
        strokePath.lineTo(screenPath[i].dx, screenPath[i].dy);
      }
      canvas.drawPath(strokePath, outlinePaint);
      canvas.drawPath(strokePath, paint);
    }

    // Draw start point indicator
    final startPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    canvas.drawCircle(screenPath.first, 6.0, startPaint);

    // Draw X mark in the start point
    final xPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final center = screenPath.first;
    canvas.drawLine(Offset(center.dx - 3, center.dy - 3), Offset(center.dx + 3, center.dy + 3), xPaint);
    canvas.drawLine(Offset(center.dx + 3, center.dy - 3), Offset(center.dx - 3, center.dy + 3), xPaint);

    // Draw current point indicator
    final currentPaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.6 )
      ..style = PaintingStyle.fill;
    canvas.drawCircle(screenPath.last, 4.0, currentPaint);
  }

  @override
  bool shouldRepaint(AreaEraserOverlayPainter oldDelegate) {
    return path.length != oldDelegate.path.length ||
        scale != oldDelegate.scale ||
        offset != oldDelegate.offset;
  }
}

/// Laser pointer overlay painter - draws laser pointer with fading trail
class LaserPointerPainter extends CustomPainter {
  final Offset? position;
  final List<Offset> trail;
  final double scale;
  final Offset offset;
  final Color color;

  LaserPointerPainter({
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
          ..color = color.withValues(alpha: opacity )
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
        ..color = color.withValues(alpha: 0.3 )
        ..style = PaintingStyle.fill;
      canvas.drawCircle(screenPos, 20.0, glowPaint);

      // Middle glow
      final midGlowPaint = Paint()
        ..color = color.withValues(alpha: 0.5 )
        ..style = PaintingStyle.fill;
      canvas.drawCircle(screenPos, 12.0, midGlowPaint);

      // Inner bright dot
      final dotPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(screenPos, 6.0, dotPaint);

      // White center highlight
      final highlightPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.8 )
        ..style = PaintingStyle.fill;
      canvas.drawCircle(screenPos, 2.0, highlightPaint);
    }
  }

  @override
  bool shouldRepaint(LaserPointerPainter oldDelegate) {
    return position != oldDelegate.position ||
        trail.length != oldDelegate.trail.length ||
        scale != oldDelegate.scale ||
        offset != oldDelegate.offset ||
        color != oldDelegate.color;
  }
}

/// Presentation highlighter overlay painter - draws highlighter with fading effect
class PresentationHighlighterPainter extends CustomPainter {
  final List<Offset> trail;
  final double scale;
  final Offset offset;
  final Color color;
  final double strokeWidth;
  final double opacity;
  final double highlighterOpacity; // 형광펜 투명도

  PresentationHighlighterPainter({
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
        ..color = color.withValues(alpha: highlighterOpacity * opacity )
        ..strokeWidth = strokeWidth * scale
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      canvas.drawPath(path, highlighterPaint);

      // Add a subtle glow effect
      final glowPaint = Paint()
        ..color = color.withValues(alpha: highlighterOpacity * 0.4 * opacity )
        ..strokeWidth = (strokeWidth + 8) * scale
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);

      canvas.drawPath(path, glowPaint);
    }
  }

  @override
  bool shouldRepaint(PresentationHighlighterPainter oldDelegate) {
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
class TemplatePainter extends CustomPainter {
  final PageTemplate template;
  final bool isOverlay; // 배경 이미지 위에 표시되는 오버레이인지 여부
  final bool darkMode; // 다크 캔버스 모드 (밝은 색 라인)

  TemplatePainter({this.template = PageTemplate.blank, this.isOverlay = false, this.darkMode = false});

  @override
  void paint(Canvas canvas, Size size) {
    // 다크 모드: 밝은 색 라인, 라이트 모드: 어두운 색 라인
    // 오버레이일 때는 선을 더 강하게 (진하고 두껍게) 표시
    final baseColor = darkMode ? Colors.grey[400]! : Colors.grey;
    final paint = Paint()
      ..color = isOverlay ? baseColor.withValues(alpha: 0.5 ) : baseColor.withValues(alpha: (darkMode ? 0.4 : 0.2) )
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
        final marginColor = darkMode ? Colors.red[300]! : Colors.red;
        final marginPaint = Paint()
          ..color = isOverlay ? marginColor.withValues(alpha: 0.6 ) : marginColor.withValues(alpha: (darkMode ? 0.5 : 0.3) )
          ..strokeWidth = isOverlay ? 1.5 : 1.0;
        canvas.drawLine(const Offset(marginLeft, 0), Offset(marginLeft, size.height), marginPaint);

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
        final dotColor = darkMode ? Colors.grey[400]! : Colors.grey;
        final dotPaint = Paint()
          ..color = isOverlay ? dotColor.withValues(alpha: 0.7 ) : dotColor.withValues(alpha: (darkMode ? 0.6 : 0.4) )
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

        final sectionColor = darkMode ? Colors.blue[300]! : Colors.blue;
        final sectionPaint = Paint()
          ..color = isOverlay ? sectionColor.withValues(alpha: 0.6 ) : sectionColor.withValues(alpha: (darkMode ? 0.5 : 0.3) )
          ..strokeWidth = isOverlay ? 3.0 : 2.0;

        // Vertical line for cue column
        canvas.drawLine(
          const Offset(cueColumnWidth, 0),
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
        final labelOpacity = isOverlay ? 0.7 : (darkMode ? 0.6 : 0.4);
        final labelColor = darkMode ? Colors.blue[300]! : Colors.blue;
        final textPainter = TextPainter(
          textDirection: TextDirection.ltr,
        );

        // Cue label
        textPainter.text = TextSpan(
          text: 'CUE',
          style: TextStyle(
            color: labelColor.withValues(alpha: labelOpacity ),
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
            color: labelColor.withValues(alpha: labelOpacity ),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        );
        textPainter.layout();
        textPainter.paint(canvas, const Offset(cueColumnWidth + 10, 10));

        // Summary label
        textPainter.text = TextSpan(
          text: 'SUMMARY',
          style: TextStyle(
            color: labelColor.withValues(alpha: labelOpacity ),
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
  bool shouldRepaint(covariant TemplatePainter oldDelegate) =>
      template != oldDelegate.template || isOverlay != oldDelegate.isOverlay || darkMode != oldDelegate.darkMode;
}

/// Optimized stroke renderer - draws directly without spline interpolation for performance
class StrokePainter extends CustomPainter {
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
  // 뷰포트 최적화 (대용량 노트 성능 개선)
  final Rect? visibleRect;
  // 캐시된 스트로크 이미지 (성능 최적화)
  final ui.Image? cachedStrokesImage;
  final Size? canvasSize;

  StrokePainter({
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
    this.visibleRect,
    this.cachedStrokesImage,
    this.canvasSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 캐시된 이미지가 있으면 먼저 그리기 (성능 최적화)
    // 단, 현재 스트로크가 그려지 중이거나 선택된 스트로크가 있으면 캐시 사용하지 않음
    final useCache = cachedStrokesImage != null &&
                     canvasSize != null &&
                     currentStroke == null &&
                     selectedStrokeIds.isEmpty;
    
    if (useCache) {
      // 캐시된 이미지 그리기
      final srcRect = Rect.fromLTWH(0, 0,
        cachedStrokesImage!.width.toDouble(),
        cachedStrokesImage!.height.toDouble());
      final dstRect = Rect.fromLTWH(0, 0, canvasSize!.width, canvasSize!.height);
      canvas.drawImageRect(cachedStrokesImage!, srcRect, dstRect, Paint());
    } else {
      // 캐시 없음: 기존 방식으로 스트로크 그리기
      // Draw completed strokes (non-selected first)
      for (final stroke in strokes) {
        if (!selectedStrokeIds.contains(stroke.id)) {
          // 뷰포트 최적화: 뷰포트 밖 스트로크는 렌더링 스킵
          if (visibleRect != null && !_isStrokeVisible(stroke, visibleRect!)) {
            continue;
          }
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
    }

    // Draw eraser cursor with preview of strokes to be erased
    if (eraserPosition != null) {
      // 1. 먼저 지워질 스트로크 하이라이트 (빨간색 표시)
      for (final stroke in strokes) {
        if (_isStrokeInEraserRange(stroke, eraserPosition!, eraserRadius)) {
          _drawEraserPreviewHighlight(canvas, stroke, eraserPosition!, eraserRadius);
        }
      }

      // 2. 지우개 커서 그리기 (외곽선 + 반투명 내부)
      final eraserFillPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.3 )
        ..style = PaintingStyle.fill;

      final eraserStrokePaint = Paint()
        ..color = Colors.grey[600]!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      // X 표시가 있는 지우개 아이콘
      canvas.drawCircle(eraserPosition!, eraserRadius, eraserFillPaint);
      canvas.drawCircle(eraserPosition!, eraserRadius, eraserStrokePaint);

      // 지우개 내부에 작은 X 표시
      final xSize = eraserRadius * 0.4;
      final xPaint = Paint()
        ..color = Colors.grey[500]!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(eraserPosition!.dx - xSize, eraserPosition!.dy - xSize),
        Offset(eraserPosition!.dx + xSize, eraserPosition!.dy + xSize),
        xPaint,
      );
      canvas.drawLine(
        Offset(eraserPosition!.dx + xSize, eraserPosition!.dy - xSize),
        Offset(eraserPosition!.dx - xSize, eraserPosition!.dy + xSize),
        xPaint,
      );
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
        ..color = lassoColor.withValues(alpha: 0.08 )
        ..style = PaintingStyle.fill;

      // Main lasso stroke paint
      final lassoPaint = Paint()
        ..color = lassoColor.withValues(alpha: 0.8 )
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      // White outline for better visibility
      final lassoOutlinePaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.9 )
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
        ..color = lassoColor.withValues(alpha: 0.8 )
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

  /// Fast stroke drawing with improved pressure and taper
  void _drawStrokeFast(Canvas canvas, Stroke stroke, {Offset offset = Offset.zero, bool highlight = false}) {
    if (stroke.points.isEmpty) return;

    final paint = Paint()
      ..color = stroke.color
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // Single point: draw circle with pressure-based size
    if (stroke.points.length == 1) {
      final point = stroke.points[0];
      final width = stroke.getWidthAtPressure(point.pressure);
      paint.style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(point.x + offset.dx, point.y + offset.dy),
        width / 2,
        paint,
      );
      return;
    }

    // 도형이 아닌 경우: 가변 굵기로 자연스러운 획 렌더링
    if (!stroke.isShape && stroke.points.length >= 2) {
      _drawVariableWidthStroke(canvas, stroke, offset, highlight);
      return;
    }

    // 도형 또는 짧은 스트로크: 기존 Path 방식
    final path = Path();
    final firstPoint = stroke.points.first;
    path.moveTo(firstPoint.x + offset.dx, firstPoint.y + offset.dy);

    // Calculate average pressure for consistent line width
    double totalPressure = 0;
    for (final p in stroke.points) {
      totalPressure += p.pressure;
    }
    final avgPressure = (totalPressure / stroke.points.length).clamp(0.1, 1.0);
    paint.strokeWidth = stroke.getWidthAtPressure(avgPressure);

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
            ..color = Colors.blue.withValues(alpha: 0.3 )
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
        ..color = Colors.blue.withValues(alpha: 0.3 )
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..strokeWidth = paint.strokeWidth + 6;
      canvas.drawPath(path, glowPaint);
    }

    canvas.drawPath(path, paint);
  }

  /// 가변 굵기 스트로크 렌더링 (필압 기반 + 시작/끝 테이퍼)
  void _drawVariableWidthStroke(Canvas canvas, Stroke stroke, Offset offset, bool highlight) {
    final points = stroke.points;
    if (points.length < 2) return;

    final totalPoints = points.length;

    // 하이라이트 그리기 (선택된 스트로크)
    if (highlight) {
      for (int i = 0; i < totalPoints - 1; i++) {
        final p1 = points[i];
        final p2 = points[i + 1];
        final avgPressure = (p1.pressure + p2.pressure) / 2;
        final width = stroke.getWidthAtPressure(avgPressure);

        final glowPaint = Paint()
          ..color = Colors.blue.withValues(alpha: 0.3 )
          ..strokeCap = StrokeCap.round
          ..strokeWidth = width + 6
          ..style = PaintingStyle.stroke;

        canvas.drawLine(
          Offset(p1.x + offset.dx, p1.y + offset.dy),
          Offset(p2.x + offset.dx, p2.y + offset.dy),
          glowPaint,
        );
      }
    }

    // 시작/끝 테이퍼 효과를 위한 계수 계산
    const taperLength = 5; // 테이퍼 적용 포인트 수

    for (int i = 0; i < totalPoints - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];

      // 기본 필압 기반 굵기
      final avgPressure = (p1.pressure + p2.pressure) / 2;
      double width = stroke.getWidthAtPressure(avgPressure);

      // 시작 테이퍼 (처음 몇 포인트에서 얇게 시작)
      if (i < taperLength) {
        final taperRatio = (i + 1) / taperLength;
        width *= 0.3 + (taperRatio * 0.7); // 30%에서 시작
      }

      // 끝 테이퍼 (마지막 몇 포인트에서 얇게 끝남)
      if (i >= totalPoints - taperLength - 1) {
        final distFromEnd = totalPoints - 1 - i;
        final taperRatio = distFromEnd / taperLength;
        width *= 0.3 + (taperRatio * 0.7); // 30%로 끝남
      }

      // 형광펜은 블렌드 모드 적용
      final paint = Paint()
        ..color = stroke.color
        ..strokeCap = StrokeCap.round
        ..strokeWidth = width
        ..style = PaintingStyle.stroke;

      if (stroke.toolType == ToolType.highlighter) {
        paint.blendMode = BlendMode.multiply;
      }

      canvas.drawLine(
        Offset(p1.x + offset.dx, p1.y + offset.dy),
        Offset(p2.x + offset.dx, p2.y + offset.dy),
        paint,
      );
    }

    // 시작점과 끝점에 라운드 캡 추가
    final startPoint = points.first;
    final endPoint = points.last;

    final startWidth = stroke.getWidthAtPressure(startPoint.pressure) * 0.3;
    final endWidth = stroke.getWidthAtPressure(endPoint.pressure) * 0.3;

    final capPaint = Paint()
      ..color = stroke.color
      ..style = PaintingStyle.fill;

    if (stroke.toolType == ToolType.highlighter) {
      capPaint.blendMode = BlendMode.multiply;
    }

    // 시작점 원형 캡
    canvas.drawCircle(
      Offset(startPoint.x + offset.dx, startPoint.y + offset.dy),
      startWidth / 2,
      capPaint,
    );

    // 끝점 원형 캡
    canvas.drawCircle(
      Offset(endPoint.x + offset.dx, endPoint.y + offset.dy),
      endWidth / 2,
      capPaint,
    );
  }

  /// 스트로크가 뷰포트 내에 보이는지 확인 (대용량 노트 최적화)
  bool _isStrokeVisible(Stroke stroke, Rect viewport) {
    // BoundingBox가 있으면 빠르게 체크
    final bb = stroke.boundingBox;
    if (!bb.isEmpty) {
      final strokeRect = Rect.fromLTRB(bb.minX, bb.minY, bb.maxX, bb.maxY);
      // 약간의 여유를 두고 체크 (선 굵기 고려)
      final expandedRect = strokeRect.inflate(stroke.width);
      return viewport.overlaps(expandedRect);
    }

    // BoundingBox가 없으면 포인트 기반 체크
    for (final point in stroke.points) {
      if (viewport.contains(Offset(point.x, point.y))) {
        return true;
      }
    }
    return false;
  }

  /// 스트로크가 지우개 범위 내에 있는지 확인
  bool _isStrokeInEraserRange(Stroke stroke, Offset eraserPos, double radius) {
    for (final point in stroke.points) {
      final distance = (Offset(point.x, point.y) - eraserPos).distance;
      if (distance <= radius + stroke.width / 2) {
        return true;
      }
    }
    return false;
  }

  /// 지우개로 지워질 스트로크 부분 하이라이트
  void _drawEraserPreviewHighlight(Canvas canvas, Stroke stroke, Offset eraserPos, double radius) {
    final highlightPaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.4 )
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke.width + 4;

    // 지우개 범위 내의 포인트만 하이라이트
    for (int i = 0; i < stroke.points.length - 1; i++) {
      final p1 = stroke.points[i];
      final p2 = stroke.points[i + 1];

      final d1 = (Offset(p1.x, p1.y) - eraserPos).distance;
      final d2 = (Offset(p2.x, p2.y) - eraserPos).distance;

      // 두 점 중 하나라도 지우개 범위 내에 있으면 하이라이트
      if (d1 <= radius + stroke.width / 2 || d2 <= radius + stroke.width / 2) {
        canvas.drawLine(
          Offset(p1.x, p1.y),
          Offset(p2.x, p2.y),
          highlightPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant StrokePainter oldDelegate) {
    // 캐시 이미지가 변경되면 repaint
    if (cachedStrokesImage != oldDelegate.cachedStrokesImage) return true;
    
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
    // Viewport changes (zoom/pan) require repaint
    if (visibleRect != oldDelegate.visibleRect) return true;
    return false;
  }
}

/// Image painter for rendering images on canvas
class ImagePainter extends CustomPainter {
  final List<CanvasImage> images;
  final Map<String, ui.Image> loadedImages;
  final String? selectedImageId;

  ImagePainter({
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
          Paint()..color = Colors.blue..strokeWidth = 2,);
        canvas.drawCircle(rotationHandlePos, 8, handleBorderPaint);
        canvas.drawCircle(rotationHandlePos, 6, Paint()..color = Colors.green);
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant ImagePainter oldDelegate) {
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
class ShapePainter extends CustomPainter {
  final List<CanvasShape> shapes;
  final String? selectedShapeId;

  ShapePainter({
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
          ..color = Colors.blue.withValues(alpha: 0.3 )
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
  bool shouldRepaint(covariant ShapePainter oldDelegate) {
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
class TablePainter extends CustomPainter {
  final List<CanvasTable> tables;
  final String? selectedTableId;
  final String? readyToDragId; // 드래그 준비 완료 상태 (1초 롱프레스 완료)
  final String? resizeWaitingTableId; // 리사이즈 대기 중인 테이블 ID
  final int resizeWaitingColumnIndex; // 리사이즈 대기 중인 컬럼 인덱스 (-1=없음, -99=왼쪽외곽)
  final int resizeWaitingRowIndex; // 리사이즈 대기 중인 행 인덱스 (-1=없음)
  final bool isResizeActive; // 리사이즈 활성화 상태 (롱프레스 완료)

  // 성능 최적화: TextPainter 캐시 (tableId:row:col -> TextPainter)
  // LRU 순서 유지를 위해 LinkedHashMap 사용
  static final Map<String, TextPainter> _textPainterCache = <String, TextPainter>{};
  static final List<String> _cacheAccessOrder = []; // LRU 순서 추적
  static const int _maxCacheSize = 500;

  TablePainter({
    required this.tables,
    this.selectedTableId,
    this.readyToDragId,
    this.resizeWaitingTableId,
    this.resizeWaitingColumnIndex = -1,
    this.resizeWaitingRowIndex = -1,
    this.isResizeActive = false,
  });

  /// 캐시 정리 (메모리 해제)
  static void clearCache() {
    for (final painter in _textPainterCache.values) {
      painter.dispose();
    }
    _textPainterCache.clear();
    _cacheAccessOrder.clear();
  }

  /// 캐시된 TextPainter 가져오기 또는 생성
  TextPainter _getCachedTextPainter(String cacheKey, String content, Color color, double maxWidth) {
    final cached = _textPainterCache[cacheKey];
    if (cached != null) {
      // LRU: 접근된 항목을 맨 뒤로 이동
      _cacheAccessOrder.remove(cacheKey);
      _cacheAccessOrder.add(cacheKey);
      return cached;
    }

    // 캐시 크기 제한 - LRU 방식으로 오래된 항목 제거
    while (_textPainterCache.length >= _maxCacheSize && _cacheAccessOrder.isNotEmpty) {
      final oldestKey = _cacheAccessOrder.removeAt(0);
      final oldPainter = _textPainterCache.remove(oldestKey);
      oldPainter?.dispose(); // 메모리 해제
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
    _cacheAccessOrder.add(cacheKey);
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
          ..color = Colors.blue.withValues(alpha: 0.2 )
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
          ..color = Colors.orange.withValues(alpha: 0.3 )
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
  bool shouldRepaint(covariant TablePainter oldDelegate) {
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
class CanvasTextPainter extends CustomPainter {
  final List<CanvasText> texts;
  final String? selectedTextId;

  CanvasTextPainter({
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
  bool shouldRepaint(covariant CanvasTextPainter oldDelegate) {
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
class BackgroundImageWidget extends StatelessWidget {
  final String imagePath;
  final ui.Image? loadedImage;

  const BackgroundImageWidget({super.key, 
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
      painter: BackgroundImagePainter(image: loadedImage!),
      size: Size.infinite,
    );
  }
}

/// 배경 이미지 페인터
/// 캔버스 전체에 이미지를 채워서 렌더링 (cover 모드 - 전체 채움)
class BackgroundImagePainter extends CustomPainter {
  final ui.Image image;

  BackgroundImagePainter({required this.image});

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

    // 50% 투명도로 배경 이미지 렌더링 (스캔 문서가 보이면서 필기도 가능하도록)
    final paint = Paint()
      ..colorFilter = const ColorFilter.matrix(<double>[
        1, 0, 0, 0, 0,    // R
        0, 1, 0, 0, 0,    // G
        0, 0, 1, 0, 0,    // B
        0, 0, 0, 0.50, 0, // A (50% 투명도)
      ]);
    canvas.drawImageRect(image, srcRect, destRect, paint);
  }

  @override
  bool shouldRepaint(covariant BackgroundImagePainter oldDelegate) =>
      image != oldDelegate.image;
}
