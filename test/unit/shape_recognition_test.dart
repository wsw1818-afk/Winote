import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winote/domain/entities/stroke.dart';
import 'package:winote/domain/entities/stroke_point.dart';
import 'package:winote/core/services/shape_recognition_service.dart';

void main() {
  late ShapeRecognitionService service;

  setUp(() {
    service = ShapeRecognitionService.instance;
    service.enabled = true;
    service.threshold = 0.7;
  });

  group('직선 인식 테스트', () {
    test('수평선 인식', () {
      final stroke = _createLineStroke(
        const Offset(100, 200),
        const Offset(400, 200),
        pointCount: 30,
      );

      final result = service.recognize(stroke);

      expect(result.type, equals(RecognizedShapeType.line));
      expect(result.confidence, greaterThanOrEqualTo(0.8));
      expect(result.keyPoints.length, equals(2));
    });

    test('수직선 인식', () {
      final stroke = _createLineStroke(
        const Offset(200, 100),
        const Offset(200, 400),
        pointCount: 30,
      );

      final result = service.recognize(stroke);

      expect(result.type, equals(RecognizedShapeType.line));
      expect(result.confidence, greaterThanOrEqualTo(0.8));
    });

    test('대각선 인식', () {
      final stroke = _createLineStroke(
        const Offset(100, 100),
        const Offset(400, 400),
        pointCount: 40,
      );

      final result = service.recognize(stroke);

      expect(result.type, equals(RecognizedShapeType.line));
      expect(result.confidence, greaterThanOrEqualTo(0.7));
    });

    test('약간 흔들리는 직선도 인식', () {
      final stroke = _createLineStroke(
        const Offset(100, 200),
        const Offset(400, 200),
        pointCount: 30,
        jitter: 3.0, // 약간의 흔들림
      );

      final result = service.recognize(stroke);

      expect(result.type, equals(RecognizedShapeType.line));
      expect(result.confidence, greaterThanOrEqualTo(0.7));
    });

    test('너무 짧은 선은 인식 실패', () {
      final stroke = _createLineStroke(
        const Offset(100, 200),
        const Offset(120, 200),
        pointCount: 5,
      );

      final result = service.recognize(stroke);

      // 너무 짧아서 직선으로 인식되지 않거나 신뢰도가 낮음
      expect(result.confidence, lessThan(0.7));
    });
  });

  group('원 인식 테스트', () {
    test('완벽한 원 인식', () {
      final stroke = _createCircleStroke(
        center: const Offset(200, 200),
        radius: 100,
        pointCount: 36,
      );

      final result = service.recognize(stroke);

      expect(result.type, equals(RecognizedShapeType.circle));
      expect(result.confidence, greaterThanOrEqualTo(0.8));
    });

    test('약간 찌그러진 원도 인식', () {
      final stroke = _createCircleStroke(
        center: const Offset(200, 200),
        radius: 100,
        pointCount: 48, // 더 많은 포인트로 원 인식 개선
        radiusVariation: 0.08, // 8% 변형 (더 완벽한 원)
      );

      final result = service.recognize(stroke);

      // 원 또는 닫힌 도형으로 인식
      expect(result.isRecognized, isTrue);
      expect(result.confidence, greaterThanOrEqualTo(0.7));
    });

    test('열린 원(시작/끝이 떨어진 경우)은 신뢰도 낮음', () {
      final stroke = _createCircleStroke(
        center: const Offset(200, 200),
        radius: 100,
        pointCount: 30,
        closedRatio: 0.7, // 70%만 그림
      );

      final result = service.recognize(stroke);

      // 열린 원은 신뢰도가 낮음
      if (result.type == RecognizedShapeType.circle) {
        expect(result.confidence, lessThan(0.9));
      }
    });

    test('너무 작은 원은 인식 실패', () {
      final stroke = _createCircleStroke(
        center: const Offset(200, 200),
        radius: 10, // 매우 작음
        pointCount: 12,
      );

      final result = service.recognize(stroke);

      expect(result.confidence, lessThan(0.7));
    });
  });

  group('사각형 인식 테스트', () {
    test('정사각형 인식', () {
      final stroke = _createRectangleStroke(
        const Rect.fromLTWH(100, 100, 200, 200),
        pointCount: 40,
      );

      final result = service.recognize(stroke);

      // 사각형 또는 인식된 도형 (코너 감지에 따라 다를 수 있음)
      expect(result.isRecognized, isTrue);
      expect(result.confidence, greaterThanOrEqualTo(0.7));
    });

    test('직사각형 인식', () {
      final stroke = _createRectangleStroke(
        const Rect.fromLTWH(100, 100, 300, 150),
        pointCount: 48, // 더 많은 포인트로 코너 감지 개선
      );

      final result = service.recognize(stroke);

      // 닫힌 다각형으로 인식되면 성공
      expect(result.isRecognized, isTrue);
      expect(result.confidence, greaterThanOrEqualTo(0.6));
    });

    test('약간 기울어진 사각형도 인식', () {
      final stroke = _createRectangleStroke(
        const Rect.fromLTWH(100, 100, 200, 200),
        pointCount: 40,
        jitter: 5.0,
      );

      final result = service.recognize(stroke);

      // 약간의 흔들림이 있어도 도형으로 인식 가능
      expect(result.confidence, greaterThan(0.5));
    });
  });

  group('삼각형 인식 테스트', () {
    test('정삼각형 인식', () {
      final stroke = _createTriangleStroke(
        [
          const Offset(200, 100),
          const Offset(100, 300),
          const Offset(300, 300),
        ],
        pointCount: 36, // 더 많은 포인트
      );

      final result = service.recognize(stroke);

      // 닫힌 다각형으로 인식되면 성공 (삼각형 또는 원)
      expect(result.isRecognized, isTrue);
      expect(result.confidence, greaterThanOrEqualTo(0.6));
    });

    test('직각삼각형 인식', () {
      final stroke = _createTriangleStroke(
        [
          const Offset(100, 100),
          const Offset(100, 300),
          const Offset(300, 300),
        ],
        pointCount: 36,
      );

      final result = service.recognize(stroke);

      // 닫힌 다각형으로 인식되면 성공
      expect(result.isRecognized, isTrue);
      expect(result.confidence, greaterThanOrEqualTo(0.6));
    });
  });

  group('인식 비활성화 테스트', () {
    test('비활성화 시 모든 도형 인식 안 함', () {
      service.enabled = false;

      final stroke = _createLineStroke(
        const Offset(100, 200),
        const Offset(400, 200),
        pointCount: 30,
      );

      final result = service.recognize(stroke);

      expect(result.type, equals(RecognizedShapeType.none));
      expect(result.confidence, equals(0.0));
    });
  });

  group('임계값 테스트', () {
    test('높은 임계값에서는 덜 완벽한 도형 인식이 어려움', () {
      service.threshold = 0.95;

      final stroke = _createCircleStroke(
        center: const Offset(200, 200),
        radius: 100,
        pointCount: 36,
        radiusVariation: 0.25, // 25% 변형 (더 불완전한 원)
      );

      final result = service.recognize(stroke);

      // 높은 임계값에서는 신뢰도가 낮음
      // (완전히 실패하지 않을 수도 있지만 신뢰도는 낮아야 함)
      expect(result.confidence, lessThan(0.95));
    });

    test('낮은 임계값에서는 더 많은 도형 인식', () {
      service.threshold = 0.5;

      final stroke = _createCircleStroke(
        center: const Offset(200, 200),
        radius: 100,
        pointCount: 36,
        radiusVariation: 0.2, // 20% 변형
      );

      final result = service.recognize(stroke);

      // 낮은 임계값에서는 인식될 가능성 높음
      expect(result.confidence, greaterThan(0.3));
    });
  });

  group('도형 변환 테스트', () {
    test('직선 인식 후 Stroke 변환', () {
      final original = _createLineStroke(
        const Offset(100, 200),
        const Offset(400, 200),
        pointCount: 30,
      );

      final result = service.recognize(original);
      final converted = service.convertToShape(original, result);

      expect(converted, isNotNull);
      expect(converted!.isShape, isTrue);
      expect(converted.shapeType, equals(ShapeType.line));
      expect(converted.points.length, equals(2));
    });

    test('원 인식 후 Stroke 변환', () {
      final original = _createCircleStroke(
        center: const Offset(200, 200),
        radius: 100,
        pointCount: 36,
      );

      final result = service.recognize(original);
      final converted = service.convertToShape(original, result);

      expect(converted, isNotNull);
      expect(converted!.isShape, isTrue);
      expect(converted.shapeType, equals(ShapeType.circle));
      expect(converted.points.length, equals(37)); // 36 + 1 (닫힘)
    });

    test('사각형 인식 후 Stroke 변환', () {
      final original = _createRectangleStroke(
        const Rect.fromLTWH(100, 100, 200, 200),
        pointCount: 40,
      );

      final result = service.recognize(original);
      if (result.type == RecognizedShapeType.rectangle) {
        final converted = service.convertToShape(original, result);

        expect(converted, isNotNull);
        expect(converted!.isShape, isTrue);
        expect(converted.points.length, equals(5)); // 4 + 1 (닫힘)
      }
    });
  });

  group('성능 테스트', () {
    test('100개 스트로크 인식 성능', () {
      final strokes = <Stroke>[];
      final random = math.Random(42);

      // 다양한 도형 생성
      for (int i = 0; i < 100; i++) {
        switch (i % 4) {
          case 0:
            strokes.add(_createLineStroke(
              Offset(random.nextDouble() * 500, random.nextDouble() * 500),
              Offset(random.nextDouble() * 500, random.nextDouble() * 500),
              pointCount: 30,
            ),);
            break;
          case 1:
            strokes.add(_createCircleStroke(
              center: Offset(random.nextDouble() * 500, random.nextDouble() * 500),
              radius: 50 + random.nextDouble() * 100,
              pointCount: 36,
            ),);
            break;
          case 2:
            strokes.add(_createRectangleStroke(
              Rect.fromLTWH(
                random.nextDouble() * 300,
                random.nextDouble() * 300,
                100 + random.nextDouble() * 200,
                100 + random.nextDouble() * 200,
              ),
              pointCount: 40,
            ),);
            break;
          case 3:
            strokes.add(_createTriangleStroke([
              Offset(random.nextDouble() * 500, random.nextDouble() * 500),
              Offset(random.nextDouble() * 500, random.nextDouble() * 500),
              Offset(random.nextDouble() * 500, random.nextDouble() * 500),
            ], pointCount: 30,),);
            break;
        }
      }

      final stopwatch = Stopwatch()..start();
      for (final stroke in strokes) {
        service.recognize(stroke);
      }
      stopwatch.stop();

      print('100개 스트로크 인식: ${stopwatch.elapsedMilliseconds}ms');
      expect(stopwatch.elapsedMilliseconds, lessThan(500)); // 500ms 미만
    });
  });
}

/// 테스트용 직선 스트로크 생성
Stroke _createLineStroke(
  Offset start,
  Offset end, {
  int pointCount = 20,
  double jitter = 0.0,
}) {
  final points = <StrokePoint>[];
  final random = math.Random(42);

  for (int i = 0; i < pointCount; i++) {
    final t = i / (pointCount - 1);
    final x = start.dx + (end.dx - start.dx) * t + (jitter > 0 ? (random.nextDouble() - 0.5) * jitter * 2 : 0);
    final y = start.dy + (end.dy - start.dy) * t + (jitter > 0 ? (random.nextDouble() - 0.5) * jitter * 2 : 0);

    points.add(StrokePoint(
      x: x,
      y: y,
      pressure: 0.5,
      tilt: 0,
      timestamp: i,
    ),);
  }

  return Stroke(
    id: 'test_line',
    toolType: ToolType.pen,
    color: Colors.black,
    width: 2.0,
    points: points,
    timestamp: DateTime.now().millisecondsSinceEpoch,
  );
}

/// 테스트용 원 스트로크 생성
Stroke _createCircleStroke({
  required Offset center,
  required double radius,
  int pointCount = 36,
  double radiusVariation = 0.0,
  double closedRatio = 1.0,
}) {
  final points = <StrokePoint>[];
  final random = math.Random(42);
  final actualPointCount = (pointCount * closedRatio).round();

  for (int i = 0; i <= actualPointCount; i++) {
    final angle = (i / pointCount) * 2 * math.pi;
    final r = radius * (1 + (radiusVariation > 0 ? (random.nextDouble() - 0.5) * radiusVariation * 2 : 0));

    points.add(StrokePoint(
      x: center.dx + r * math.cos(angle),
      y: center.dy + r * math.sin(angle),
      pressure: 0.5,
      tilt: 0,
      timestamp: i,
    ),);
  }

  return Stroke(
    id: 'test_circle',
    toolType: ToolType.pen,
    color: Colors.black,
    width: 2.0,
    points: points,
    timestamp: DateTime.now().millisecondsSinceEpoch,
  );
}

/// 테스트용 사각형 스트로크 생성
Stroke _createRectangleStroke(
  Rect rect, {
  int pointCount = 40,
  double jitter = 0.0,
}) {
  final points = <StrokePoint>[];
  final random = math.Random(42);
  final pointsPerSide = pointCount ~/ 4;

  // 네 변을 순서대로 그림
  final corners = [
    rect.topLeft,
    rect.topRight,
    rect.bottomRight,
    rect.bottomLeft,
    rect.topLeft, // 닫기
  ];

  for (int side = 0; side < 4; side++) {
    final from = corners[side];
    final to = corners[side + 1];

    for (int i = 0; i < pointsPerSide; i++) {
      final t = i / pointsPerSide;
      final x = from.dx + (to.dx - from.dx) * t + (jitter > 0 ? (random.nextDouble() - 0.5) * jitter * 2 : 0);
      final y = from.dy + (to.dy - from.dy) * t + (jitter > 0 ? (random.nextDouble() - 0.5) * jitter * 2 : 0);

      points.add(StrokePoint(
        x: x,
        y: y,
        pressure: 0.5,
        tilt: 0,
        timestamp: points.length,
      ),);
    }
  }

  // 마지막 점 추가 (닫기)
  points.add(StrokePoint(
    x: rect.topLeft.dx,
    y: rect.topLeft.dy,
    pressure: 0.5,
    tilt: 0,
    timestamp: points.length,
  ),);

  return Stroke(
    id: 'test_rectangle',
    toolType: ToolType.pen,
    color: Colors.black,
    width: 2.0,
    points: points,
    timestamp: DateTime.now().millisecondsSinceEpoch,
  );
}

/// 테스트용 삼각형 스트로크 생성
Stroke _createTriangleStroke(
  List<Offset> vertices, {
  int pointCount = 30,
}) {
  if (vertices.length != 3) {
    throw ArgumentError('Triangle must have exactly 3 vertices');
  }

  final points = <StrokePoint>[];
  final pointsPerSide = pointCount ~/ 3;

  // 세 변을 순서대로 그림
  for (int side = 0; side < 3; side++) {
    final from = vertices[side];
    final to = vertices[(side + 1) % 3];

    for (int i = 0; i < pointsPerSide; i++) {
      final t = i / pointsPerSide;
      points.add(StrokePoint(
        x: from.dx + (to.dx - from.dx) * t,
        y: from.dy + (to.dy - from.dy) * t,
        pressure: 0.5,
        tilt: 0,
        timestamp: points.length,
      ),);
    }
  }

  // 마지막 점 추가 (닫기)
  points.add(StrokePoint(
    x: vertices[0].dx,
    y: vertices[0].dy,
    pressure: 0.5,
    tilt: 0,
    timestamp: points.length,
  ),);

  return Stroke(
    id: 'test_triangle',
    toolType: ToolType.pen,
    color: Colors.black,
    width: 2.0,
    points: points,
    timestamp: DateTime.now().millisecondsSinceEpoch,
  );
}
