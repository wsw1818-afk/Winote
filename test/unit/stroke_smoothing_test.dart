import 'package:flutter_test/flutter_test.dart';
import 'package:winote/domain/entities/stroke_point.dart';
import 'package:winote/core/services/stroke_smoothing_service.dart';

void main() {
  group('StrokeSmoothingService 테스트', () {
    late StrokeSmoothingService service;

    setUp(() {
      service = StrokeSmoothingService.instance;
      service.level = SmoothingLevel.medium;
      service.beginStroke();
    });

    test('싱글톤 인스턴스 확인', () {
      final instance1 = StrokeSmoothingService.instance;
      final instance2 = StrokeSmoothingService.instance;
      expect(identical(instance1, instance2), isTrue);
    });

    test('스무딩 레벨 변경', () {
      service.level = SmoothingLevel.light;
      expect(service.level, equals(SmoothingLevel.light));

      service.level = SmoothingLevel.strong;
      expect(service.level, equals(SmoothingLevel.strong));
    });

    test('스무딩 레벨 none에서 포인트 그대로 반환', () {
      service.level = SmoothingLevel.none;

      const point = StrokePoint(
        x: 100,
        y: 200,
        pressure: 0.5,
        tilt: 0.0,
        timestamp: 1000,
      );

      final filtered = service.filterPoint(point, []);
      expect(filtered, isNotNull);
      expect(filtered!.x, equals(100));
      expect(filtered.y, equals(200));
    });

    test('첫 번째 포인트는 항상 그대로 반환', () {
      service.level = SmoothingLevel.strong;

      const firstPoint = StrokePoint(
        x: 50,
        y: 50,
        pressure: 0.5,
        tilt: 0.0,
        timestamp: 0,
      );

      final result = service.filterPoint(firstPoint, []);
      expect(result, isNotNull);
      expect(result!.x, equals(50));
      expect(result.y, equals(50));
    });

    test('너무 가까운 포인트는 무시 (떨림 제거)', () {
      service.level = SmoothingLevel.medium;

      final existingPoints = [
        const StrokePoint(x: 100, y: 100, pressure: 0.5, tilt: 0.0, timestamp: 0),
      ];

      // 0.5 픽셀만 이동 - minDistance(1.5) 미만이므로 null 반환
      const tooClose = StrokePoint(
        x: 100.3,
        y: 100.4,
        pressure: 0.5,
        tilt: 0.0,
        timestamp: 10,
      );

      final result = service.filterPoint(tooClose, existingPoints);
      expect(result, isNull);
    });

    test('충분히 먼 포인트는 스무딩 적용 후 반환', () {
      service.level = SmoothingLevel.light;

      final existingPoints = [
        const StrokePoint(x: 100, y: 100, pressure: 0.5, tilt: 0.0, timestamp: 0),
      ];

      // 50 픽셀 이동 - 충분히 멂
      const farPoint = StrokePoint(
        x: 150,
        y: 100,
        pressure: 0.5,
        tilt: 0.0,
        timestamp: 100,
      );

      final result = service.filterPoint(farPoint, existingPoints);
      expect(result, isNotNull);
      // 스무딩이 적용되므로 정확히 150이 아닐 수 있음
      expect(result!.x, greaterThan(100));
    });

    test('beginStroke 호출 시 버퍼 초기화', () {
      service.level = SmoothingLevel.medium;

      // 몇 개 포인트 추가
      final points = <StrokePoint>[];
      for (int i = 0; i < 5; i++) {
        final point = StrokePoint(
          x: i * 10.0,
          y: i * 10.0,
          pressure: 0.5,
          tilt: 0.0,
          timestamp: i * 100,
        );
        final filtered = service.filterPoint(point, points);
        if (filtered != null) {
          points.add(filtered);
        }
      }

      // 새 스트로크 시작
      service.beginStroke();

      // 첫 포인트는 그대로 반환되어야 함
      const newFirst = StrokePoint(x: 0, y: 0, pressure: 0.5, tilt: 0.0, timestamp: 0);
      final result = service.filterPoint(newFirst, []);
      expect(result, isNotNull);
    });
  });

  group('SmoothingLevel 테스트', () {
    test('모든 스무딩 레벨 존재', () {
      expect(SmoothingLevel.values.length, equals(4));
      expect(SmoothingLevel.values.contains(SmoothingLevel.none), isTrue);
      expect(SmoothingLevel.values.contains(SmoothingLevel.light), isTrue);
      expect(SmoothingLevel.values.contains(SmoothingLevel.medium), isTrue);
      expect(SmoothingLevel.values.contains(SmoothingLevel.strong), isTrue);
    });
  });
}
