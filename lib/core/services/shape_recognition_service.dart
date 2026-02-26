import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../domain/entities/stroke.dart';
import '../../domain/entities/stroke_point.dart';

/// 인식된 도형 종류
enum RecognizedShapeType {
  none,       // 인식 실패 (일반 스트로크 유지)
  line,       // 직선
  rectangle,  // 사각형
  circle,     // 원
  triangle,   // 삼각형
  arrow,      // 화살표
}

/// 도형 인식 결과
class ShapeRecognitionResult {
  final RecognizedShapeType type;
  final double confidence;  // 0.0 ~ 1.0
  final List<Offset> keyPoints;  // 도형의 핵심 포인트들
  final Rect boundingBox;

  ShapeRecognitionResult({
    required this.type,
    required this.confidence,
    required this.keyPoints,
    required this.boundingBox,
  });

  bool get isRecognized => type != RecognizedShapeType.none && confidence >= 0.7;
}

/// 도형 자동 인식 서비스
/// 손으로 그린 스트로크를 분석하여 직선/원/사각형 등으로 변환
class ShapeRecognitionService {
  static final ShapeRecognitionService instance = ShapeRecognitionService._();
  ShapeRecognitionService._();

  /// 인식 활성화 여부
  bool _enabled = false;
  bool get enabled => _enabled;
  set enabled(bool value) => _enabled = value;

  /// 인식 임계값 (0.0 ~ 1.0)
  double _threshold = 0.75;
  double get threshold => _threshold;
  set threshold(double value) => _threshold = value.clamp(0.5, 0.95);

  /// 스트로크를 분석하여 도형 인식
  ShapeRecognitionResult recognize(Stroke stroke) {
    if (!_enabled || stroke.points.length < 3) {
      return _noMatch(stroke);
    }

    final points = stroke.points;
    final boundingBox = _calculateBoundingBox(points);

    // 1. 직선 체크 (가장 먼저 - 가장 단순한 도형)
    final lineResult = _checkLine(points, boundingBox);
    if (lineResult.confidence >= _threshold) {
      return lineResult;
    }

    // 2. 코너 감지 - 코너 개수에 따라 도형 종류 결정
    final corners = _detectCorners(points);

    // 3개 코너 → 삼각형 우선 체크
    if (corners.length == 3) {
      final triangleResult = _checkTriangle(points, boundingBox);
      if (triangleResult.confidence >= _threshold) {
        return triangleResult;
      }
    }

    // 4개 코너 → 사각형 우선 체크
    if (corners.length >= 4 && corners.length <= 6) {
      final rectResult = _checkRectangle(points, boundingBox);
      if (rectResult.confidence >= _threshold) {
        return rectResult;
      }
    }

    // 코너가 거의 없거나 매우 많음 → 원 체크
    if (corners.length < 3 || corners.length > 6) {
      final circleResult = _checkCircle(points, boundingBox);
      if (circleResult.confidence >= _threshold) {
        return circleResult;
      }
    }

    // 모든 도형 재시도 (낮은 신뢰도라도)
    final allResults = [
      _checkCircle(points, boundingBox),
      _checkRectangle(points, boundingBox),
      _checkTriangle(points, boundingBox),
    ];

    // 가장 높은 신뢰도 선택
    allResults.sort((a, b) => b.confidence.compareTo(a.confidence));
    if (allResults.first.confidence >= _threshold) {
      return allResults.first;
    }

    // 인식 실패
    return _noMatch(stroke);
  }

  /// 직선 인식
  ShapeRecognitionResult _checkLine(List<StrokePoint> points, Rect boundingBox) {
    if (points.length < 2) {
      return _noMatchResult(boundingBox);
    }

    final start = Offset(points.first.x, points.first.y);
    final end = Offset(points.last.x, points.last.y);
    final lineLength = (end - start).distance;

    // 너무 짧은 선은 제외
    if (lineLength < 30) {
      return _noMatchResult(boundingBox);
    }

    // 모든 점이 직선에 얼마나 가까운지 측정
    double totalDeviation = 0;
    for (final point in points) {
      final p = Offset(point.x, point.y);
      final distance = _pointToLineDistance(p, start, end);
      totalDeviation += distance;
    }

    final avgDeviation = totalDeviation / points.length;
    final maxAllowedDeviation = lineLength * 0.08; // 선 길이의 8%

    // 신뢰도 계산
    final confidence = (1.0 - (avgDeviation / maxAllowedDeviation)).clamp(0.0, 1.0);

    return ShapeRecognitionResult(
      type: RecognizedShapeType.line,
      confidence: confidence,
      keyPoints: [start, end],
      boundingBox: boundingBox,
    );
  }

  /// 원 인식
  ShapeRecognitionResult _checkCircle(List<StrokePoint> points, Rect boundingBox) {
    if (points.length < 8) {
      return _noMatchResult(boundingBox);
    }

    // 중심점 계산
    double sumX = 0, sumY = 0;
    for (final p in points) {
      sumX += p.x;
      sumY += p.y;
    }
    final center = Offset(sumX / points.length, sumY / points.length);

    // 평균 반지름 계산
    double sumRadius = 0;
    for (final p in points) {
      sumRadius += (Offset(p.x, p.y) - center).distance;
    }
    final avgRadius = sumRadius / points.length;

    // 너무 작은 원은 제외
    if (avgRadius < 15) {
      return _noMatchResult(boundingBox);
    }

    // 반지름 편차 측정
    double radiusVariance = 0;
    for (final p in points) {
      final radius = (Offset(p.x, p.y) - center).distance;
      radiusVariance += (radius - avgRadius).abs();
    }
    final avgRadiusDeviation = radiusVariance / points.length;

    // 시작점과 끝점이 가까운지 (닫힌 도형)
    final startEnd = Offset(points.first.x, points.first.y);
    final endPt = Offset(points.last.x, points.last.y);
    final closedness = 1.0 - ((startEnd - endPt).distance / (avgRadius * 2)).clamp(0.0, 1.0);

    // 신뢰도 계산
    final radiusConsistency = (1.0 - (avgRadiusDeviation / avgRadius)).clamp(0.0, 1.0);
    final confidence = (radiusConsistency * 0.6 + closedness * 0.4).clamp(0.0, 1.0);

    return ShapeRecognitionResult(
      type: RecognizedShapeType.circle,
      confidence: confidence,
      keyPoints: [
        center,
        Offset(center.dx + avgRadius, center.dy), // 오른쪽 점 (반지름 표시)
      ],
      boundingBox: Rect.fromCircle(center: center, radius: avgRadius),
    );
  }

  /// 사각형 인식
  ShapeRecognitionResult _checkRectangle(List<StrokePoint> points, Rect boundingBox) {
    if (points.length < 12) {
      return _noMatchResult(boundingBox);
    }

    // 코너 감지
    final corners = _detectCorners(points);

    // 4개의 코너가 있어야 함
    if (corners.length < 4 || corners.length > 6) {
      return _noMatchResult(boundingBox);
    }

    // 시작점과 끝점이 가까운지 (닫힌 도형)
    final start = Offset(points.first.x, points.first.y);
    final end = Offset(points.last.x, points.last.y);
    final diagonal = math.sqrt(
      boundingBox.width * boundingBox.width +
      boundingBox.height * boundingBox.height,
    );
    final closedness = 1.0 - ((start - end).distance / (diagonal * 0.2)).clamp(0.0, 1.0);

    // 바운딩 박스와의 일치도 측정
    double boundingBoxFit = 0;
    for (final p in points) {
      final pt = Offset(p.x, p.y);
      // 각 점이 바운딩 박스 가장자리에 얼마나 가까운지
      final distToEdge = _distanceToRectEdge(pt, boundingBox);
      boundingBoxFit += (1.0 - (distToEdge / (diagonal * 0.1)).clamp(0.0, 1.0));
    }
    boundingBoxFit /= points.length;

    // 신뢰도 계산
    final cornerScore = corners.length == 4 ? 1.0 : 0.8;
    final confidence = (cornerScore * 0.3 + boundingBoxFit * 0.4 + closedness * 0.3).clamp(0.0, 1.0);

    return ShapeRecognitionResult(
      type: RecognizedShapeType.rectangle,
      confidence: confidence,
      keyPoints: [
        boundingBox.topLeft,
        boundingBox.topRight,
        boundingBox.bottomRight,
        boundingBox.bottomLeft,
      ],
      boundingBox: boundingBox,
    );
  }

  /// 삼각형 인식
  ShapeRecognitionResult _checkTriangle(List<StrokePoint> points, Rect boundingBox) {
    if (points.length < 9) {
      return _noMatchResult(boundingBox);
    }

    // 코너 감지
    final corners = _detectCorners(points);

    // 3개의 코너가 있어야 함
    if (corners.length != 3) {
      return _noMatchResult(boundingBox);
    }

    // 시작점과 끝점이 가까운지 (닫힌 도형)
    final start = Offset(points.first.x, points.first.y);
    final end = Offset(points.last.x, points.last.y);
    final diagonal = math.sqrt(
      boundingBox.width * boundingBox.width +
      boundingBox.height * boundingBox.height,
    );
    final closedness = 1.0 - ((start - end).distance / (diagonal * 0.2)).clamp(0.0, 1.0);

    // 세 변의 직선성 측정
    double linearity = 0;
    for (int i = 0; i < 3; i++) {
      final from = corners[i];
      final to = corners[(i + 1) % 3];
      final segment = _getPointsBetween(points, from, to);
      if (segment.isNotEmpty) {
        linearity += _measureLinearity(segment, from, to);
      }
    }
    linearity /= 3;

    // 신뢰도 계산
    final confidence = (linearity * 0.6 + closedness * 0.4).clamp(0.0, 1.0);

    return ShapeRecognitionResult(
      type: RecognizedShapeType.triangle,
      confidence: confidence,
      keyPoints: corners,
      boundingBox: boundingBox,
    );
  }

  /// 코너 감지 (방향 변화가 큰 점들)
  List<Offset> _detectCorners(List<StrokePoint> points) {
    if (points.length < 5) return [];

    final corners = <Offset>[];
    const angleThreshold = 45 * math.pi / 180; // 45도 이상 변화
    const windowSize = 3;

    for (int i = windowSize; i < points.length - windowSize; i++) {
      final before = Offset(points[i - windowSize].x, points[i - windowSize].y);
      final current = Offset(points[i].x, points[i].y);
      final after = Offset(points[i + windowSize].x, points[i + windowSize].y);

      final angle = _angleBetweenVectors(current - before, after - current);

      if (angle > angleThreshold) {
        // 이전 코너와 너무 가까우면 무시
        if (corners.isEmpty || (current - corners.last).distance > 20) {
          corners.add(current);
        }
      }
    }

    return corners;
  }

  /// 점에서 직선까지의 거리
  double _pointToLineDistance(Offset point, Offset lineStart, Offset lineEnd) {
    final lineVec = lineEnd - lineStart;
    final lineLength = lineVec.distance;

    if (lineLength == 0) {
      return (point - lineStart).distance;
    }

    final t = ((point - lineStart).dx * lineVec.dx + (point - lineStart).dy * lineVec.dy) /
              (lineLength * lineLength);

    if (t < 0) {
      return (point - lineStart).distance;
    } else if (t > 1) {
      return (point - lineEnd).distance;
    }

    final projection = lineStart + lineVec * t;
    return (point - projection).distance;
  }

  /// 점에서 사각형 가장자리까지의 거리
  double _distanceToRectEdge(Offset point, Rect rect) {
    final dx = math.max(rect.left - point.dx, math.max(0.0, point.dx - rect.right));
    final dy = math.max(rect.top - point.dy, math.max(0.0, point.dy - rect.bottom));

    if (dx == 0 && dy == 0) {
      // 점이 사각형 내부에 있음 - 가장자리까지 거리
      return math.min(
        math.min(point.dx - rect.left, rect.right - point.dx),
        math.min(point.dy - rect.top, rect.bottom - point.dy),
      );
    }

    return math.sqrt(dx * dx + dy * dy);
  }

  /// 두 벡터 사이의 각도
  double _angleBetweenVectors(Offset v1, Offset v2) {
    final dot = v1.dx * v2.dx + v1.dy * v2.dy;
    final mag1 = v1.distance;
    final mag2 = v2.distance;

    if (mag1 == 0 || mag2 == 0) return 0;

    final cosAngle = (dot / (mag1 * mag2)).clamp(-1.0, 1.0);
    return math.acos(cosAngle);
  }

  /// 두 점 사이의 포인트들 추출
  List<StrokePoint> _getPointsBetween(List<StrokePoint> points, Offset from, Offset to) {
    int fromIdx = -1, toIdx = -1;
    double minFromDist = double.infinity, minToDist = double.infinity;

    for (int i = 0; i < points.length; i++) {
      final p = Offset(points[i].x, points[i].y);
      final fromDist = (p - from).distance;
      final toDist = (p - to).distance;

      if (fromDist < minFromDist) {
        minFromDist = fromDist;
        fromIdx = i;
      }
      if (toDist < minToDist) {
        minToDist = toDist;
        toIdx = i;
      }
    }

    if (fromIdx == -1 || toIdx == -1 || fromIdx >= toIdx) {
      return [];
    }

    return points.sublist(fromIdx, toIdx + 1);
  }

  /// 직선성 측정
  double _measureLinearity(List<StrokePoint> segment, Offset start, Offset end) {
    if (segment.length < 2) return 1.0;

    double totalDeviation = 0;
    for (final p in segment) {
      totalDeviation += _pointToLineDistance(Offset(p.x, p.y), start, end);
    }

    final avgDeviation = totalDeviation / segment.length;
    final lineLength = (end - start).distance;

    if (lineLength == 0) return 0;

    return (1.0 - (avgDeviation / (lineLength * 0.1))).clamp(0.0, 1.0);
  }

  /// 바운딩 박스 계산
  Rect _calculateBoundingBox(List<StrokePoint> points) {
    if (points.isEmpty) return Rect.zero;

    double minX = points.first.x, maxX = points.first.x;
    double minY = points.first.y, maxY = points.first.y;

    for (final p in points) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// 인식 실패 결과
  ShapeRecognitionResult _noMatch(Stroke stroke) {
    return ShapeRecognitionResult(
      type: RecognizedShapeType.none,
      confidence: 0.0,
      keyPoints: [],
      boundingBox: stroke.boundingBox.toRect(),
    );
  }

  ShapeRecognitionResult _noMatchResult(Rect boundingBox) {
    return ShapeRecognitionResult(
      type: RecognizedShapeType.none,
      confidence: 0.0,
      keyPoints: [],
      boundingBox: boundingBox,
    );
  }

  /// 인식된 도형을 Stroke로 변환
  Stroke? convertToShape(Stroke originalStroke, ShapeRecognitionResult result) {
    if (!result.isRecognized) return null;

    final points = <StrokePoint>[];
    final now = DateTime.now().millisecondsSinceEpoch;

    switch (result.type) {
      case RecognizedShapeType.line:
        if (result.keyPoints.length >= 2) {
          points.add(StrokePoint(
            x: result.keyPoints[0].dx,
            y: result.keyPoints[0].dy,
            pressure: 0.5,
            tilt: 0,
            timestamp: now,
          ),);
          points.add(StrokePoint(
            x: result.keyPoints[1].dx,
            y: result.keyPoints[1].dy,
            pressure: 0.5,
            tilt: 0,
            timestamp: now + 1,
          ),);
        }
        return Stroke(
          id: originalStroke.id,
          toolType: originalStroke.toolType,
          color: originalStroke.color,
          width: originalStroke.width,
          points: points,
          timestamp: originalStroke.timestamp,
          isShape: true,
          shapeType: ShapeType.line,
        );

      case RecognizedShapeType.circle:
        // 원을 포인트들로 구성
        if (result.keyPoints.length >= 2) {
          final center = result.keyPoints[0];
          final radius = (result.keyPoints[1] - center).distance;
          const segments = 36; // 10도 간격

          for (int i = 0; i <= segments; i++) {
            final angle = (i / segments) * 2 * math.pi;
            points.add(StrokePoint(
              x: center.dx + radius * math.cos(angle),
              y: center.dy + radius * math.sin(angle),
              pressure: 0.5,
              tilt: 0,
              timestamp: now + i,
            ),);
          }
        }
        return Stroke(
          id: originalStroke.id,
          toolType: originalStroke.toolType,
          color: originalStroke.color,
          width: originalStroke.width,
          points: points,
          timestamp: originalStroke.timestamp,
          isShape: true,
          shapeType: ShapeType.circle,
        );

      case RecognizedShapeType.rectangle:
        if (result.keyPoints.length >= 4) {
          for (int i = 0; i <= 4; i++) {
            final pt = result.keyPoints[i % 4];
            points.add(StrokePoint(
              x: pt.dx,
              y: pt.dy,
              pressure: 0.5,
              tilt: 0,
              timestamp: now + i,
            ),);
          }
        }
        return Stroke(
          id: originalStroke.id,
          toolType: originalStroke.toolType,
          color: originalStroke.color,
          width: originalStroke.width,
          points: points,
          timestamp: originalStroke.timestamp,
          isShape: true,
          shapeType: ShapeType.rectangle,
        );

      case RecognizedShapeType.triangle:
        if (result.keyPoints.length >= 3) {
          for (int i = 0; i <= 3; i++) {
            final pt = result.keyPoints[i % 3];
            points.add(StrokePoint(
              x: pt.dx,
              y: pt.dy,
              pressure: 0.5,
              tilt: 0,
              timestamp: now + i,
            ),);
          }
        }
        return Stroke(
          id: originalStroke.id,
          toolType: originalStroke.toolType,
          color: originalStroke.color,
          width: originalStroke.width,
          points: points,
          timestamp: originalStroke.timestamp,
          isShape: true,
          shapeType: ShapeType.none, // 삼각형은 별도 ShapeType 없음
        );

      default:
        return null;
    }
  }
}
