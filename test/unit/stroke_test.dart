import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:winote/domain/entities/stroke.dart';
import 'package:winote/domain/entities/stroke_point.dart';

void main() {
  group('Stroke 필압 계산 테스트', () {
    late Stroke stroke;

    setUp(() {
      stroke = Stroke(
        id: 'test-stroke',
        toolType: ToolType.pen,
        color: Colors.black,
        width: 4.0,
        points: [],
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
    });

    test('기본 필압 민감도(0.6)에서 압력 0.0 → 최소 굵기', () {
      final width = stroke.getWidthAtPressure(0.0, 0.6);
      // pow(0, 0.6) = 0, 0.3 + 0 * 1.5 = 0.3
      expect(width, closeTo(4.0 * 0.3, 0.01));
    });

    test('기본 필압 민감도(0.6)에서 압력 1.0 → 최대 굵기', () {
      final width = stroke.getWidthAtPressure(1.0, 0.6);
      // pow(1, 0.6) = 1, 0.3 + 1 * 1.5 = 1.8
      expect(width, closeTo(4.0 * 1.8, 0.01));
    });

    test('기본 필압 민감도(0.6)에서 압력 0.5 → 중간 굵기', () {
      final width = stroke.getWidthAtPressure(0.5, 0.6);
      // pow(0.5, 0.6) ≈ 0.66, 0.3 + 0.66 * 1.5 ≈ 1.29
      expect(width, greaterThan(4.0 * 0.3));
      expect(width, lessThan(4.0 * 1.8));
    });

    test('부드러운 민감도(0.4)는 낮은 압력에서 더 굵음', () {
      final softWidth = stroke.getWidthAtPressure(0.3, 0.4);
      final normalWidth = stroke.getWidthAtPressure(0.3, 0.6);
      final hardWidth = stroke.getWidthAtPressure(0.3, 0.8);

      // 민감도가 낮을수록 같은 압력에서 더 굵게
      expect(softWidth, greaterThan(normalWidth));
      expect(normalWidth, greaterThan(hardWidth));
    });

    test('강한 민감도(0.8)는 높은 압력에서만 굵어짐', () {
      // 낮은 압력(0.2)에서 차이 확인
      final softLow = stroke.getWidthAtPressure(0.2, 0.4);
      final hardLow = stroke.getWidthAtPressure(0.2, 0.8);

      // 높은 압력(0.9)에서 차이 확인
      final softHigh = stroke.getWidthAtPressure(0.9, 0.4);
      final hardHigh = stroke.getWidthAtPressure(0.9, 0.8);

      // 낮은 압력: soft가 훨씬 굵음
      expect(softLow - hardLow, greaterThan(0.5));

      // 높은 압력: 차이가 줄어듦
      expect(softHigh - hardHigh, lessThan(softLow - hardLow));
    });

    test('음수 압력은 0으로 클램프', () {
      final width = stroke.getWidthAtPressure(-0.5, 0.6);
      expect(width, closeTo(4.0 * 0.3, 0.01));
    });

    test('1 초과 압력은 1로 클램프', () {
      final width = stroke.getWidthAtPressure(1.5, 0.6);
      expect(width, closeTo(4.0 * 1.8, 0.01));
    });
  });

  group('Stroke 틸트 계산 테스트', () {
    late Stroke stroke;

    setUp(() {
      stroke = Stroke(
        id: 'test-stroke',
        toolType: ToolType.pen,
        color: Colors.black,
        width: 4.0,
        points: [],
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
    });

    test('틸트 0 → 기본 굵기 유지', () {
      final baseWidth = stroke.getWidthAtPressure(0.5);
      final tiltWidth = stroke.getWidthWithTilt(0.5, 0.0);
      expect(tiltWidth, closeTo(baseWidth, 0.01));
    });

    test('틸트 1 (최대) → 1.5배 굵기', () {
      final baseWidth = stroke.getWidthAtPressure(0.5);
      final tiltWidth = stroke.getWidthWithTilt(0.5, 1.0);
      expect(tiltWidth, closeTo(baseWidth * 1.5, 0.01));
    });

    test('틸트 0.5 → 1.25배 굵기', () {
      final baseWidth = stroke.getWidthAtPressure(0.5);
      final tiltWidth = stroke.getWidthWithTilt(0.5, 0.5);
      expect(tiltWidth, closeTo(baseWidth * 1.25, 0.01));
    });
  });

  group('Stroke 생성 및 포인트 추가 테스트', () {
    test('Stroke.create로 시작점 포함 생성', () {
      final startPoint = StrokePoint(
        x: 100,
        y: 200,
        pressure: 0.5,
        tilt: 0.0,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final stroke = Stroke.create(
        id: 'new-stroke',
        toolType: ToolType.pen,
        color: Colors.blue,
        width: 3.0,
        startPoint: startPoint,
      );

      expect(stroke.points.length, equals(1));
      expect(stroke.points.first.x, equals(100));
      expect(stroke.points.first.y, equals(200));
    });

    test('addPoint로 포인트 추가 시 boundingBox 확장', () {
      final stroke = Stroke.create(
        id: 'test',
        toolType: ToolType.pen,
        color: Colors.black,
        width: 2.0,
        startPoint: const StrokePoint(x: 0, y: 0, pressure: 0.5, tilt: 0.0, timestamp: 0),
      );

      stroke.addPoint(const StrokePoint(x: 100, y: 100, pressure: 0.5, tilt: 0.0, timestamp: 1));
      stroke.addPoint(const StrokePoint(x: 50, y: 150, pressure: 0.5, tilt: 0.0, timestamp: 2));

      expect(stroke.boundingBox.minX, equals(0));
      expect(stroke.boundingBox.minY, equals(0));
      expect(stroke.boundingBox.maxX, equals(100));
      expect(stroke.boundingBox.maxY, equals(150));
    });

    test('copyWith로 불변 복사', () {
      final original = Stroke(
        id: 'original',
        toolType: ToolType.pen,
        color: Colors.black,
        width: 2.0,
        points: [const StrokePoint(x: 0, y: 0, pressure: 0.5, tilt: 0.0, timestamp: 0)],
        timestamp: 0,
      );

      final copied = original.copyWith(color: Colors.red, width: 5.0);

      expect(copied.id, equals('original'));
      expect(copied.color, equals(Colors.red));
      expect(copied.width, equals(5.0));
      expect(original.color, equals(Colors.black)); // 원본 불변
    });
  });

  group('ToolType 테스트', () {
    test('모든 툴 타입 존재', () {
      expect(ToolType.values.length, greaterThanOrEqualTo(5));
      expect(ToolType.values.contains(ToolType.pen), isTrue);
      expect(ToolType.values.contains(ToolType.pencil), isTrue);
      expect(ToolType.values.contains(ToolType.marker), isTrue);
      expect(ToolType.values.contains(ToolType.highlighter), isTrue);
      expect(ToolType.values.contains(ToolType.eraser), isTrue);
    });
  });

  group('ShapeType 테스트', () {
    test('모든 도형 타입 존재', () {
      expect(ShapeType.values.length, greaterThanOrEqualTo(5));
      expect(ShapeType.values.contains(ShapeType.none), isTrue);
      expect(ShapeType.values.contains(ShapeType.line), isTrue);
      expect(ShapeType.values.contains(ShapeType.rectangle), isTrue);
      expect(ShapeType.values.contains(ShapeType.circle), isTrue);
      expect(ShapeType.values.contains(ShapeType.arrow), isTrue);
    });
  });
}
